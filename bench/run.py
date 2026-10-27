#!/usr/bin/env python3
"""Run every parser on every document, each in its own process, and write
bench/results.md. Times are best-of-N wall clock around the parse call;
memory is the process's peak RSS, which for greylag includes the worker's
copies where a worker is used."""
import subprocess, re, os, sys, platform

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "bench", "data")
BUILD = os.path.join(ROOT, "build")
FILES = ["small-orders.xml", "small-svg.xml", "orders-50k.xml", "svg-50k.xml"]

def run(cmd):
    out = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if out.returncode != 0:
        print("FAILED:", " ".join(cmd), out.stdout, out.stderr, file=sys.stderr)
        return {}
    m = [l for l in out.stdout.splitlines() if l.startswith("RESULT")]
    return dict(kv.split("=", 1) for kv in m[-1].split()[1:]) if m else {}

rows = []
for f in FILES:
    path = os.path.join(DATA, f)
    size = os.path.getsize(path)
    repeat = "2000" if size < 10000 else "7"
    r = {"file": f, "bytes": size}
    for mode in ["direct", "pooled", "worker"]:
        d = run([os.path.join(BUILD, "host"), path, repeat, mode])
        r[mode] = float(d.get(mode + "_ms", "nan"))
        r[mode + "_rss"] = int(d.get("peak_rss_kb", 0))
        if mode == "direct":
            r["tree"] = int(d.get("tree_bytes", 0))
            r["walk"] = float(d.get("walk_ms", "nan"))
    d = run([os.path.join(BUILD, "libxml2_bench"), path, repeat])
    r["libxml2"] = float(d.get("parse_ms", "nan")); r["libxml2_rss"] = int(d.get("peak_rss_kb", 0)); r["libxml2_walk"] = float(d.get("walk_ms", "nan"))
    d = run([os.path.join(BUILD, "expat_bench"), path, repeat])
    r["expat"] = float(d.get("parse_ms", "nan")); r["expat_rss"] = int(d.get("peak_rss_kb", 0))
    rows.append(r)
    print(f, r)

def ms(x): return f"{x:.3f}" if x < 1 else f"{x:.1f}"

lines = []
lines.append("# Spike results\n")
lines.append(f"Machine: {platform.machine()}, {os.cpu_count()} vCPU, {platform.platform()}. ")
lines.append("Goose compiler built from source at master, generated C compiled with gcc 13 -O2. libxml2 and expat are the Ubuntu 24.04 packages. ")
lines.append("Times are the best of N runs of the parse call alone (N=2000 for the small files, 7 for the large ones). ")
lines.append("Greylag is a subset parser (no namespaces, no DTD subset, no UTF-8 validation), so this is the parse structure's cost, not a conformance-equal comparison.\n")
lines.append("## Parse time (ms)\n")
lines.append("| file | bytes | greylag direct | greylag pooled worker | greylag worker per call | libxml2 DOM | expat SAX |")
lines.append("|---|---:|---:|---:|---:|---:|---:|")
for r in rows:
    lines.append(f"| {r['file']} | {r['bytes']:,} | {ms(r['direct'])} | {ms(r['pooled'])} | {ms(r['worker'])} | {ms(r['libxml2'])} | {ms(r['expat'])} |")
lines.append("\n## Peak RSS (MB) and tree size\n")
lines.append("| file | greylag tree bytes | tree / input | greylag direct RSS | greylag pooled RSS | libxml2 RSS | expat RSS (no tree) |")
lines.append("|---|---:|---:|---:|---:|---:|---:|")
for r in rows:
    lines.append(f"| {r['file']} | {r['tree']:,} | {r['tree']/r['bytes']:.2f}x | {r['direct_rss']/1024:.1f} | {r['pooled_rss']/1024:.1f} | {r['libxml2_rss']/1024:.1f} | {r['expat_rss']/1024:.1f} |")
lines.append("\n## Full-tree walk (ms)\n")
lines.append("| file | greylag handle API | libxml2 pointers |")
lines.append("|---|---:|---:|")
for r in rows:
    lines.append(f"| {r['file']} | {ms(r['walk'])} | {ms(r['libxml2_walk'])} |")
open(os.path.join(ROOT, "bench", "results.md"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
