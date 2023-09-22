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
        .description = "",
        .keywords = &.{},
    },
    .{
        .title = "@import and Packages",
        .path = "posts/import-and-packages.md",
        .date = "2021-07-27",
        .description = "",
        .keywords = &.{},
    },
    .{
        .title = "Bare Minimum STM32 Toolchain Setup",
        .path = "posts/bare-minimum-stm32-toolchain-setup.md",
        .date = "2019-05-24",
        .description = "",
        .keywords = &.{},
    },
    .{
        .title = "How libbpf Loads Maps",
        .path = "posts/libbpf-maps.md",
        .date = "2020-10-16",
        .description = "",
        .keywords = &.{},
    },
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    std.fs.cwd().deleteTree("zig-out") catch {};

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
    gen_post_exe.linkLibrary(libcmark);
    gen_post_exe.linkLibrary(libcmark_extensions);

    const gen_index_exe = b.addExecutable(.{
        .name = "generate_index",
        .root_source_file = .{ .path = "src/generate_index.zig" },
        .target = target,
        .optimize = optimize,
    });
    gen_index_exe.addModule("datetime", datetime_dep.module("zig-datetime"));

    const is_debug = optimize == .Debug;
    generate_index(b, .{
        .gen_index_exe = gen_index_exe,
        .gen_post_exe = gen_post_exe,
        .ordered_posts = all_posts.items,
        .debug = is_debug,
    });

    generate_rss(b, all_posts.items);
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
    const metadata_json = std.json.stringifyAlloc(b.allocator, .{
        .debug = opts.debug,
        .title = "mattnite",
        .author = "Matt Knight",
        .date = "", // TODO: today
        .description = "",
        .keywords = &.{},
        .style_path = "style.css",
    }, .{}) catch unreachable;

    const gen_index_run = b.addRunArtifact(opts.gen_index_exe);
    gen_index_run.addArg(posts_json);
    gen_index_run.addFileArg(.{ .path = "about.md" });
    const index_md = gen_index_run.addOutputFileArg("index.md");

    const gen_post_run = b.addRunArtifact(opts.gen_post_exe);
    gen_post_run.addArg(metadata_json);
    gen_post_run.addFileArg(index_md);
    const index_html = gen_post_run.addOutputFileArg("index.html");

    const install = b.addInstallFile(index_html, "www/index.html");
    b.getInstallStep().dependOn(&install.step);
}

fn generate_rss(b: *Build, ordered_posts: []const Post) void {
    _ = b;
    _ = ordered_posts;
}

fn generate_post(b: *Build, opts: struct {
    exe: *CompileStep,
    path: []const u8,
    metadata: Metadata,
}) void {
    const basename = std.fs.path.basename(opts.path);
    const postname = basename[0 .. basename.len - std.fs.path.extension(basename).len];
    const gen = b.addRunArtifact(opts.exe);

    const metadata_json = std.json.stringifyAlloc(b.allocator, opts.metadata, .{}) catch unreachable;
    gen.addArg(metadata_json);
    gen.addFileArg(.{ .path = opts.path });
    const post_path = gen.addOutputFileArg(b.fmt("{s}.html", .{postname}));

    const install = b.addInstallFile(post_path, b.fmt("www/posts/{s}/index.html", .{postname}));
    b.getInstallStep().dependOn(&install.step);
}
