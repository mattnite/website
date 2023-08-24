const std = @import("std");
const Build = std.Build;
const RunStep = Build.RunStep;
const LazyPath = Build.LazyPath;
const OptimizeMode = std.builtin.OptimizeMode;

const datetime = @import("datetime");
const Post = @import("src/Post.zig");

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var ordered_posts = std.ArrayList(Post).init(b.allocator);

    const cmark_dep = b.dependency("cmark", .{
        .target = target,
        .optimize = optimize,
    });

    const libcmark = cmark_dep.artifact("cmark-gfm");

    ordered_posts.appendSlice(posts) catch unreachable;

    if (optimize == .Debug)
        ordered_posts.appendSlice(drafts) catch unreachable;

    std.mem.sort(Post, ordered_posts.items, {}, Post.less_than);

    generate_index(b, optimize, ordered_posts.items);
    generate_archive(b, optimize, ordered_posts.items);
    generate_rss(b, ordered_posts.items);
    for (ordered_posts.items) |post|
        generate_post(b, post, optimize);

    b.installFile("style.css", "www/style.css");
    b.installDirectory(.{
        .source_dir = .{ .path = "fonts" },
        .install_dir = .{ .prefix = {} },
        .install_subdir = "www/fonts",
    });

    const deploy = b.step("deploy", "Deploy website do prod!");
    _ = deploy;

    const dumper = b.addExecutable(.{
        .name = "dumper",
        .root_source_file = .{ .path = "dumper.zig" },
    });
    dumper.linkLibrary(libcmark);
    b.installArtifact(dumper);
}

const posts: []const Post = &.{
    .{
        .title = "Bare Minimum STM32 Toolchain Setup",
        .path = "posts/bare-minimum-stm32-toolchain-setup.md",
        .date = "2019-05-24",
        .description = "",
    },
    .{
        .title = "Test post",
        .path = "posts/test.md",
        .date = "2019-05-24",
        .description = "",
    },
};

const drafts: []const Post = &.{};

fn generate_index(
    b: *Build,
    optimize: std.builtin.OptimizeMode,
    ordered_posts: []const Post,
) void {
    const exe = b.addExecutable(.{
        .name = "generate_index",
        .root_source_file = .{ .path = "src/generate_index.zig" },
    });
    const exe_run = b.addRunArtifact(exe);

    var posts_str = std.ArrayList(u8).init(b.allocator);
    std.json.stringify(ordered_posts, .{}, posts_str.writer()) catch unreachable;
    exe_run.addArg(posts_str.items);
    const index_md = exe_run.addOutputFileArg("index.md");

    const pandoc = Pandoc.add(b, optimize);
    pandoc.add_template(.{ .path = "index.pandoc" });
    pandoc.add_metadata("title", "mattnite");
    pandoc.add_input(index_md);
    const index_html = pandoc.add_output("index.html");

    const install = b.addInstallFile(index_html, "www/index.html");
    b.getInstallStep().dependOn(&install.step);
}

fn generate_archive(b: *Build, optimize: OptimizeMode, ordered_posts: []const Post) void {
    _ = b;
    _ = ordered_posts;
    _ = optimize;
}

fn generate_rss(b: *Build, ordered_posts: []const Post) void {
    _ = b;
    _ = ordered_posts;
}

const Pandoc = struct {
    b: *Build,
    run_step: *RunStep,

    fn add(b: *Build, optimize: std.builtin.OptimizeMode) Pandoc {
        const pandoc = Pandoc{
            .b = b,
            .run_step = b.addSystemCommand(&.{
                "pandoc",
                "-f",
                "gfm-smart",
                "-t",
                "html",
                "-s",
                "--fail-if-warnings=true",
            }),
        };

        pandoc.add_metadata("debug", b.fmt("{}", .{optimize == .Debug}));
        pandoc.add_metadata("author-meta", "Matt Knight");
        return pandoc;
    }

    fn add_template(pandoc: Pandoc, path: LazyPath) void {
        pandoc.run_step.addArg("--template");
        pandoc.run_step.addFileArg(path);
    }

    fn add_metadata(pandoc: Pandoc, key: []const u8, value: []const u8) void {
        pandoc.run_step.addArgs(&.{
            "--metadata",
            pandoc.b.fmt("{s}={s}", .{ key, value }),
        });
    }

    fn add_input(pandoc: Pandoc, input: LazyPath) void {
        pandoc.run_step.addFileArg(input);
    }

    fn add_output(pandoc: Pandoc, output_name: []const u8) LazyPath {
        return pandoc.run_step.addPrefixedOutputFileArg("-o", output_name);
    }
};

fn generate_post(b: *Build, post: Post, optimize: std.builtin.OptimizeMode) void {
    const basename = std.fs.path.basename(post.path);
    const postname = basename[0 .. basename.len - std.fs.path.extension(basename).len];
    const pandoc = Pandoc.add(b, optimize);
    pandoc.add_template(.{ .path = "post.pandoc" });
    pandoc.add_metadata("title", post.title);
    pandoc.add_metadata("date-meta", post.date);
    pandoc.add_metadata("description-meta", post.description);
    pandoc.add_input(.{ .path = post.path });

    const post_path = pandoc.add_output(b.fmt("{s}.html", .{postname}));
    const install = b.addInstallFile(post_path, b.fmt("www/posts/{s}.html", .{postname}));
    b.getInstallStep().dependOn(&install.step);
}
