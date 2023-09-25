const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Metadata = @import("Metadata.zig");
const clap = @import("clap");
const c = @cImport({
    @cInclude("cmark-gfm.h");
    @cInclude("cmark-gfm-core-extensions.h");
    @cInclude("tree_sitter/api.h");
});

extern fn tree_sitter_bash() callconv(.C) *c.TSLanguage;
extern fn tree_sitter_c() callconv(.C) *c.TSLanguage;
extern fn tree_sitter_cmake() callconv(.C) *c.TSLanguage;
extern fn tree_sitter_cpp() callconv(.C) *c.TSLanguage;
extern fn tree_sitter_zig() callconv(.C) *c.TSLanguage;

const template = @embedFile("template.html");
extern fn cmark_list_syntax_extensions([*c]c.cmark_mem) [*c]c.cmark_llist;

const Footnote = struct {
    name: []const u8,
    def_node: *c.cmark_node,
    ref_nodes: std.ArrayListUnmanaged(*c.cmark_node) = .{},
};

const parsers = std.ComptimeStringMap(*const fn () callconv(.C) *c.TSLanguage, .{
    .{ "bash", tree_sitter_bash },
    .{ "c", tree_sitter_c },
    .{ "cmake", tree_sitter_cmake },
    .{ "cpp", tree_sitter_cpp },
    .{ "sh", tree_sitter_bash },
    .{ "zig", tree_sitter_zig },
});

const HighlightQuery = struct { *const fn () callconv(.C) *c.TSLanguage, []const u8 };
const highlight_queries: []const HighlightQuery = &.{
    .{ tree_sitter_bash, @embedFile("parsers/bash/highlights.scm") },
    .{ tree_sitter_c, @embedFile("parsers/c/highlights.scm") },
    .{ tree_sitter_cmake, @embedFile("parsers/cmake/highlights.scm") },
    .{ tree_sitter_cpp, @embedFile("parsers/cpp/highlights.scm") },
    .{ tree_sitter_zig, @embedFile("parsers/zig/highlights.scm") },
};

/// Makes an assumption that any overlaps are perfect overlaps
const Highlight = struct {
    start: u32,
    end: u32,
    capture_name: std.StringHashMapUnmanaged(void) = .{},
};

fn write_highlighted_code(allocator: Allocator, writer: anytype, fence_info: ?[]const u8, code: []const u8) !void {
    std.log.info("FENCE INFO: {?s}", .{fence_info});
    if (fence_info) |fi| if (parsers.get(fi)) |language_fn| {
        const language = language_fn();
        const query_str: []const u8 = inline for (highlight_queries) |query_entry| {
            if (query_entry[0] == language_fn)
                break query_entry[1];
        } else @panic("language query missing");

        var highlights = std.AutoArrayHashMap(struct { start: u32, end: u32 }, std.StringArrayHashMapUnmanaged(void)).init(allocator);
        defer highlights.deinit();

        const parser = c.ts_parser_new();
        defer c.ts_parser_delete(parser);

        _ = c.ts_parser_set_language(parser, language);
        const tree = c.ts_parser_parse_string(parser, null, code.ptr, @intCast(code.len));
        defer c.ts_tree_delete(tree);

        var error_offset: u32 = undefined;
        var error_type: c.TSQueryError = undefined;
        const query = c.ts_query_new(language, query_str.ptr, @intCast(query_str.len), &error_offset, &error_type) orelse {
            std.log.err("err: {}, off: {}, fence_info: {?s}", .{ error_type, error_offset, fence_info });
            try writer.print(
                \\<code>
                \\{s}
                \\</code>
                \\
            , .{code});
            //return error.Query;
            return;
        };
        defer c.ts_query_delete(query);

        const query_cursor = c.ts_query_cursor_new();
        defer c.ts_query_cursor_delete(query_cursor);

        const root_node = c.ts_tree_root_node(tree);
        c.ts_query_cursor_exec(query_cursor, query, root_node);

        var match: c.TSQueryMatch = undefined;
        while (c.ts_query_cursor_next_match(query_cursor, &match)) {
            for (0..match.capture_count) |i| {
                const capture = match.captures[i];
                const node = capture.node;

                var len: u32 = undefined;
                if (c.ts_query_capture_name_for_id(query, capture.index, &len)) |capture_name_ptr| {
                    const capture_name = try allocator.dupe(u8, capture_name_ptr[0..len]);
                    const start = c.ts_node_start_byte(node);
                    const end = c.ts_node_end_byte(node);
                    if (capture_name.len < 0)
                        continue;

                    const result = try highlights.getOrPutValue(.{ .start = start, .end = end }, .{});
                    try result.value_ptr.put(allocator, capture_name, {});
                }
            }
        }

        for (highlights.keys(), highlights.values()) |key, set| {
            var buf: [4096]u8 = undefined;
            var buffer = std.io.fixedBufferStream(&buf);

            for (set.keys(), 0..) |capture, i| {
                if (i != 0)
                    try buffer.writer().writeAll(", ");

                try buffer.writer().print("{s}", .{capture});
            }

            std.log.info("[{}:{}]: {s}", .{ key.start, key.end, buffer.getWritten() });
        }

        try writer.writeAll("<code>\n");
        var idx: u32 = 0;
        for (highlights.keys(), highlights.values()) |pos, captures| {
            while (idx < pos.start) : (idx += 1)
                try writer.writeByte(code[idx]);

            try writer.writeAll("<span class=\"");
            for (captures.keys(), 0..) |capture, i| {
                if (i != 0)
                    try writer.writeByte(' ');

                const norm = try std.mem.replaceOwned(u8, allocator, capture, ".", "-");
                try writer.print("code-{s}", .{norm});
            }

            try writer.writeAll("\">");

            while (idx < pos.end) : (idx += 1)
                try writer.writeByte(code[idx]);

            try writer.writeAll("</span>");
        }
        try writer.writeAll(code[idx..]);

        try writer.writeAll("</code>\n");
        return;
    };

    try writer.print(
        \\<code>
        \\{s}
        \\</code>
        \\
    , .{code});
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit.
        \\-t, --title <str>      Title
        \\-a, --author <str>    Author
        \\-d, --date <str>        Date
        \\-D, --description <str> Description
        \\-s, --style_path <str>  Path to style.css
        \\-c, --debug
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();
    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    c.cmark_gfm_core_extensions_ensure_registered();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();
    const input_path = res.positionals[0];
    const output_path = res.positionals[1];

    const text_md = try std.fs.cwd().readFileAlloc(arena.allocator(), input_path, std.math.maxInt(usize));

    const output_file = try std.fs.createFileAbsolute(output_path, .{});
    defer output_file.close();

    var body = std.ArrayList(u8).init(allocator);
    const body_writer = body.writer();
    const options: c_int =
        c.CMARK_OPT_FOOTNOTES;
    const extensions = cmark_list_syntax_extensions(c.cmark_get_arena_mem_allocator());
    const parser = c.cmark_parser_new(options);
    defer c.cmark_parser_free(parser);

    _ = c.cmark_parser_attach_syntax_extension(parser, c.cmark_find_syntax_extension("table"));

    c.cmark_parser_feed(parser, text_md.ptr, text_md.len);

    var footnotes = std.ArrayList(Footnote).init(allocator);
    const document = c.cmark_parser_finish(parser);
    defer c.cmark_node_free(document);

    var it = c.cmark_node_first_child(document);
    while (it != null) : (it = c.cmark_node_next(it)) {
        const node_type = c.cmark_node_get_type(it);
        std.log.info("{x}: type={s}", .{ node_type, c.cmark_node_get_type_string(it) });
        switch (node_type) {
            c.CMARK_NODE_CODE_BLOCK => {
                if (c.cmark_node_get_literal(it)) |literal| {
                    const fence_info = c.cmark_node_get_fence_info(it);
                    try write_highlighted_code(allocator, body_writer, std.mem.span(fence_info), std.mem.span(literal));
                }
            },
            c.CMARK_NODE_PARAGRAPH => {
                try body_writer.writeAll("<p>");
                var child_it = c.cmark_node_first_child(it);
                while (child_it != null) : (child_it = c.cmark_node_next(child_it)) {
                    const child_type = c.cmark_node_get_type(child_it);
                    std.log.info("  {x}: type={s}", .{ child_type, c.cmark_node_get_type_string(child_it) });

                    if (child_type == c.CMARK_NODE_FOOTNOTE_REFERENCE) {
                        const def = c.cmark_node_parent_footnote_def(child_it) orelse return error.MissingFootnoteDef;
                        const name = std.mem.span(c.cmark_node_get_literal(def));
                        const index: usize = for (footnotes.items, 0..) |footnote, i| {
                            if (std.mem.eql(u8, footnote.name, name))
                                break i;
                        } else index: {
                            const len = footnotes.items.len;
                            try footnotes.append(.{
                                .name = name,
                                .def_node = def,
                            });

                            break :index len;
                        };

                        const entry = &footnotes.items[index];

                        const ref_idx = entry.ref_nodes.items.len;
                        try entry.ref_nodes.append(allocator, child_it.?);
                        try body_writer.print(
                            \\[<a class=footnote-ref href="#fn-{s}" id="fnref-{s}-{}" data-footnote-ref="">{s}</a>]
                        , .{
                            name,
                            name,
                            ref_idx,
                            name,
                        });
                    } else {
                        const html = c.cmark_render_html(child_it, options, extensions);
                        try body_writer.writeAll(std.mem.span(html));
                    }
                }

                try body_writer.writeAll("</p>");
            },
            c.CMARK_NODE_FOOTNOTE_DEFINITION => {}, // ignore

            else => {
                const html = c.cmark_render_html(it, options, extensions);
                try body_writer.writeAll(std.mem.span(html));
            },
        }
    }

    if (footnotes.items.len > 0) {
        try body_writer.writeAll(
            \\<h2>Footnotes</h2>
            \\<table class="references">
            \\
        );

        for (footnotes.items) |footnote| {
            const text = "text here";
            try body_writer.print(
                \\<tr id="fn-{s}">
                \\  <td>[{s}]:</td>
                \\  <td>{s} 
            , .{ footnote.name, footnote.name, text });

            for (footnote.ref_nodes.items, 0..) |_, i| {
                try body_writer.print(
                    \\<a href="#fnref-{s}-{}" class="footnote-backref" data-footnote-backref data-footnote-backref-idx="{s}-{}" aria-label="Back to reference {s}-{}">↩</a>
                , .{
                    footnote.name, i,
                    footnote.name, i,
                    footnote.name, i,
                });

                if (i != footnote.ref_nodes.items.len - 1) {
                    try body_writer.writeAll(", ");
                }
            }

            try body_writer.writeAll("</tr>\n");
        }

        try body_writer.writeAll(
            \\</table>
            \\
        );
    }

    const keywords_str = "";
    var buffered = std.io.bufferedWriter(output_file.writer());
    try buffered.writer().print(template, .{
        .title = res.args.title.?,
        .author = res.args.author.?,
        .date = res.args.date.?,
        .keywords = keywords_str,
        .description = res.args.description.?,
        .style_path = res.args.style_path.?,
        .body = body.items,
    });
    try buffered.flush();
}
