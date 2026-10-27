// Probe 2: is the from_bytes limit specific to from_bytes, or general to
// values with self-relative links? Each shape is a separate function so one
// error does not hide the others; comment shapes out to isolate.
import std;

struct N { v: i32, next: N&<u32>? }
var pool: N[>..] = [];
var docs: N[][>..] = [];
var image: u8[>..] = [];

// A regular function that returns a linked array by value.
fn build() -> N[>..] {
    var out: N[>..] = [];
    let a .= out.push(N { v: 1, next: null });
    let b .= out.push(N { v: 2, next: null });
    a.next .= b;
    return out;
}

// P1: whole-assignment of a global from a regular call.
fn p1() -> i64 { pool = build(); return pool.len; }

// P2: pushing a regular call's result as a variable-size element.
fn p2() -> i64 { docs.push(build()); return docs.len; }

// P3: whole-assignment of a global from from_bytes.
fn p3() -> i64 { pool = from_bytes<N[>..]>(image); return pool.len; }

// P4: pushing from_bytes's result as an element.
fn p4() -> i64 { docs.push(from_bytes<N[]>(image)); return docs.len; }

fn main() {
    var local: N[>..] = [];
    let a .= local.push(N { v: 1, next: null });
    let b .= local.push(N { v: 2, next: null });
    a.next .= b;
    image.append(local.to_bytes());
    print("p1 ", p1());
    print("p2 ", p2());
    print("p3 ", p3());
    print("p4 ", p4());
}
