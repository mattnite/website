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
    .{
        .title = "Advent of Code 2023: Day 3",
        .path = "posts/aoc2023_03.md",
        .date = "2023-12-10",
        .description = "Notes I took for Aoc 2023 day 3.",
        .keywords = &.{"AoC"},
    },
};

const zine = @import("zine");

pub fn build(b: *Build) void {
    zine.website(b, .{
        .title = "Sample Website",
        .host_url = "https://sample.com",
        .content_dir_path = "content",
        .layouts_dir_path = "layouts",
        .assets_dir_path = "assets",
    });
}
