// A command-line driver for the parser, for the spike.

import std;
import os;
import .parser;

fn main() {
    var path: u8[>..] = [];
    guard arg_count() > 1 else { print("usage: greylag file.xml [dump]"); exit(2); }
    arg(1, path);
    var src: u8[>..] = [];
    guard read_file(path, src) else { print("cannot read ", path); exit(1); }
    var nodes: Node[>..] = [];
    var attrs: Attr[>..] = [];
    var text: u8[>..] = [];
    let t0 = clock();
    let root, err = parse(src, nodes, attrs, text);
    let t1 = clock();
    guard root >= 0 else { print("parse error: ", err); exit(1); }
    var elems = 0;
    var texts = 0;
    for n in nodes { if n.kind == K_ELEM { elems++; } else if n.kind == K_TEXT { texts++; } }
    let tree = bytes_of(nodes).len + bytes_of(attrs).len + text.len;
    print("parsed ", src.len, " bytes: ", nodes.len, " nodes (", elems, " elements, ", texts, " text, ", attrs.len, " attributes), root at ", root);
    print("tree bytes ", tree, " = nodes ", bytes_of(nodes).len, " + attrs ", bytes_of(attrs).len, " + arena ", text.len, " (", text.len - src.len, " decoded)");
    print("parse ms ", (t1 - t0) * 1000.0);
    if arg_count() > 2 {
        var out: u8[>..] = [];
        render(root as u32, nodes, attrs, text, out);
        print(out);
    }
}
