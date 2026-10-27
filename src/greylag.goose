// greylag: the C-facing library. A parse runs in a contained worker, so a
// failed check inside the parser ends the worker and reaches the host as an
// error, never as a dead process. The document is flat, so it comes back
// over the typed queue with one memcpy and is then served to the host
// through integer handles that are checked before every use.

import std;
import os;
import .parser;

struct Req { stop: bool, text: u8[] }
struct Resp { ok: bool, root: i64, nodes: Node[], attrs: Attr[], text: u8[], err: u8[] }

thread_fn worker() {
    let req = qget<Req>();
    var nodes: Node[>..] = [];
    var attrs: Attr[>..] = [];
    var text: u8[>..] = [];
    let root, err = parse(req.text, nodes, attrs, text);
    guard root >= 0 else { qput(Resp { ok: false, root: -1, nodes: [], attrs: [], text: [], err: err[..] }); return; }
    qput(Resp { ok: true, root: root, nodes: nodes[..], attrs: attrs[..], text: text[..], err: "" });
}

// The current document.
var g_nodes: Node[>..] = [];
var g_attrs: Attr[>..] = [];
var g_text: u8[>..] = [];
var last_err: u8[>..] = [];
var root_handle: i64 = -1;

fn reset() {
    last_err.clear();
    root_handle = -1;
    g_nodes.clear();
    g_attrs.clear();
    g_text.clear();
}

// Parse in a contained worker. Returns the root handle, or -1 with the
// message in greylag_error.
export "greylag_parse" fn gl_parse(text: const u8[:]) -> i64 {
    reset();
    qput(Req { stop: false, text: text });
    let id = thread_spawn_contained(worker);
    var why: u8[>..] = [];
    guard thread_wait(id, why) else { last_err.append("parser failed: "); last_err.append(why); return -1; }
    let r = qget<Resp>();
    guard r.ok else { last_err.append(r.err); return -1; }
    g_nodes.append(r.nodes);
    g_attrs.append(r.attrs);
    g_text.append(r.text);
    root_handle = r.root;
    return root_handle;
}

// A persistent contained worker: one per process, started on first use,
// restarted if it dies. Its arrays are freed and re-created per request on
// the same data stacks, so the pages stay warm.
thread_fn pooled_worker() {
    loop {
        let req = qget<Req>();
        guard !req.stop else { break; }
        var nodes: Node[>..] = [];
        var attrs: Attr[>..] = [];
        var text: u8[>..] = [];
        let root, err = parse(req.text, nodes, attrs, text);
        if root >= 0 { qput(Resp { ok: true, root: root, nodes: nodes[..], attrs: attrs[..], text: text[..], err: "" }); }
        else { qput(Resp { ok: false, root: -1, nodes: [], attrs: [], text: [], err: err[..] }); }
    }
}

var pooled_id: i64 = -1;

export "greylag_parse_pooled" fn gl_parse_pooled(text: const u8[:]) -> i64 {
    reset();
    if pooled_id < 0 { pooled_id = thread_spawn_contained(pooled_worker); }
    qput(Req { stop: false, text: text });
    // A reply, or silence long enough to conclude the worker died. A real
    // library needs a watchdog here; the spike scales the wait with size.
    let r, ok = qget<Resp>(2000 + text.len / 1000);
    guard ok else {
        var why: u8[>..] = [];
        thread_wait(pooled_id, why);
        pooled_id = -1;
        last_err.append("parser failed: ");
        last_err.append(why);
        return -1;
    }
    guard r.ok else { last_err.append(r.err); return -1; }
    g_nodes.append(r.nodes);
    g_attrs.append(r.attrs);
    g_text.append(r.text);
    root_handle = r.root;
    return root_handle;
}

// Parse on the calling thread: no worker, no copies. A failed check inside
// the parser aborts the process. For measuring what the worker costs.
export "greylag_parse_direct" fn gl_parse_direct(text: const u8[:]) -> i64 {
    reset();
    let root, err = parse(text, g_nodes, g_attrs, g_text);
    guard root >= 0 else { last_err.append(err); return -1; }
    root_handle = root;
    return root_handle;
}

export "greylag_error" fn gl_error() -> const u8[:] { last_err }
export "greylag_node_count" fn gl_node_count() -> i64 { g_nodes.len }
export "greylag_attr_count_total" fn gl_attr_count_total() -> i64 { g_attrs.len }
export "greylag_tree_bytes" fn gl_tree_bytes() -> i64 { bytes_of(g_nodes).len + bytes_of(g_attrs).len + g_text.len }

// Every accessor below is `checkfree`: the compiler refuses it if a bounds
// check survives, so a hostile handle or a hostile offset in the document
// can only ever return an empty result.

checkfree fn span(off: u32, len: u32) -> const u8[:] {
    let o = off as i64;
    let l = len as i64;
    let e = o + l;
    guard o >= 0 && e >= o && e <= g_text.len else { return ""; }
    return g_text[o..e];
}

// 1 element, 2 text, 3 comment, 0 no such node.
export "greylag_kind" checkfree fn gl_kind(h: i64) -> i32 {
    guard h >= 0 && h < g_nodes.len else { return 0; }
    return g_nodes[h].kind;
}

export "greylag_name" checkfree fn gl_name(h: i64) -> const u8[:] {
    guard h >= 0 && h < g_nodes.len else { return ""; }
    let n = g_nodes[h];
    guard n.kind == K_ELEM else { return ""; }
    return span(n.s_off, n.s_len);
}

export "greylag_text" checkfree fn gl_text(h: i64) -> const u8[:] {
    guard h >= 0 && h < g_nodes.len else { return ""; }
    let n = g_nodes[h];
    guard n.kind != K_ELEM else { return ""; }
    return span(n.s_off, n.s_len);
}

checkfree fn link(v: u32) -> i64 {
    guard v != NONE && v < g_nodes.len else { return -1; }
    return v;
}

export "greylag_first_child" checkfree fn gl_first_child(h: i64) -> i64 {
    guard h >= 0 && h < g_nodes.len else { return -1; }
    return link(g_nodes[h].first_child);
}

export "greylag_next" checkfree fn gl_next(h: i64) -> i64 {
    guard h >= 0 && h < g_nodes.len else { return -1; }
    return link(g_nodes[h].next);
}

export "greylag_parent" checkfree fn gl_parent(h: i64) -> i64 {
    guard h >= 0 && h < g_nodes.len else { return -1; }
    return link(g_nodes[h].parent);
}

export "greylag_attr_count" checkfree fn gl_attr_count(h: i64) -> i64 {
    guard h >= 0 && h < g_nodes.len else { return 0; }
    return g_nodes[h].n_attrs;
}

checkfree fn attr_at(h: i64, i: i64) -> Attr? {
    guard h >= 0 && h < g_nodes.len else { return null; }
    let n = g_nodes[h];
    guard i >= 0 && i < n.n_attrs else { return null; }
    let k = n.first_attr + i;
    guard k >= 0 && k < g_attrs.len else { return null; }
    return g_attrs[k];
}

export "greylag_attr_name" checkfree fn gl_attr_name(h: i64, i: i64) -> const u8[:] {
    let a = attr_at(h, i);
    guard a else { return ""; }
    return span(a.n_off, a.n_len);
}

export "greylag_attr_value" checkfree fn gl_attr_value(h: i64, i: i64) -> const u8[:] {
    let a = attr_at(h, i);
    guard a else { return ""; }
    return span(a.v_off, a.v_len);
}

// The value of the attribute named `name`, or empty.
export "greylag_attr" checkfree fn gl_attr(h: i64, name: const u8[:]) -> const u8[:] {
    guard h >= 0 && h < g_nodes.len else { return ""; }
    let n = g_nodes[h];
    for i in n.n_attrs {
        let a = attr_at(h, i);
        guard a else { return ""; }
        if span(a.n_off, a.n_len) == name { return span(a.v_off, a.v_len); }
    }
    return "";
}

// Spike only: proves that a failed check inside a worker reaches the host
// as a message, not as a dead process.
thread_fn crasher() {
    let req = qget<Req>();
    var xs: i64[>..] = [1, 2, 3];
    let i = req.text.len * 1000;             // 3000: out of bounds
    print(xs[i]);
}

export "greylag_selftest_crash" fn gl_selftest_crash() -> const u8[:] {
    last_err.clear();
    qput(Req { stop: false, text: "abc" });
    let id = thread_spawn_contained(crasher);
    var why: u8[>..] = [];
    if thread_wait(id, why) { last_err.append("worker did not fail"); } else { last_err.append(why); }
    return last_err;
}
