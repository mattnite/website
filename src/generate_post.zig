const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Metadata = @import("Metadata.zig");
const clap = @import("clap");
const c = @cImport({
    @cInclude("cmark-gfm.h");
    @cInclude("cmark-gfm-core-extensions.h");
    @cInclude("tree_sitter/api.h");
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
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
    //.{ "c", tree_sitter_c },
    .{ "cmake", tree_sitter_cmake },
    //.{ "cpp", tree_sitter_cpp },
    .{ "sh", tree_sitter_bash },
    .{ "zig", tree_sitter_zig },
});

const HighlightQuery = struct { *const fn () callconv(.C) *c.TSLanguage, []const u8 };
const highlight_queries: []const HighlightQuery = &.{
    .{ tree_sitter_bash, @embedFile("parsers/bash/highlights.scm") },
    //.{ tree_sitter_c, @embedFile("parsers/c/highlights.scm") },
    .{ tree_sitter_cmake, @embedFile("parsers/cmake/highlights.scm") },
    //.{ tree_sitter_cpp, @embedFile("parsers/cpp/highlights.scm") },
    .{ tree_sitter_zig, @embedFile("parsers/zig/highlights.scm") },
};

/// Makes an assumption that any overlaps are perfect overlaps
const Highlight = struct {
    start: u32,
    end: u32,
    capture_name: std.StringHashMapUnmanaged(void) = .{},
};

const NodeId = struct {
    start: u32,
    end: u32,
};

const Predicate = struct {
    steps: []const c.TSQueryPredicateStep,
};

const Captures = struct {
    default: []const u8 = "",
    predicates: std.ArrayListUnmanaged(Predicate) = .{},
};

fn get_capture_name(query: *c.TSQuery, value_id: u32) ?[]const u8 {
    var len: u32 = undefined;
    const ptr = c.ts_query_capture_name_for_id(query, value_id, &len) orelse return null;
    var ret: []const u8 = undefined;
    ret.ptr = ptr;
    ret.len = len;
    return ret;
}

fn get_pred_str(query: *c.TSQuery, value_id: u32) ?[]const u8 {
    var len: u32 = undefined;
    const ptr = c.ts_query_string_value_for_id(query, value_id, &len) orelse return null;
    var ret: []const u8 = undefined;
    ret.ptr = ptr;
    ret.len = len;
    return ret;
}

fn pred_eq(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    assert(predicate.steps.len == 4);

    // TODO: how does this handle two captures? (see vim source code)
    const str = get_pred_str(query, predicate.steps[2].value_id).?;
    return std.mem.eql(u8, token, str);
}

fn pred_any_of(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    return for (predicate.steps[2..]) |step| {
        if (step.type == c.TSQueryPredicateStepTypeDone)
            break false;

        const str = get_pred_str(query, step.value_id).?;
        if (std.mem.eql(u8, token, str))
            break true;
    } else false;
}

extern fn pcre2_compile_8([*c]const u8, usize, u32, *c_int, ?*c.PCRE2_SIZE, ?*anyopaque) ?*anyopaque;
extern fn pcre2_match_data_create_from_pattern_8(?*anyopaque, ?*anyopaque) ?*anyopaque;
extern fn pcre2_match_8(?*anyopaque, [*c]const u8, usize, usize, u32, ?*anyopaque, ?*anyopaque) c_int;

// regex match
fn pred_match(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    const p = get_pred_str(query, predicate.steps[2].value_id) orelse unreachable;
    const pattern: []const u8 = if (std.mem.startsWith(u8, p, "\\c"))
        p[2..]
    else
        p;

    assert(predicate.steps[2].type == c.TSQueryPredicateStepTypeString);
    var errornumber: c_int = undefined;
    var erroroffset: usize = undefined;

    const re = pcre2_compile_8(pattern.ptr, pattern.len, 0, &errornumber, &erroroffset, null);
    assert(re != null);

    //if (re == NULL)
    //  {
    //  PCRE2_UCHAR buffer[256];
    //  pcre2_get_error_message(errornumber, buffer, sizeof(buffer));
    //  printf("PCRE2 compilation failed at offset %d: %s\n", (int)erroroffset,
    //    buffer);
    //  return 1;
    //  }
    //
    const match_data = pcre2_match_data_create_from_pattern_8(re, null);
    //
    //* Now run the match. */
    //
    const rc = pcre2_match_8(re, //* the compiled pattern */
        token.ptr, //* the subject string */
        token.len, //* the length of the subject */
        0, //* start at offset 0 in the subject */
        0, //* default options */
        match_data, //* block for storing the result */
        null); //* use default match context */

    assert((rc >= 0) or rc == c.PCRE2_ERROR_NOMATCH);
    return (rc >= 0);

    //
    //* Matching failed: handle error cases */
    //
    //if (rc < 0)
    //  {
    //  switch(rc)
    //    {
    //    case PCRE2_ERROR_NOMATCH: printf("No match\n"); break;
    //    /*
    //    Handle other special cases if you like
    //    */
    //    default: printf("Matching error %d\n", rc); break;
    //    }
    //  pcre2_match_data_free(match_data);   /* Release memory used for the match */
    //  pcre2_code_free(re);                 /*   data and the compiled pattern. */
    //  return 1;
    //  }
    //
    //* Match succeeded. Get a pointer to the output vector, where string offsets
    //are stored. */
    //
    //ovector = pcre2_get_ovector_pointer(match_data);
    //
    //if (rc == 0)
    //  printf("ovector was not big enough for all the captured substrings\n");

    //printf("Match succeeded at offset %d\n", (int)ovector[0]);
}

// lua string.find function
fn pred_lua_match(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    _ = query;
    _ = token;
    _ = predicate;

    return false;
}

// ignore directives like set!
fn pred_set(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    _ = query;
    _ = token;
    _ = predicate;

    return false;
}

fn pred_has_ancestor(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    _ = query;
    _ = token;
    _ = predicate;

    return false;
}

fn pred_not_has_parent(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    _ = query;
    _ = token;
    _ = predicate;

    return false;
}

const predicates = std.ComptimeStringMap(*const fn (*c.TSQuery, []const u8, Predicate) bool, .{
    .{ "eq?", pred_eq },
    .{ "any-of?", pred_any_of },
    .{ "match?", pred_match },
    .{ "lua-match?", pred_lua_match },
    .{ "set!", pred_set },
    .{ "has-ancestor?", pred_has_ancestor },
    .{ "not-has-parent?", pred_not_has_parent },
});

fn evaluate_predicate(query: *c.TSQuery, token: []const u8, predicate: Predicate) bool {
    // TODO: assert that only two predicate expressions (only one 'done' step)
    assert(predicate.steps[0].type == c.TSQueryPredicateStepTypeString);
    const predicate_name = get_pred_str(query, predicate.steps[0].value_id).?;
    const predicate_fn = predicates.get(predicate_name) orelse {
        std.log.warn("unhandled predicate function: {s}", .{predicate_name});
        return false;
    };

    return predicate_fn(query, token, predicate);
}

fn evaluate_capture(allocator: Allocator, query: *c.TSQuery, token: []const u8, captures: Captures) ![]const u8 {
    var capture_names = std.ArrayList([]const u8).init(allocator);
    defer capture_names.deinit();

    var eval = std.bit_set.IntegerBitSet(64).initEmpty();
    for (captures.predicates.items, 0..) |predicate, i| {
        const capture_name = get_capture_name(query, predicate.steps[1].value_id).?;
        try capture_names.append(capture_name);
        eval.setValue(i, evaluate_predicate(query, token, predicate));
    }

    return if (eval.mask == 0)
        captures.default
    else
        capture_names.items[eval.findFirstSet().?];
}

fn write_highlighted_code(allocator: Allocator, writer: anytype, fence_info: ?[]const u8, code: []const u8) !void {
    //std.log.info("FENCE INFO: {?s}", .{fence_info});
    if (fence_info) |fi| {
        if (parsers.get(fi)) |language_fn| {
            const language = language_fn();
            const query_str: []const u8 = inline for (highlight_queries) |query_entry| {
                if (query_entry[0] == language_fn)
                    break query_entry[1];
            } else @panic("language query missing");

            var captures = std.AutoArrayHashMap(NodeId, Captures).init(allocator);
            defer captures.deinit();

            const parser = c.ts_parser_new();
            defer c.ts_parser_delete(parser);

            _ = c.ts_parser_set_language(parser, language);
            const tree = c.ts_parser_parse_string(parser, null, code.ptr, @intCast(code.len));
            defer c.ts_tree_delete(tree);

            var error_offset: u32 = undefined;
            var error_type: c.TSQueryError = undefined;
            const query = c.ts_query_new(language, query_str.ptr, @intCast(query_str.len), &error_offset, &error_type) orelse {
                std.log.err("err: {}, off: {}, fence_info: {?s}", .{ error_type, error_offset, fence_info });
                return error.Query;
            };
            defer c.ts_query_delete(query);

            //const pattern_count = c.ts_query_pattern_count(query);
            //const capture_count = c.ts_query_capture_count(query);
            //const string_count = c.ts_query_string_count(query);

            //std.log.info("counts, pattern: {}, capture: {}, string: {}", .{ pattern_count, capture_count, string_count });

            const query_cursor = c.ts_query_cursor_new();
            defer c.ts_query_cursor_delete(query_cursor);

            const root_node = c.ts_tree_root_node(tree);
            c.ts_query_cursor_exec(query_cursor, query, root_node);

            var match: c.TSQueryMatch = undefined;
            while (c.ts_query_cursor_next_match(query_cursor, &match)) {
                const pred_steps = pred_steps: {
                    var step_count: u32 = undefined;
                    const step_ptr = c.ts_query_predicates_for_pattern(query, match.pattern_index, &step_count);

                    if (step_ptr == null)
                        break :pred_steps &.{};

                    var ret: []const c.TSQueryPredicateStep = undefined;
                    ret.ptr = @ptrCast(step_ptr);
                    ret.len = step_count;
                    break :pred_steps ret;
                };

                var buf: [4096]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);
                for (pred_steps, 0..) |step, i| {
                    if (i != 0)
                        try fbs.writer().writeAll(" ");

                    const value: []const u8 = switch (step.type) {
                        c.TSQueryPredicateStepTypeDone => "",
                        c.TSQueryPredicateStepTypeCapture => blk: {
                            var len: u32 = undefined;
                            if (c.ts_query_capture_name_for_id(query, step.value_id, &len)) |ptr| {
                                var ret: []const u8 = undefined;
                                ret.ptr = ptr;
                                ret.len = len;
                                break :blk ret;
                            } else break :blk "";
                        },
                        c.TSQueryPredicateStepTypeString => blk: {
                            var len: u32 = undefined;
                            if (c.ts_query_string_value_for_id(query, step.value_id, &len)) |ptr| {
                                var ret: []const u8 = undefined;
                                ret.ptr = ptr;
                                ret.len = len;
                                break :blk ret;
                            } else break :blk "";
                        },
                        else => "<unknown>",
                    };

                    try fbs.writer().writeAll(value);
                }

                for (0..match.capture_count) |i| {
                    const capture = match.captures[i];
                    const node = capture.node;

                    var len: u32 = undefined;
                    if (c.ts_query_capture_name_for_id(query, capture.index, &len)) |capture_name_ptr| {
                        const capture_name = try allocator.dupe(u8, capture_name_ptr[0..len]);
                        if (capture_name.len == 0)
                            continue;
                        const start = c.ts_node_start_byte(node);
                        const end = c.ts_node_end_byte(node);
                        //std.log.info("{*} '{s}' @{s} '{s}'", .{ node.id, code[start..end], capture_name, fbs.getWritten() });

                        const result = try captures.getOrPutValue(.{ .start = start, .end = end }, .{});
                        if (pred_steps.len == 0)
                            result.value_ptr.default = capture_name
                        else
                            try result.value_ptr.predicates.append(allocator, .{ .steps = pred_steps });
                    }
                }
            }

            for (captures.keys(), captures.values()) |node_id, capture| {
                _ = node_id;
                //std.log.info("[{}:{}] default: {s}", .{ node_id.start, node_id.end, capture.default });
                for (capture.predicates.items) |predicate| {
                    var buf: [4096]u8 = undefined;
                    var fbs = std.io.fixedBufferStream(&buf);
                    for (predicate.steps, 0..) |step, i| {
                        if (i != 0)
                            try fbs.writer().writeAll(" ");

                        const value: []const u8 = switch (step.type) {
                            c.TSQueryPredicateStepTypeDone => "",
                            c.TSQueryPredicateStepTypeCapture => blk: {
                                var len: u32 = undefined;
                                if (c.ts_query_capture_name_for_id(query, step.value_id, &len)) |ptr| {
                                    var ret: []const u8 = undefined;
                                    ret.ptr = ptr;
                                    ret.len = len;
                                    break :blk ret;
                                } else break :blk "";
                            },
                            c.TSQueryPredicateStepTypeString => blk: {
                                var len: u32 = undefined;
                                if (c.ts_query_string_value_for_id(query, step.value_id, &len)) |ptr| {
                                    var ret: []const u8 = undefined;
                                    ret.ptr = ptr;
                                    ret.len = len;
                                    break :blk ret;
                                } else break :blk "";
                            },
                            else => "<unknown>",
                        };

                        try fbs.writer().writeAll(value);
                    }

                    //std.log.info("  {s}", .{fbs.getWritten()});
                }
            }

            try writer.writeAll("<code>\n");
            var idx: u32 = 0;
            for (captures.keys(), captures.values()) |pos, capture| {
                while (idx < pos.start) : (idx += 1)
                    try writer.writeByte(code[idx]);

                const capture_name = try evaluate_capture(allocator, query, code[pos.start..pos.end], capture);
                //std.log.info("[{}:{}] {s}", .{ pos.start, pos.end, capture_name });
                const norm = try std.mem.replaceOwned(u8, allocator, capture_name, ".", "-");
                try writer.print("<span class=\"code-{s}\">", .{norm});

                while (idx < pos.end) : (idx += 1)
                    try writer.writeByte(code[idx]);

                try writer.writeAll("</span>");
            }

            try writer.writeAll(code[idx..]);
            try writer.writeAll("</code>\n");
            return;
        }
    }

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
