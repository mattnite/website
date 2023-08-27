path: []const u8,
date: []const u8,
title: []const u8,
description: []const u8,
keywords: []const []const u8,

const Post = @This();
const datetime = @import("datetime");
const Date = datetime.datetime.Date;

pub fn less_than(_: void, lhs_post: Post, rhs_post: Post) bool {
    const lhs = Date.parseIso(lhs_post.date) catch @panic("invalid date");
    const rhs = Date.parseIso(rhs_post.date) catch @panic("invalid date");
    return lhs.gt(rhs);
}
