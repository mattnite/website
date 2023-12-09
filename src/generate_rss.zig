const std = @import("std");
const Allocator = std.mem.Allocator;
const Post = @import("Post.zig");

const datetime = @import("datetime");
const Date = datetime.datetime.Date;

fn format_as_rfc822(date: Date, allocator: Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}, {s} {} {}", .{
        switch (date.dayOfWeek()) {
            .Monday => "Mon",
            .Tuesday => "Tues",
            .Wednesday => "Wed",
            .Thursday => "Thurs",
            .Friday => "Fri",
            .Saturday => "Sat",
            .Sunday => "Sun",
        },
        date.monthName(),
        date.day,
        date.year,
    });
}

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

    const now = Date.now();
    try writer.print(
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<rss version="2.0">
        \\<channel>
        \\  <title>Matt Knight</title>
        \\  <link>https://mattnite.net/</link>
        \\  <description>Programming, Electronics</description>
        \\  <lastBuildDate>{s}</lastBuildDate>
        \\
    , .{try format_as_rfc822(now, arena.allocator())});

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
            \\    <pubDate>{s}</pubDate>
            \\  </item>
            \\
        , .{
            post.title,
            html_path,
            html_path,
            post.description,
            try format_as_rfc822(try Date.parseIso(post.date), arena.allocator()),
        });
    }

    try writer.writeAll(
        \\</channel>
        \\</rss>
        \\
    );
}
