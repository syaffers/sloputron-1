#!/usr/bin/env python3
"""Pull the final cell breakdown (LUT4 / DFF* / CARRY / RAM) out of Yosys logs.
Supplementary only: the authoritative cell count is nextpnr's ICESTORM_LC.
usage: yosys_stats.py build/*.yslog"""
import re, sys, os

def stats(path):
    txt = open(path, errors="replace").read()
    blocks = txt.split("Printing statistics.")
    last = blocks[-1]
    # keep only the first per-module block (synth_ice40 flattens to one module, 'top');
    # the 'design hierarchy' summary that follows repeats the same counts.
    parts = re.split(r"^=== .* ===$", last, flags=re.M)
    last = parts[1] if len(parts) > 1 else last
    c = {}
    for m in re.finditer(r"^\s+(\d+)\s+(SB_\w+)\s*$", last, re.M):
        c[m.group(2)] = c.get(m.group(2), 0) + int(m.group(1))
    lut = c.get("SB_LUT4", 0)
    ff = sum(v for k, v in c.items() if k.startswith("SB_DFF"))
    carry = c.get("SB_CARRY", 0)
    ram = c.get("SB_RAM40_4K", 0)
    return lut, ff, carry, ram

print("design,lut4,dff,carry,ram")
for p in sys.argv[1:]:
    n = os.path.basename(p).rsplit(".", 1)[0]
    print(n + "," + ",".join(map(str, stats(p))))
