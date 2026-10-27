// Probe 3: the holder rule and the stack rooting.
import std;

struct N { v: i32, next: N&<u32>? }
var pool: N[>..] = [];
var index: (N&)[>..] = [];

fn fill() {
    let a .= pool.push(N { v: 1, next: null });
    let b .= pool.push(N { v: 2, next: null });
    a.next .= b;
    index.push(a);
    index.push(b);
}

// H1: a global holder, cleared first, then the pool.
fn h1() -> i64 {
    fill();
    index.clear();
    pool.clear();
    return pool.len;
}

// H2: a local holder, cleared first, then the pool.
fn h2() -> i64 {
    var lpool: N[>..] = [];
    var lindex: (N&)[>..] = [];
    let a .= lpool.push(N { v: 1, next: null });
    lindex.push(a);
    lindex.clear();
    lpool.clear();
    return lpool.len;
}

// H3: a local holder whose last use is before the clear (liveness, not emptiness).
fn h3() -> i64 {
    var lpool: N[>..] = [];
    var lindex: (N&)[>..] = [];
    let a .= lpool.push(N { v: 1, next: null });
    lindex.push(a);
    let n = lindex.len;
    lpool.clear();
    return n;
}

// E: a grow-only stack of plain references into a local pool, patched through.
struct Open { elem: N&, last: N? }
fn e() -> i32 {
    var lpool: N[>..] = [];
    var open: Open[>..] = [];
    let a .= lpool.push(N { v: 10, next: null });
    open.push(Open { elem: a, last: null });
    let b .= lpool.push(N { v: 20, next: null });
    let top .= open[open.len - 1];
    top.elem.next .= b;
    top.last .= b;
    open.pop();
    let n = a.next;
    guard n else { return -1; }
    return n.v;
}

fn main() {
    print("h1 ", h1());
    print("h2 ", h2());
    print("h3 ", h3());
    print("e ", e());
}
