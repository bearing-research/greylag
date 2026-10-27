// greylag parser: the XML grammar and the flat document model.
//
// Spike subset: elements, attributes, text, comments, PIs (skipped), a
// DOCTYPE without internal subset (skipped), CDATA, the five predefined
// entities and character references, UTF-8 input only.
//
// The document is three flat arrays: fixed-size nodes in document order,
// fixed-size attributes, and one byte arena that starts with a copy of the
// source. A name or a text run that needs no decoding is a span into that
// copy; a decoded one is appended to the arena. Links are ordinals, so a
// node is 27 bytes with no padding and the whole document is a flat value
// that crosses a thread queue with one memcpy.

import std;
import os;

let NONE: u32 = 0xFFFFFFFF;

let K_ELEM: u8 = 1;
let K_TEXT: u8 = 2;
let K_COMMENT: u8 = 3;

struct Node {
    kind: u8,
    s_off: u32, s_len: u32,          // name of an element, text of a text or comment
    first_attr: u32, n_attrs: u16,
    first_child: u32, next: u32, parent: u32,
}

struct Attr { n_off: u32, n_len: u16, v_off: u32, v_len: u32 }

fn is_xml_space(c: u8) -> bool { c == ' ' || c == '\n' || c == '\r' || c == '\t' }

fn is_name_start(c: u8) -> bool {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == ':' || c >= 0x80
}

fn is_name_char(c: u8) -> bool {
    is_name_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.'
}

// Parses `src` into the three arrays, which must be empty. Returns the root
// node's ordinal, or -1 and a message.
fn parse(src: u8[:], nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&) -> i64, u8[>..] {
    text.append(src);                    // the arena starts as the source
    var pos = 0;
    var open: u32[>..<] = [];            // ordinals of the open elements
    var last: u32[>..<] = [];            // and each one's last child so far
    var root: u32 = NONE;
    let needs_decode = byte_set("&\r");
    let dq_stop = byte_set("\"<&\r\n\t");
    let sq_stop = byte_set("'<&\r\n\t");

    fn fail(what: u8[:]) -> u8[>..] { str(what, " at byte ", pos) }

    fn skip_space() { while pos < src.len && is_xml_space(src[pos]) { pos++; } }

    fn at(s: u8[:]) -> bool { pos + s.len <= src.len && src[pos..pos + s.len] == s }

    fn expect(c: u8) {
        if pos < src.len && src[pos] == c { pos++; return; }
        var msg: u8[>..] = [];
        format(msg, "expected '");
        msg.push(c);
        msg.push('\'');
        return -1, fail(msg) from parse;
    }

    // A name as a span of the source: start and length.
    fn parse_name() -> i64, i64 {
        let start = pos;
        guard pos < src.len && is_name_start(src[pos]) else { return -1, fail("expected a name") from parse; }
        pos++;
        while pos < src.len && is_name_char(src[pos]) { pos++; }
        return start, pos - start;
    }

    // A character or entity reference at `&`, appended decoded to the arena.
    fn parse_reference() {
        pos++;                                        // the &
        guard pos < src.len else { return -1, fail("bad reference") from parse; }
        if src[pos] == '#' {
            pos++;
            var cp = 0;
            if pos < src.len && src[pos] == 'x' {
                pos++;
                let start = pos;
                while pos < src.len && src[pos] != ';' {
                    let c = src[pos];
                    var d = -1;
                    if c >= '0' && c <= '9' { d = c - '0'; }
                    else if c >= 'a' && c <= 'f' { d = c - 'a' + 10; }
                    else if c >= 'A' && c <= 'F' { d = c - 'A' + 10; }
                    guard d >= 0 && cp < 0x110000 else { return -1, fail("bad character reference") from parse; }
                    cp = cp * 16 + d;
                    pos++;
                }
                guard pos > start else { return -1, fail("bad character reference") from parse; }
            } else {
                let start = pos;
                while pos < src.len && src[pos] != ';' {
                    let c = src[pos];
                    guard c >= '0' && c <= '9' && cp < 0x110000 else { return -1, fail("bad character reference") from parse; }
                    cp = cp * 10 + (c - '0');
                    pos++;
                }
                guard pos > start else { return -1, fail("bad character reference") from parse; }
            }
            expect(';');
            guard cp > 0 && cp < 0x110000 && !(cp >= 0xD800 && cp <= 0xDFFF) else { return -1, fail("character reference out of range") from parse; }
            push_utf8(text, cp);
            return;
        }
        let ns, nl = parse_name();
        expect(';');
        let name = src[ns..ns + nl];
        if name == "lt" { text.push('<'); }
        else if name == "gt" { text.push('>'); }
        else if name == "amp" { text.push('&'); }
        else if name == "apos" { text.push('\''); }
        else if name == "quot" { text.push('"'); }
        else { return -1, fail("undefined entity") from parse; }
    }

    // An attribute value between matching quotes: a span of the source when
    // it needs no decoding, else decoded and normalized into the arena.
    fn parse_attr_value() -> i64, i64 {
        guard pos < src.len && (src[pos] == '"' || src[pos] == '\'') else { return -1, fail("expected a quoted attribute value") from parse; }
        let q = src[pos];
        pos++;
        let start = pos;
        let end_q = if q == '"' { find_any(src[pos..], dq_stop) } else { find_any(src[pos..], sq_stop) };
        guard end_q >= 0 else { return -1, fail("unterminated attribute value") from parse; }
        if src[pos + end_q] == q {           // the common case: nothing to decode
            pos += end_q + 1;
            return start, end_q;
        }
        let out_start = text.len;
        loop {
            guard pos < src.len else { return -1, fail("unterminated attribute value") from parse; }
            let c = src[pos];
            if c == q { pos++; break; }
            if c == '<' { return -1, fail("'<' in attribute value") from parse; }
            if c == '&' { parse_reference(); continue; }
            if c == '\n' || c == '\r' || c == '\t' { text.push(' '); } else { text.push(c); }
            pos++;
        }
        return out_start, text.len - out_start;
    }

    // The attributes of a start tag; stops before `>` or `/>`.
    fn parse_attrs() -> i64 {
        var n = 0;
        loop {
            skip_space();
            guard pos < src.len else { return -1, fail("unterminated start tag") from parse; }
            if src[pos] == '>' || src[pos] == '/' { break; }
            let ns, nl = parse_name();
            skip_space();
            expect('=');
            skip_space();
            let vs, vl = parse_attr_value();
            attrs.push(Attr { n_off: ns as u32, n_len: nl as u16, v_off: vs as u32, v_len: vl as u32 });
            n++;
        }
        return n;
    }

    // Text content up to the next `<`: a span of the source, or decoded.
    fn parse_text() -> i64, i64 {
        let start = pos;
        let lt = find(src[pos..], "<");
        let end = if lt < 0 { src.len } else { pos + lt };
        if find_any(src[pos..end], needs_decode) < 0 {
            pos = end;
            return start, end - start;
        }
        let out_start = text.len;
        while pos < end {
            let c = src[pos];
            if c == '&' { parse_reference(); continue; }
            if c == '\r' {                                // end-of-line normalization
                text.push('\n');
                pos++;
                if pos < end && src[pos] == '\n' { pos++; }
                continue;
            }
            text.push(c);
            pos++;
        }
        return out_start, text.len - out_start;
    }

    // Links node `ix` under the innermost open element.
    fn attach(ix: u32) {
        guard open.len > 0 else { return; }
        let p = open[open.len - 1];
        nodes[ix].parent = p;
        let l = last[last.len - 1];
        if l == NONE { nodes[p].first_child = ix; } else { nodes[l].next = ix; }
        last[last.len - 1] = ix;
    }

    fn push_node(kind: u8, s_off: i64, s_len: i64, first_attr: i64, n_attrs: i64) -> u32 {
        let ix = nodes.len as u32;
        nodes.push(Node { kind: kind, s_off: s_off as u32, s_len: s_len as u32,
                          first_attr: first_attr as u32, n_attrs: n_attrs as u16,
                          first_child: NONE, next: NONE, parent: NONE });
        attach(ix);
        return ix;
    }

    loop {
        guard pos < src.len else { break; }
        if src[pos] != '<' {
            if open.len == 0 {
                skip_space();
                guard pos >= src.len || src[pos] == '<' else { return -1, fail("text outside the root element") from parse; }
                continue;
            }
            let s, l = parse_text();
            push_node(K_TEXT, s, l, 0, 0);
            continue;
        }
        if at("<!--") {
            pos += 4;
            let start = pos;
            let e = find(src[pos..], "-->");
            guard e >= 0 else { return -1, fail("unterminated comment") from parse; }
            pos += e;
            push_node(K_COMMENT, start, pos - start, 0, 0);
            pos += 3;
            continue;
        }
        if at("<![CDATA[") {
            guard open.len > 0 else { return -1, fail("CDATA outside the root element") from parse; }
            pos += 9;
            let start = pos;
            let e = find(src[pos..], "]]>");
            guard e >= 0 else { return -1, fail("unterminated CDATA section") from parse; }
            pos += e;
            push_node(K_TEXT, start, pos - start, 0, 0);
            pos += 3;
            continue;
        }
        if at("<?") {
            pos += 2;
            let e = find(src[pos..], "?>");
            guard e >= 0 else { return -1, fail("unterminated processing instruction") from parse; }
            pos += e + 2;
            continue;
        }
        if at("<!DOCTYPE") {
            guard open.len == 0 && root == NONE else { return -1, fail("misplaced DOCTYPE") from parse; }
            pos += 9;
            while pos < src.len && src[pos] != '>' && src[pos] != '[' { pos++; }
            guard pos < src.len && src[pos] == '>' else { return -1, fail("DOCTYPE internal subset is not supported") from parse; }
            pos++;
            continue;
        }
        if at("</") {
            pos += 2;
            let ns, nl = parse_name();
            skip_space();
            expect('>');
            guard open.len > 0 else { return -1, fail("end tag without a start tag") from parse; }
            let top = nodes[open[open.len - 1]];
            guard top.s_len == nl && src[top.s_off..top.s_off + nl] == src[ns..ns + nl] else { return -1, fail("mismatched end tag") from parse; }
            open.pop();
            last.pop();
            continue;
        }
        // A start tag.
        pos++;
        guard open.len > 0 || root == NONE else { return -1, fail("more than one root element") from parse; }
        let ns, nl = parse_name();
        let first_attr = attrs.len;
        let n = parse_attrs();
        let ix = push_node(K_ELEM, ns, nl, first_attr, n);
        if open.len == 0 { root = ix; }
        var empty = false;
        if src[pos] == '/' { pos++; empty = true; }
        expect('>');
        if !empty { open.push(ix); last.push(NONE); }
    }
    guard open.len == 0 else { return -1, fail("unclosed element") from parse; }
    guard root != NONE else { return -1, fail("no root element") from parse; }
    return root, str("");
}

// --- serializing ------------------------------------------------------------

fn escape(out: u8[>..]&, s: u8[:], in_attr: bool) {
    for c in s {
        if c == '<' { out.append("&lt;"); }
        else if c == '>' { out.append("&gt;"); }
        else if c == '&' { out.append("&amp;"); }
        else if c == '"' && in_attr { out.append("&quot;"); }
        else { out.push(c); }
    }
}

fn span(text: u8[:], off: u32, len: i64) -> u8[:] { text[off..off + len] }

recursive fn render(ix: u32, nodes: Node[:], attrs: Attr[:], text: u8[:], out: u8[>..]&) {
    let n = nodes[ix];
    if n.kind == K_ELEM {
        let name = span(text, n.s_off, n.s_len);
        out.push('<');
        out.append(name);
        for k in n.n_attrs {
            let a = attrs[n.first_attr + k];
            out.push(' ');
            out.append(span(text, a.n_off, a.n_len));
            out.append("=\"");
            escape(out, span(text, a.v_off, a.v_len), true);
            out.push('"');
        }
        guard n.first_child != NONE else { out.append("/>"); return; }
        out.push('>');
        var c = n.first_child;
        while c != NONE { render(c, nodes, attrs, text, out); c = nodes[c].next; }
        out.append("</");
        out.append(name);
        out.push('>');
    } else if n.kind == K_TEXT {
        escape(out, span(text, n.s_off, n.s_len), false);
    } else {
        out.append("<!--");
        out.append(span(text, n.s_off, n.s_len));
        out.append("-->");
    }
}
