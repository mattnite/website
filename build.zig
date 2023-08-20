const std = @import("std");
const Build = std.Build;

const Post = struct {
    path: []const u8,
    date: []const u8,
    title: []const u8,
    description: []const u8,
};

fn generate_post(b: *Build, post: Post, optimize: std.builtin.OptimizeMode) void {
    const basename = std.fs.path.basename(post.path);
    const postname = basename[0 .. basename.len - std.fs.path.extension(basename).len];
    const pandoc = b.addSystemCommand(&.{
        "pandoc",
        "-f",
        "markdown-smart",
        "-t",
        "html",
        "-s",
        "--fail-if-warnings=true",
    });
    pandoc.addArg("--template");
    pandoc.addFileArg(.{ .path = "post.pandoc" });
    pandoc.addArgs(&.{ "--metadata", b.fmt("title={s}", .{post.title}) });
    pandoc.addArgs(&.{ "--metadata", "css=../style.css" });
    pandoc.addArgs(&.{ "--metadata", b.fmt("debug={}", .{optimize == .Debug}) });
    pandoc.addArgs(&.{ "--metadata", "author-meta=Matt Knight" });
    pandoc.addArgs(&.{ "--metadata", b.fmt("date-meta={s}", .{post.date}) });
    pandoc.addArgs(&.{ "--metadata", b.fmt("description-meta={s}", .{post.description}) });

    pandoc.addFileArg(.{ .path = post.path });
    const post_path = pandoc.addPrefixedOutputFileArg("-o", b.fmt("{s}.html", .{postname}));
    const install = b.addInstallFile(post_path, b.fmt("www/posts/{s}.html", .{postname}));
    b.getInstallStep().dependOn(&install.step);
}

const posts: []const Post = &.{
    .{
        .title = "Bare Minimum STM32 Toolchain Setup",
        .path = "posts/bare-minimum-stm32-toolchain-setup.md",
        .date = "2019-05-24",
        .description = "",
    },
};

pub fn build(b: *Build) void {
    const optimize = b.standardOptimizeOption(.{});
    for (posts) |post|
        generate_post(b, post, optimize);

    b.installFile("style.css", "www/style.css");
    b.installDirectory(.{
        .source_dir = .{ .path = "fonts" },
        .install_dir = .{ .prefix = {} },
        .install_subdir = "www/fonts",
    });
}
