# Phase 0 spike: findings

Date: 2026-10-26. Goose at master (64d62fc), built from source. Linux x86-64, 2 vCPU, gcc 13.

## What was built

- `src/parser.goose`: a subset XML parser (elements, attributes, text, comments, CDATA, PIs and a subset-free DOCTYPE skipped, the five predefined entities, character references, UTF-8 only). Explicit element stack, no recursion.
- `src/greylag.goose`: the C-facing library. Three parse entry points (direct, per-call contained worker, persistent contained worker) and a handle-based accessor API, every accessor `checkfree`.
- `c/host.c`: a C host that walks the tree, exercises the error path and a hostile handle, and times each entry point.
- `bench/`: libxml2 and expat harnesses, a document generator, a runner, and `results.md`.

The library compiles to one 10.6k-line C file plus a header via `goose --standalone --header`.

## The three numbers the spike was for

1. **Per-parse overhead of the worker path.** On a 1.25 KB document: direct 4 µs, persistent worker 17 µs, worker spawned per call 85 µs. libxml2 takes 22 µs and expat 11 µs. The queue round trip costs about 13 µs; a spawn per call costs about 80 µs. The persistent worker is at parity with libxml2 on small documents, not ahead.
2. **Bytes per node.** The flat model costs 27 bytes per node and 14 per attribute, plus one copy of the source as the text arena. Tree size is 1.8x to 3x the input. libxml2's peak RSS is 4.8x greylag's for the record file and 4.2x for the SVG (direct mode).
3. **Language limits hit.** Two, both design-changing; see below.

## Results (best of N, parse call only)

| file | bytes | greylag direct | greylag persistent worker | libxml2 DOM | expat SAX |
|---|---:|---:|---:|---:|---:|
| small-orders.xml | 1,253 | 0.004 ms | 0.017 ms | 0.022 ms | 0.011 ms |
| small-svg.xml | 1,002 | 0.003 ms | 0.019 ms | 0.009 ms | 0.007 ms |
| orders-50k.xml | 13.4 MB | 29.8 ms | 55.6 ms | 155.3 ms | 86.4 ms |
| svg-50k.xml | 6.9 MB | 6.6 ms | 12.1 ms | 40.0 ms | 41.9 ms |

Single cold runs on the large files: orders direct 50.5 ms, persistent worker 163 ms (includes its first spawn), libxml2 258 ms, expat 96 ms; SVG direct 11.6 ms, worker 52.7 ms, libxml2 68.7 ms, expat 44.2 ms.

Peak RSS on orders-50k: greylag direct 52.6 MB, greylag persistent worker 229 MB, libxml2 250 MB, expat 27.6 MB (no tree). A full walk of the 674k-node tree through the handle API takes 6.3 ms against 23 ms for libxml2 pointer chasing.

Caveats: greylag does less work than libxml2 or expat (no namespaces, no UTF-8 validation of content, no DTD), the machine is a 2-vCPU VM with roughly 20% run-to-run noise on the large files, and the Ubuntu libxml2 is 2.9.14.

## Language limits that changed the design

Re-examined with isolating probes (`spike/probe2.goose` through `spike/probe7_stale_in_pool_link.goose`) after the first writeup overstated what was the language's fault.

1. **`from_bytes` constructs in place only into a fresh `var`: a compiler gap.** An ordinary function returning a linked array constructs in place at a global whole-assignment, at a push, and on reassignment, with links intact (probe2: p1, p2). The identical shapes with `from_bytes` are rejected as copies of a value with self-relative links (p3, p4). Spec §4.3's in-place guarantee is not wired up for this builtin. This is the one finding that blocks the variable-mode handle API, since a verified image cannot outlive the call that loaded it.
2. **The holder rule is liveness-based, as §5.1 says; not a bug.** A local holder whose last use precedes the clear is fine (probe3: h2, h3); one cleared and used again is rejected (probe4: h4); a global holder is always in use, so always rejected (h1). A `clear()` that reset the holder's recorded stores would be a feature request.
3. **References read out of a `T[>..<]` stack are rooted at the stack; not a bug, and there is a fix inside a worker.** A grow-only `Open[>..]` stack of plain references, popped by hand, compiles and patches links correctly (probe3: e). The first writeup's claim that the pool-as-parameter case had no fix was wrong.
4. **A soundness hole, found while probing (2).** A global holder of pool-relative links, `(E..&<u32 in pool>)[>..]`, does not block `pool.clear()` (probe5), while a holder of plain references in the same position does. For fixed-size elements that is the documented stale-slot semantics. For a variable-mode pool, a stale link arranged to land mid-element on a byte of value 5 makes a release-build `match` execute no arm and exit 0 (undefined behavior on a corrupt tag); a debug build reports `corrupt ADT tag` (probe7). Spec §3.5 says allowing variant replacement or interior references but never both is what keeps the type system sound; clear-and-refill under a surviving interior link is both. This is the first thing to report upstream.

Consequence for greylag: the library uses the flat model (fixed-size nodes, integer links, text arena) because of (1) alone. It crosses the queue with no image and no verification pass, handles are indices, and every accessor is `checkfree`. The variable-mode tree was measured in-process on the same files before the switch: 17.9 MB versus 39.6 MB for the flat tree on orders-50k, and 7.6 MB versus 12.5 MB on the SVG, at 54 ms versus 44 ms parse time. That is what (1) costs: roughly half the memory advantage. With (1) fixed and (3)'s grow-only stack, the variable-mode design becomes viable again, using `in pool` links for the handle index on a pool that is never cleared, only replaced by whole assignment, which needs a check that assignment is covered by (4)'s fix.

## What held up

- `export fn` with `--standalone --header` works as documented. Slices cross as a `{data, len}` struct by value; a `const u8[:]` return is pointer plus out-length.
- `thread_spawn_contained` plus `thread_wait(id, msg)` turns an out-of-bounds index inside the worker into a message with the source line; the host keeps running.
- `checkfree` caught two accessors with a surviving bounds check during development, which is the guarantee it promises.
- `qget<T>(ms)` makes a persistent contained worker workable: wait with a timeout, then `thread_wait` to collect the abort message and respawn.
- The parser itself, with no tree and no recursion, is 2.5x to 6x faster than libxml2's DOM build and 1.5x to 6x faster than expat's SAX pass on these files, with the subset caveat above.

## What the worker costs

The worker path copies the document three times (into the request queue, into the response queue, into the host-facing globals) because queues copy and nothing moves. That quadruples peak memory on large documents (229 MB against 52.6 MB direct) and roughly doubles parse time. A single-threaded library with no worker would be the fastest and smallest, at the price that a parser bug aborts the host process. The honest options for Phase 1:

- Ship both entry points, document the trade, default to the worker.
- Or reduce the copies: parse directly from the request's bytes (one copy saved), and have the host read results through accessors that run on the worker's side (not possible without host-visible storage), or ask upstream for queue messages that transfer ownership.

## Phase 0 verdict

Nothing found kills the project. The variable-mode tree is blocked by one compiler gap that looks fixable upstream, and the flat model still beats libxml2 on every column measured. The small-document case is at parity through the worker and well ahead without it. The decision Phase 1 needs is the worker default. Upstream, the soundness hole (4) goes first, then `from_bytes` in-place construction (1).
