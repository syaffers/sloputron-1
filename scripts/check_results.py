#!/usr/bin/env python3
"""CI gate for results.csv (see docs/process.md).

usage: check_results.py [--csv results.csv] [--budget 1216] [--base REV] build/<design>/sweep.json ...

Fails (exit 1) when any of these hold:
  1. budget:   a design uses more logic cells than --budget (default 1216 = 95% of 1280),
               or more BRAMs than 16.
  2. stale:    the fresh measurement differs from the newest results.csv row for that
               design (cells/BRAMs exactly; Fmax median by more than 1%), so the committed
               numbers no longer describe the code. Fix: `make report NOTE=...`.
  3. missing:  the design has no row in results.csv at all.
  4. silent regression: compared with the design's previous row, cells went up or
               median Fmax fell by more than 2% and the newest row's `note` is empty.
  5. no row for the change: --base is given, files under rtl/ or board/ changed since
               REV, and results.csv did not.
"""
import argparse, csv, json, subprocess, sys

def main():
    p = argparse.ArgumentParser()
    p.add_argument("rows", nargs="+")
    p.add_argument("--csv", default="results.csv")
    p.add_argument("--budget", type=int, default=1216)
    p.add_argument("--fmax-tol", type=float, default=0.01)
    p.add_argument("--regress-tol", type=float, default=0.02)
    p.add_argument("--base", help="git revision to diff against for rule 5")
    a = p.parse_args()

    hist = {}
    with open(a.csv) as f:
        for r in csv.DictReader(f):
            hist.setdefault(r["design"], []).append(r)

    errors = []
    for path in a.rows:
        m = json.load(open(path))
        d = m["name"]
        if m["lc"] > a.budget:
            errors.append(f"{d}: {m['lc']} LC exceeds budget {a.budget}")
        if m["ram"] > 16:
            errors.append(f"{d}: {m['ram']} BRAMs exceeds 16")
        rows = hist.get(d)
        if not rows:
            errors.append(f"{d}: no row in {a.csv}; run `make report`")
            continue
        last = rows[-1]
        if int(last["cells"]) != m["lc"] or int(last["brams"]) != m["ram"]:
            errors.append(f"{d}: results.csv says {last['cells']} LC/{last['brams']} BRAM, "
                          f"measured {m['lc']} LC/{m['ram']} BRAM; run `make report`")
        f_last = float(last["fmax_median"])
        if abs(m["fmax_median"] - f_last) > a.fmax_tol * f_last:
            errors.append(f"{d}: results.csv Fmax median {f_last}, measured {m['fmax_median']}; "
                          f"run `make report`")
        if len(rows) >= 2 and not last["note"].strip():
            prev = rows[-2]
            if int(last["cells"]) > int(prev["cells"]):
                errors.append(f"{d}: cells {prev['cells']} -> {last['cells']} with no note")
            if float(last["fmax_median"]) < (1 - a.regress_tol) * float(prev["fmax_median"]):
                errors.append(f"{d}: Fmax {prev['fmax_median']} -> {last['fmax_median']} with no note")
        print(f"{d}: {m['lc']} LC, {m['ram']} BRAM, Fmax {m['fmax_median']} / {m['fmax_worst']} MHz")

    if a.base:
        changed = subprocess.run(["git", "diff", "--name-only", a.base, "HEAD"],
                                 capture_output=True, text=True).stdout.split()
        hw = [c for c in changed if c.startswith(("rtl/", "board/"))]
        if hw and a.csv not in changed:
            errors.append(f"hardware changed since {a.base} ({', '.join(hw[:5])}) "
                          f"but {a.csv} has no new row")

    for e in errors:
        print("FAIL:", e)
    sys.exit(1 if errors else 0)

if __name__ == "__main__":
    main()
