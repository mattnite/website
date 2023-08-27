const std = @import("std");
const Post = @import("Post.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    const posts = try std.json.parseFromSlice([]Post, arena.allocator(), args[1], .{});
    std.mem.sortUnstable(Post, posts.value, {}, Post.less_than);

    const input_path = args[2];
    const input_text = try std.fs.cwd().readFileAlloc(arena.allocator(), input_path, std.math.maxInt(usize));

    const output_path = args[3];
    const file = try std.fs.createFileAbsolute(output_path, .{});
    defer file.close();
    const writer = file.writer();
    try writer.writeAll(input_text);

    try writer.writeAll(
        \\
        \\## Posts
        \\
        \\
    );

    for (posts.value) |post| {
        const html_path = std.fs.path.join(arena.allocator(), &.{
            post.path[0 .. post.path.len - std.fs.path.extension(post.path).len],
            "index.html",
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
