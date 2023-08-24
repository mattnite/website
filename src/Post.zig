path: []const u8,
date: []const u8,
title: []const u8,
description: []const u8,

const Post = @This();
const datetime = @import("datetime");

pub fn less_than(_: void, lhs: Post, rhs: Post) bool {
    _ = lhs;
    _ = rhs;
    return false;
}
