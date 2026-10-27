import std;
enum E { Big { s: u8[varint], x: i64 }, Small { y: u8 } }
var pool: E..[>..] = [];
var index: (E..&<u32 in pool>)[>..] = [];
fn main() {
    pool.push(E.Small { y: 1 });                        // 2 bytes: tag, y
    let a .= pool.push(E.Big { s: "payload", x: 42 });  // starts at offset 2
    index.push(a);
    pool.clear();
    // One Big whose string begins with byte 5: offset 2 is now inside its payload.
    var s: u8[>..] = [];
    s.push(5); s.push(9); s.append("rest of the string");
    pool.push(E.Big { s: s[..], x: 7 });
    let stale = index[0];
    match stale {
        Big &b => print("stale reads Big: x=", b.x),
        Small &s => print("stale reads Small: y=", s.y),
    }
}
