struct N { v: i32, next: N&<u32>? }
var pool: N[>..] = [];

// Build straight into the result slot, as 18_json's parse_string does.
fn two() -> N[>..], bool {
    return [N { v: 1, next: null }], true;
}

// Single result, named local returned: the shape build() used.
fn one() -> N[>..] {
    var out: N[>..] = [];
    out.push(N { v: 1, next: null });
    return out;
}

fn main() {
    var ok: bool;
    // pool, ok = two();   rejected

    pool = one();
    print("one at global: ", pool.len);
    var p2, ok2 = two();
    print("two at fresh local: ", ok2, " ", p2.len);
}
