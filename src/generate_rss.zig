const std = @import("std");
const Post = @import("Post.zig");

const datetime = @import("datetime");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    const posts = try std.json.parseFromSlice([]Post, arena.allocator(), args[1], .{});
    std.mem.sortUnstable(Post, posts.value, {}, Post.less_than);

    const output_path = args[2];
    const file = try std.fs.createFileAbsolute(output_path, .{});
    defer file.close();
    const writer = file.writer();

    try writer.writeAll(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<rss version="2.0">
        \\<channel>
        \\  <title>Matt Knight</title>
        \\  <link>https://mattnite.net/</link>
        \\  <description>Programming, Electronics</description>
        \\  <lastBuildDate>Wed, July 4 2018</lastBuildDate>
        \\
    );

    for (posts.value) |post| {
        const html_path = std.fs.path.join(arena.allocator(), &.{
            post.path[0 .. post.path.len - std.fs.path.extension(post.path).len],
        }) catch unreachable;
        try writer.print(
            \\  <item>
            \\    <title>{s}</title>
            \\    <link>https://mattnite.net/{s}</link>
            \\    <guid>https://mattnite.net/{s}</guid>
            \\    <description>{s}</description>
            \\    <pubDate>Wed, July 4 2018</pubDate>
            \\  </item>
            \\
        , .{ post.title, html_path, html_path, post.description });
    }

    try writer.writeAll(
        \\</channel>
        \\</rss>
        \\
    );
}
