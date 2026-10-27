import std;
struct N { v: i32, next: N&<u32>? }

// H4: a local holder cleared, the pool cleared, and the holder used afterwards.
fn h4() -> i64 {
    var lpool: N[>..] = [];
    var lindex: (N&)[>..] = [];
    let a .= lpool.push(N { v: 1, next: null });
    lindex.push(a);
    lindex.clear();
    lpool.clear();
    let b .= lpool.push(N { v: 2, next: null });
    lindex.push(b);
    return lindex.len;
}

// H5: the same without the clear of the holder: should be rejected.
fn h5() -> i64 {
    var lpool: N[>..] = [];
    var lindex: (N&)[>..] = [];
    let a .= lpool.push(N { v: 1, next: null });
    lindex.push(a);
    lpool.clear();
    return lindex.len;
}

fn main() { print("h4 ", h4()); print("h5 ", h5()); }
