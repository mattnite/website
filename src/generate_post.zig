const std = @import("std");
const Metadata = @import("Metadata.zig");
const c = @cImport({
    @cInclude("cmark-gfm.h");
    @cInclude("cmark-gfm-core-extensions.h");
});

const template = @embedFile("template.html");
extern fn cmark_list_syntax_extensions([*c]c.cmark_mem) [*c]c.cmark_llist;

const Footnote = struct {
    name: []const u8,
    def_node: *c.cmark_node,
    ref_nodes: std.ArrayListUnmanaged(*c.cmark_node) = .{},
};

pub fn main() !void {
    c.cmark_gfm_core_extensions_ensure_registered();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    const metadata_json = args[1];
    const input_path = args[2];
    const output_path = args[3];

    const parsed = try std.json.parseFromSlice(Metadata, arena.allocator(), metadata_json, .{});
    const metadata = parsed.value;
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
                const literal: ?[]const u8 = if (c.cmark_node_get_literal(it)) |literal|
                    std.mem.span(literal)
                else
                    null;

                const fence_info = c.cmark_node_get_fence_info(it);
                _ = literal;
                // TODO: escaping
                std.log.warn("skiping code for <{s}>", .{fence_info});
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
            \\<h2>References</h2>
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
        .title = metadata.title,
        .author = metadata.author,
        .date = metadata.date,
        .keywords = keywords_str,
        .description = metadata.description,
        .style_path = metadata.style_path,
        .body = body.items,
    });
    try buffered.flush();
}
