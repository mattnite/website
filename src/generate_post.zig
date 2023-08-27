const std = @import("std");
const Metadata = @import("Metadata.zig");
const c = @cImport({
    @cInclude("cmark-gfm.h");
    @cInclude("cmark-gfm-core-extensions.h");
});

const template = @embedFile("template.html");
extern fn cmark_list_syntax_extensions([*c]c.cmark_mem) [*c]c.cmark_llist;

pub fn main() !void {
    c.cmark_gfm_core_extensions_ensure_registered();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    const metadata_json = args[1];
    const input_path = args[2];
    const output_path = args[3];

    const parsed = try std.json.parseFromSlice(Metadata, arena.allocator(), metadata_json, .{});
    const metadata = parsed.value;
    const text_md = try std.fs.cwd().readFileAlloc(arena.allocator(), input_path, std.math.maxInt(usize));

    const output_file = try std.fs.createFileAbsolute(output_path, .{});
    defer output_file.close();

    var body = std.ArrayList(u8).init(gpa.allocator());
    defer body.deinit();

    const body_writer = body.writer();
    const options: c_int =
        c.CMARK_OPT_FOOTNOTES;
    const extensions = cmark_list_syntax_extensions(c.cmark_get_arena_mem_allocator());
    const parser = c.cmark_parser_new(options);
    defer c.cmark_parser_free(parser);

    _ = c.cmark_parser_attach_syntax_extension(parser, c.cmark_find_syntax_extension("table"));

    c.cmark_parser_feed(parser, text_md.ptr, text_md.len);

    const document = c.cmark_parser_finish(parser);
    defer c.cmark_node_free(document);

    const html = c.cmark_render_html(document, options, extensions);
    try body_writer.writeAll(std.mem.span(html));
    //var footnote_count: u32 = 0;
    //var it = c.cmark_node_first_child(document);
    //while (it != null) : (it = c.cmark_node_next(it)) {
    //    const node_type = c.cmark_node_get_type(it);
    //    std.log.info("{x}: type={s}", .{ node_type, c.cmark_node_get_type_string(it) });
    //    switch (node_type) {
    //        c.CMARK_NODE_CODE_BLOCK => {
    //            const literal: ?[]const u8 = if (c.cmark_node_get_literal(it)) |literal|
    //                std.mem.span(literal)
    //            else
    //                null;

    //            const fence_info = c.cmark_node_get_fence_info(it);
    //            _ = literal;
    //            // TODO: escaping
    //            std.log.warn("skiping code for <{s}>", .{fence_info});
    //        },
    //        c.CMARK_NODE_FOOTNOTE_DEFINITION => {
    //            footnote_count += 1;
    //            //<section class="footnotes" data-footnotes>
    //            //  <ol>
    //            //    <li id="fn-1">
    //            //      <p>My reference. <a href="#fnref-1" class="footnote-backref" data-footnote-backref data-footnote-backref-idx="1" aria-label="Back to reference 1">↩</a ></p>
    //            //    </li>
    //            //  </ol>
    //            //</section>
    //            //
    //            //<section class="footnotes" data-footnotes>
    //            //  <ol>
    //            //    <li id="fn-2">
    //            //      <p>Every new line should be prefixed with 2 spaces.<br />
    //            //      This allows you to have a footnote with multiple lines. <a href="#fnref-2" class="footnote-backref" data-footnote-backref data-footnote-backref-idx="1" aria-label="Back to reference 1">↩</a></p>
    //            //    </li>
    //            //  </ol>
    //            //</section>
    //            //
    //            //<section class="footnotes" data-footnotes>
    //            //  <ol>
    //            //    <li id="fn-note">
    //            //      <p>Named footnotes will still render with numbers instead of the text but allow easier identification and linking.<br />
    //            //      This footnote also has been made with a different syntax using 4 spaces for new lines. <a href="#fnref-note" class="footnote-backref" data-footnote-backref data-footnote-backref-idx="1" aria-label="Back to reference 1">↩</a></p>
    //            //    </li>
    //            //  </ol>
    //            //</section>
    //            const html = c.cmark_render_html(it, options, extensions);
    //            try body_writer.writeAll(std.mem.span(html));
    //        },
    //        else => {
    //            const html = c.cmark_render_html(it, options, extensions);
    //            try body_writer.writeAll(std.mem.span(html));
    //        },
    //    }
    //}

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
