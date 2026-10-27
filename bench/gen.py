#!/usr/bin/env python3
"""Generate benchmark documents.

orders-N.xml : a data file of N orders with items (records with attributes and short text)
svg-N.xml    : an SVG-like drawing with N paths (attribute heavy, long attribute values)
small-*.xml  : ~1 KB documents of each shape
"""
import random, sys, os

random.seed(42)
out = sys.argv[1] if len(sys.argv) > 1 else "bench/data"
os.makedirs(out, exist_ok=True)

NAMES = ["alice", "bob", "carol", "dave", "erin", "frank", "grace", "heidi"]

def orders(n):
    parts = ['<?xml version="1.0" encoding="UTF-8"?>\n<orders>\n']
    for i in range(n):
        parts.append(f'  <order id="{1000+i}" customer="{random.choice(NAMES)}" date="2026-{random.randint(1,12):02d}-{random.randint(1,28):02d}">\n')
        for j in range(random.randint(1, 4)):
            parts.append(f'    <item sku="SKU-{random.randint(1,9999)}" qty="{random.randint(1,9)}" cents="{random.randint(100,99999)}">{random.choice(["Widget","Gadget","Sprocket &amp; Co","Bolt &lt;M6&gt;"])}</item>\n')
        parts.append(f'    <note>order {i} for {random.choice(NAMES)}</note>\n  </order>\n')
    parts.append('</orders>\n')
    return ''.join(parts)

def svg(n):
    parts = ['<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">\n  <g id="layer1" fill="none" stroke="#000">\n']
    for i in range(n):
        d = ' '.join(f'L{random.randint(0,1000)} {random.randint(0,1000)}' for _ in range(random.randint(3, 12)))
        parts.append(f'    <path id="p{i}" d="M{random.randint(0,1000)} {random.randint(0,1000)} {d} Z" stroke-width="{random.choice([1,2,3])}" fill="#{random.randint(0,0xffffff):06x}"/>\n')
        if i % 50 == 0:
            parts.append(f'    <text x="{random.randint(0,1000)}" y="{random.randint(0,1000)}">label {i}</text>\n')
    parts.append('  </g>\n</svg>\n')
    return ''.join(parts)

def write(name, s):
    p = os.path.join(out, name)
    with open(p, "w") as f: f.write(s)
    print(f"{p}: {len(s)} bytes")

write("small-orders.xml", orders(4))
write("small-svg.xml", svg(6))
write("orders-50k.xml", orders(50_000))
write("svg-50k.xml", svg(50_000))
