const std = @import("std");
const Build = std.Build;
const RunStep = Build.RunStep;
const LazyPath = Build.LazyPath;
const OptimizeMode = std.builtin.OptimizeMode;
const CompileStep = Build.CompileStep;

const datetime = @import("datetime");
const Post = @import("src/Post.zig");
const Metadata = @import("src/Metadata.zig");

const drafts: []const Post = &.{
    .{
        .title = "Test post",
        .path = "posts/test.md",
        .date = "2019-05-24",
        .description = "",
        .keywords = &.{},
    },
};

// generate_index will automatically sort based on the date
const posts: []const Post = &.{
    .{
        .title = "Template Metaprogramming For Register Abstraction",
        .path = "posts/register-abstraction.md",
        .date = "2019-09-03",
        .description = "Some cursed metaprogramming in C++.",
        .keywords = &.{},
    },
    .{
        .title = "@import and Packages",
        .path = "posts/import-and-packages.md",
        .date = "2021-07-27",
        .description = "The system underlaying Zig packages.",
        .keywords = &.{},
    },
    .{
        .title = "Bare Minimum STM32 Toolchain Setup",
        .path = "posts/bare-minimum-stm32-toolchain-setup.md",
        .date = "2019-05-24",
        .description = "My initial foray into embeddded toolchains.",
        .keywords = &.{},
    },
    .{
        .title = "How libbpf Loads Maps",
        .path = "posts/libbpf-maps.md",
        .date = "2020-10-16",
        .description = "A deep dive into libbpf fundamentals.",
        .keywords = &.{},
    },
    .{
        .title = "Advent of Code 2023: Day 1",
        .path = "posts/aoc2023_01.md",
        .date = "2023-12-08",
        .description = "Notes I took for Aoc 2023 day 1.",
        .keywords = &.{"AoC"},
    },
    .{
        .title = "Advent of Code 2023: Day 2",
        .path = "posts/aoc2023_02.md",
        .date = "2023-12-09",
        .description = "Notes I took for Aoc 2023 day 2.",
        .keywords = &.{"AoC"},
    },
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    std.fs.cwd().deleteTree("zig-out") catch {};

    const clap_dep = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    const datetime_dep = b.dependency("datetime", .{
        .target = target,
        .optimize = optimize,
    });

    const cmark_dep = b.dependency("cmark", .{
        .target = target,
        .optimize = optimize,
    });

    const libcmark = cmark_dep.artifact("cmark-gfm");
    const libcmark_extensions = cmark_dep.artifact("cmark-gfm-extensions");

    const treesitter = b.dependency("treesitter", .{
        .target = target,
        .optimize = optimize,
    });

    const libtreesitter = treesitter.artifact("tree-sitter");

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });

    const libpcre2 = pcre2_dep.artifact("pcre2");

    var all_posts = std.ArrayList(Post).init(b.allocator);
    all_posts.appendSlice(posts) catch unreachable;
    if (optimize == .Debug)
        all_posts.appendSlice(drafts) catch unreachable;

    const gen_post_exe = b.addExecutable(.{
        .name = "generate_post",
        .root_source_file = .{ .path = "src/generate_post.zig" },
        .target = target,
        .optimize = optimize,
    });
    gen_post_exe.addModule("clap", clap_dep.module("clap"));
    gen_post_exe.linkLibrary(libcmark);
    gen_post_exe.linkLibrary(libcmark_extensions);
    gen_post_exe.linkLibrary(libtreesitter);
    gen_post_exe.linkLibrary(libpcre2);
    gen_post_exe.addCSourceFiles(&.{
        "src/parsers/bash/parser.c",
        "src/parsers/bash/scanner.c",
        "src/parsers/c/parser.c",
        "src/parsers/cmake/parser.c",
        "src/parsers/cmake/scanner.c",
        "src/parsers/cpp/parser.c",
        "src/parsers/cpp/scanner.c",
        "src/parsers/zig/parser.c",
    }, &.{});

    const gen_index_exe = b.addExecutable(.{
        .name = "generate_index",
        .root_source_file = .{ .path = "src/generate_index.zig" },
        .target = target,
        .optimize = optimize,
    });
    gen_index_exe.addModule("datetime", datetime_dep.module("zig-datetime"));

    const gen_rss_exe = b.addExecutable(.{
        .name = "generate_rss",
        .root_source_file = .{ .path = "src/generate_rss.zig" },
        .target = target,
        .optimize = optimize,
    });
    gen_rss_exe.addModule("datetime", datetime_dep.module("zig-datetime"));

    const is_debug = optimize == .Debug;
    generate_index(b, .{
        .gen_index_exe = gen_index_exe,
        .gen_post_exe = gen_post_exe,
        .ordered_posts = all_posts.items,
        .debug = is_debug,
    });

    generate_rss(b, .{
        .gen_rss_exe = gen_rss_exe,
        .ordered_posts = all_posts.items,
        .debug = is_debug,
    });
    for (all_posts.items) |post|
        generate_post(b, .{
            .exe = gen_post_exe,
            .path = post.path,
            .metadata = .{
                .debug = is_debug,
                .title = post.title,
                .author = "Matt Knight",
                .date = post.date,
                .description = post.description,
                .keywords = post.keywords,
                .style_path = "../../style.css",
            },
        });

    b.installFile("style.css", "www/style.css");
    b.installDirectory(.{
        .source_dir = .{ .path = "fonts" },
        .install_dir = .{ .prefix = {} },
        .install_subdir = "www/fonts",
    });
    b.installDirectory(.{
        .source_dir = .{ .path = "images" },
        .install_dir = .{ .prefix = {} },
        .install_subdir = "www/images",
    });

    // TODO: more than one set of slides
    const unzip = b.addSystemCommand(&.{ "unzip", "slides/sycl-workshop-2023.zip" });
    const workshop_slides = unzip.addPrefixedOutputFileArg("-d", "sycl-workshop-2023");
    b.installDirectory(.{
        .source_dir = workshop_slides,
        .install_dir = .{ .prefix = {} },
        .install_subdir = "www/slides/sycl-workshop-2023",
    });

    const user = b.option([]const u8, "user", "rsync user");
    const host = b.option([]const u8, "host", "rsync host");

    const rsync = b.addSystemCommand(&.{
        "rsync",
        "-v",
        "-r",
        "--delete",
        "./zig-out/www/",
    });
    rsync.step.dependOn(b.getInstallStep());

    if (user != null and host != null)
        rsync.addArg(b.fmt("{s}@{s}:/root/config/www/", .{ user.?, host.? }));

    const deploy = b.step("deploy", "Deploy website to prod");
    deploy.dependOn(&rsync.step);
}

fn generate_index(
    b: *Build,
    opts: struct {
        gen_index_exe: *CompileStep,
        gen_post_exe: *CompileStep,
        ordered_posts: []const Post,
        debug: bool,
    },
) void {
    const posts_json = std.json.stringifyAlloc(b.allocator, opts.ordered_posts, .{}) catch unreachable;

    const gen_index_run = b.addRunArtifact(opts.gen_index_exe);
    gen_index_run.addArg(posts_json);
    gen_index_run.addFileArg(.{ .path = "about.md" });
    const index_md = gen_index_run.addOutputFileArg("index.md");

    const gen_post_run = b.addRunArtifact(opts.gen_post_exe);
    gen_post_run.addArgs(&.{ "--title", "mattnite" });
    gen_post_run.addArgs(&.{ "--author", "MattKnight" });
    gen_post_run.addArgs(&.{ "--date", "" });
    gen_post_run.addArgs(&.{ "--description", "" });
    gen_post_run.addArgs(&.{ "--style_path", "style.css" });

    if (opts.debug)
        gen_post_run.addArg("--debug");

    gen_post_run.addFileArg(index_md);
    const index_html = gen_post_run.addOutputFileArg("index.html");

    const install = b.addInstallFile(index_html, "www/index.html");
    b.getInstallStep().dependOn(&install.step);
}

fn generate_rss(b: *Build, opts: struct {
    gen_rss_exe: *CompileStep,
    ordered_posts: []const Post,
    debug: bool,
}) void {
    const posts_json = std.json.stringifyAlloc(b.allocator, opts.ordered_posts, .{}) catch unreachable;

    const gen = b.addRunArtifact(opts.gen_rss_exe);
    gen.addArg(posts_json);

    const rss_path = gen.addOutputFileArg("feed.xml");

    const install = b.addInstallFile(rss_path, "www/feed.xml");
    b.getInstallStep().dependOn(&install.step);
}

fn generate_post(b: *Build, opts: struct {
    exe: *CompileStep,
    path: []const u8,
    metadata: Metadata,
}) void {
    const basename = std.fs.path.basename(opts.path);
    const postname = basename[0 .. basename.len - std.fs.path.extension(basename).len];
    const gen = b.addRunArtifact(opts.exe);

    gen.addArgs(&.{ "--title", opts.metadata.title });
    gen.addArgs(&.{ "--author", opts.metadata.author });
    gen.addArgs(&.{ "--date", opts.metadata.date });
    gen.addArgs(&.{ "--description", opts.metadata.description });
    gen.addArgs(&.{ "--style_path", opts.metadata.style_path });

    if (opts.metadata.debug)
        gen.addArg("--debug");

    // TODO: keywords
    gen.addFileArg(.{ .path = opts.path });
    const post_path = gen.addOutputFileArg(b.fmt("{s}.html", .{postname}));

    const install = b.addInstallFile(post_path, b.fmt("www/posts/{s}/index.html", .{postname}));
    b.getInstallStep().dependOn(&install.step);
}
