#!/usr/bin/env python3
"""D-002 figure of merit for the benchmark cores (Phase 3, D-005) and the CPU core (Phase 4, D-009).

usage: bench/score.py      (after bench/run.py; runs `make sim-r_f1 sim-r_f5 sim-f1_core` for
                           cycle counts)

Per kernel: iterations/s = copies x Fmax median / cycles for all copies to finish, where a
barrel runs N copies at once (D-004) and F5 runs one. Divided by the cells of the core in
the standard harness ("score" rows of bench/bench.csv), per 1000 LC. The overall figure is
the geometric mean over the four kernels (D-002 Q3). Writes bench/score.csv and prints a
Markdown table.
"""
import csv, math, os, re, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KERNELS = ("crc16", "sort", "mul16", "memcpy")
SIMS = {"F1, 4 threads": "f1_n4", "F1, 8 threads": "f1_n8", "F5, stalls": "f5",
        "F5, forwarding": "f5_fwd", "F1 x1, 4 threads": "f1x1", "F1 x2, 4 threads": "f1x2",
        "F1 x3, 4 threads": "f1x3", "F1 x7, 4 threads": "f1x7",
        "F1 x11, 4 threads": "f1x11", "F1 x15, 4 threads": "f1x15",
        "F1 core x7, 4 threads": "core", "F1 core x15, 4 threads": "core_x15"}
# unrolled kernels (X bit 3) run on the same hardware
HW = {"f1x11": "f1x3", "f1x15": "f1x7", "core_x15": "core"}


def cycles():
    env = dict(os.environ)
    tools = os.path.join(ROOT, "tools", "oss-cad-suite", "bin")
    if os.path.isdir(tools):
        env["PATH"] = tools + os.pathsep + env["PATH"]
    out = subprocess.run(["make", "-s", "sim-r_f1", "sim-r_f5", "sim-f1_core"], cwd=ROOT, env=env, check=True,
                         capture_output=True, text=True).stdout
    c = {}
    for line in out.splitlines():
        m = re.match(r"(F\d(?: core)?(?: x\d+)?, [a-z0-9 ]+?)\s+(\w+)\s+(\d+)/(\d+) done, 0 words wrong, cycles (\d+)", line)
        if m and m.group(2) in KERNELS and m.group(3) == m.group(4):
            c[(SIMS[m.group(1)], m.group(2))] = (int(m.group(5)), int(m.group(4)))
    assert len(c) == len(SIMS) * len(KERNELS), sorted(c)
    return c


def main():
    rows = {r["name"]: r for r in csv.DictReader(open(os.path.join(ROOT, "bench", "bench.csv")))}
    cyc = cycles()
    out = []
    for name in SIMS.values():
        r = rows[HW.get(name, name)]
        lc, f = int(r["lc"]), float(r["fmax_median"]) * 1e6
        row = dict(name=name, lc=lc, fmax_median=r["fmax_median"])
        merits = []
        for k in KERNELS:
            c, copies = cyc[(name, k)]
            ips = copies * f / c
            row[f"{k}_cycles"] = c
            row[f"{k}_per_klc"] = round(ips / lc * 1000)
            merits.append(ips / lc * 1000)
        row["geomean_per_klc"] = round(math.exp(sum(map(math.log, merits)) / len(merits)))
        out.append(row)
    with open(os.path.join(ROOT, "bench", "score.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0]))
        w.writeheader()
        w.writerows(out)
    print("| Core | LC | Fmax | " + " | ".join(KERNELS) + " | geomean |")
    print("|---|---:|---:|" + "---:|" * (len(KERNELS) + 1))
    for r in out:
        print(f"| {r['name']} | {r['lc']} | {r['fmax_median']} | "
              + " | ".join(f"{r[k + '_per_klc']:,}" for k in KERNELS) + f" | **{r['geomean_per_klc']:,}** |")


if __name__ == "__main__":
    main()
