#!/usr/bin/env python3
"""Place & route one synthesized netlist over N seeds and report post-placement
utilisation and Fmax (median / worst / best).

usage: pnr_sweep.py NAME NETLIST.json PCF [--seeds 16] [--jobs 2] [--freq 100]
                    [--device hx1k --package tq144] [--csv out.csv]

Numbers come from nextpnr's --report JSON (utilisation after placement, Fmax of
the 'clk' domain). Nothing is taken from Yosys `stat`.
"""
import argparse, json, os, statistics, subprocess, sys, csv
from concurrent.futures import ThreadPoolExecutor

def run(seed, a, outdir):
    rep = os.path.join(outdir, f"seed{seed:02d}.json")
    log = os.path.join(outdir, f"seed{seed:02d}.log")
    cmd = ["nextpnr-ice40", f"--{a.device}", "--package", a.package,
           "--json", a.netlist, "--freq", str(a.freq),
           "--seed", str(seed), "--report", rep, "--quiet", "--timing-allow-fail"]
    cmd += ["--pcf-allow-unconstrained"] if a.pcf == "none" else ["--pcf", a.pcf]
    if a.asc:
        cmd += ["--asc", os.path.join(outdir, f"seed{seed:02d}.asc")]
    with open(log, "w") as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        return seed, None
    with open(rep) as f:
        return seed, json.load(f)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("name"); p.add_argument("netlist"); p.add_argument("pcf")
    p.add_argument("--seeds", type=int, default=16)
    p.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    p.add_argument("--freq", type=float, default=100.0)
    p.add_argument("--device", default="hx1k")
    p.add_argument("--package", default="tq144")
    p.add_argument("--clock", default="clk")
    p.add_argument("--asc", action="store_true")
    p.add_argument("--csv")
    a = p.parse_args()

    outdir = os.path.join(os.path.dirname(a.netlist) or ".", f"pnr_{a.name}_{a.device}")
    os.makedirs(outdir, exist_ok=True)
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda s: run(s, a, outdir), range(1, a.seeds + 1)))

    ok = [(s, r) for s, r in res if r]
    failed = [s for s, r in res if not r]
    if not ok:
        print(f"{a.name}: all {a.seeds} seeds failed (see {outdir}/*.log)")
        sys.exit(1)
    u = ok[0][1]["utilization"]
    lc, ram = u["ICESTORM_LC"]["used"], u["ICESTORM_RAM"]["used"]
    io = u.get("SB_IO", {}).get("used", 0)
    fmax = []
    for s, r in ok:
        f = r["fmax"]
        key = next((k for k in f if k == a.clock or k.endswith("$" + a.clock) or a.clock in k), None)
        fmax.append(f[key]["achieved"])
    row = dict(name=a.name, device=a.device, lc=lc, lc_avail=u["ICESTORM_LC"]["available"],
               ram=ram, io=io, seeds=len(ok), failed=len(failed),
               fmax_median=round(statistics.median(fmax), 2),
               fmax_worst=round(min(fmax), 2), fmax_best=round(max(fmax), 2),
               freq_target=a.freq)
    print(json.dumps(row))
    if a.csv:
        new = not os.path.exists(a.csv)
        with open(a.csv, "a", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(row))
            if new: w.writeheader()
            w.writerow(row)

if __name__ == "__main__":
    main()
