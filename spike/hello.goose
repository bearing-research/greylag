// Spike step 1: the C-host round trip. Nothing XML yet.

var calls: i32 = 0;

export fn hello_world() -> const u8[:] {
    calls += 1;
    return "Hello from Goose";
}

export "gl_add" fn add(a: i32, b: i32) -> i32 { a + b }

// A slice crosses as { data, len }; sum the bytes the host passes in.
export "gl_sum_bytes" fn sum_bytes(s: const u8[:]) -> i64 {
    var t = 0;
    for c in s { t += c; }
    return t;
}

fn main() { calls = 100; }
