struct N { v: i32, next: N&<u32>? }

var pool: N[>..] = [];
var image: u8[>..] = [];

fn build() -> N[>..] {
    var out: N[>..] = [];
    let a .= out.push(N { v: 1, next: null });
    let b .= out.push(N { v: 2, next: null });
    a.next .= b;
    return out;
}

fn main() {
    image = build().to_bytes();

    pool = build();                       // ok: constructed in place at the global
    pool = from_bytes<N[>..]>(image);     // error: copying a value of type N[>..] ...

    var local, ok = from_bytes<N[>..]>(image);   // ok: a fresh local
    let n = local[0].next;
    if n { print(n.v); }
}
