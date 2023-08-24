const std = @import("std");
const Post = @import("Post.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    const posts = try std.json.parseFromSlice([]const Post, arena.allocator(), args[1], .{});

    const output_path = args[2];
    const file = try std.fs.createFileAbsolute(output_path, .{});
    defer file.close();

    const input_text = try std.fs.cwd().readFileAlloc(arena.allocator(), "about.md", std.math.maxInt(usize));
    const writer = file.writer();
    try writer.writeAll(input_text);

    try writer.writeAll(
        \\
        \\## Latest Posts
        \\
        \\
    );

    // TODO: latest 3
    for (posts.value) |post| {
        const html_path = std.mem.join(arena.allocator(), "", &.{
            post.path[0 .. post.path.len - std.fs.path.extension(post.path).len],
            ".html",
        }) catch unreachable;
        try writer.print(
            \\- [{s}]({s})
            \\
        , .{
            post.title,
            html_path,
        });
    }
}