#!/usr/bin/env python3
"""Append one results.csv row per design from pnr_sweep summary JSON files.

usage: report.py [--note TEXT] [--csv results.csv] [--bench FILE.json] build/<design>/sweep.json ...

Columns: date, commit, design, cells, cells_avail, brams, fmax_median, fmax_worst,
seeds, toolchain, bench_cycles, code_size, note

`commit` is the HEAD the measurement was taken on, with "+dirty" when the working tree
has uncommitted changes. Run `make report` just before committing: the row then
describes HEAD plus the change being committed, and the commit that adds the row is
the next one in history (a commit cannot contain its own hash).
`bench_cycles` and `code_size` stay empty until a CPU runs benchmarks (Phase 3). An
optional --bench JSON maps design -> {"bench_cycles": "...", "code_size": "..."}.
"""
import argparse, csv, datetime, json, os, subprocess, sys

FIELDS = ["date", "commit", "design", "cells", "cells_avail", "brams", "fmax_median",
          "fmax_worst", "seeds", "toolchain", "bench_cycles", "code_size", "note"]

def sh(*cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return (r.stdout.strip() or r.stderr.strip()).splitlines()[0] if (r.stdout or r.stderr) else ""
    except Exception:
        return ""

def toolchain():
    root = os.path.dirname(os.path.dirname(sh("which", "yosys") or "/x/x"))
    ver = ""
    try:
        ver = open(os.path.join(root, "VERSION")).read().strip()
    except OSError:
        pass
    y = sh("yosys", "-V").split(" (")[0].replace("Yosys ", "yosys-")
    n = sh("nextpnr-ice40", "--version")
    n = n.split()[-1].replace("(", "").replace(")", "") if n else ""
    n = n if n.startswith("nextpnr") else (f"nextpnr-{n}" if n else "")
    return ";".join(x for x in (f"oss-cad-suite-{ver}" if ver else "", y, n) if x)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("rows", nargs="+")
    p.add_argument("--csv", default="results.csv")
    p.add_argument("--note", default="")
    p.add_argument("--bench")
    a = p.parse_args()

    commit = sh("git", "rev-parse", "--short=7", "HEAD") or "uncommitted"
    if sh("git", "status", "--porcelain", "--untracked-files=no"):
        commit += "+dirty"
    bench = json.load(open(a.bench)) if a.bench else {}
    tc = toolchain()
    date = datetime.date.today().isoformat()

    new = not os.path.exists(a.csv) or os.path.getsize(a.csv) == 0
    with open(a.csv, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        if new:
            w.writeheader()
        for path in a.rows:
            r = json.load(open(path))
            b = bench.get(r["name"], {})
            row = dict(date=date, commit=commit, design=r["name"], cells=r["lc"],
                       cells_avail=r["lc_avail"], brams=r["ram"],
                       fmax_median=r["fmax_median"], fmax_worst=r["fmax_worst"],
                       seeds=r["seeds"], toolchain=tc,
                       bench_cycles=b.get("bench_cycles", ""), code_size=b.get("code_size", ""),
                       note=a.note)
            w.writerow(row)
            print(f"{row['design']}: {row['cells']} LC, {row['brams']} BRAM, "
                  f"Fmax {row['fmax_median']} / {row['fmax_worst']} MHz ({row['seeds']} seeds)")

if __name__ == "__main__":
    main()
