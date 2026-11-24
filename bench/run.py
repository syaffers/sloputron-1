#!/usr/bin/env python3
"""Phase 3 benchmark cores (D-005): synthesize and place & route F1 and F5 (ISA v2) over N seeds.

usage: bench/run.py [--seeds 16] [--jobs 3] [--csv bench/bench.csv] [variant-prefix ...]
Rows for the variants run replace their old rows in the CSV; other rows are kept.

Two harness sizes (bench/rtl/bench_top.sv):
  score  the standard skeleton harness (4 KB ROM, 256-word RAM, 8-bit data addresses). The
         figure of merit uses these cells and Fmax, which are comparable with Phase 2.
  fit    the whole system each configuration needs for the benchmarks: a 1 KB ROM, which
         holds all four kernels (135 words), and a data RAM of 256 x (threads + 1) words
         with 12-bit addresses. It checks that the system fits the chip and shows what the
         larger memory costs.
The ROM and RAM are filled with random words (fixed seed) so nothing constant-folds.
Cells and BRAMs come from nextpnr --report; LUT/carry/FF counts are from the Yosys netlist (info).
"""
import argparse, collections, csv, json, os, random, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = [os.path.join(ROOT, "bench", "rtl", f) for f in
       ("bench_top.sv", "r_alu.sv", "r_f1.sv", "r_f5.sv")]
PCF = os.path.join(ROOT, "board", "icestick.pcf")
BUILD = os.path.join(ROOT, "build", "bench", "synth")
SWEEP = os.path.join(ROOT, "scripts", "pnr_sweep.py")
TOOLS = os.path.join(ROOT, "tools", "oss-cad-suite", "bin")   # the pinned toolchain, if fetched
if os.path.isdir(TOOLS):
    os.environ["PATH"] = TOOLS + os.pathsep + os.environ["PATH"]

# name, design, core, threads, forwarding, harness
VARIANTS = [
    ("f1_n4",       "F1 barrel, 4 threads", 1, 4, 0, "score"),
    ("f1_n8",       "F1 barrel, 8 threads", 1, 8, 0, "score"),
    ("f5",          "F5 single, stalls",    5, 1, 0, "score"),
    ("f5_fwd",      "F5 single, forwarding", 5, 1, 1, "score"),
    ("fit_f1_n4",   "F1 barrel, 4 threads", 1, 4, 0, "fit"),
    ("fit_f1_n8",   "F1 barrel, 8 threads", 1, 8, 0, "fit"),
    ("fit_f5",      "F5 single, stalls",    5, 1, 0, "fit"),
    ("fit_f5_fwd",  "F5 single, forwarding", 5, 1, 1, "fit"),
]
HARNESS = dict(score=dict(ROMA=11, DEPTH=256, DA=8), fit=dict(ROMA=9, DA=12))


def random_hex(path, n, seed):
    rng = random.Random(seed)
    with open(path, "w") as f:
        for _ in range(n):
            f.write(f"{rng.getrandbits(16):04x}\n")


def build(name, core, n, fwd, harness, seeds, jobs):
    d = os.path.join(BUILD, name)
    os.makedirs(d, exist_ok=True)
    h = dict(HARNESS[harness])
    h.setdefault("DEPTH", 256 * (n + 1))
    random_hex(os.path.join(d, "skel_rom.hex"), 2 ** h["ROMA"], 1)
    random_hex(os.path.join(d, "skel_ram.hex"), h["DEPTH"], 2)
    g = " ".join(f"-G {k}={v}" for k, v in dict(CORE=core, N=n, FWD=fwd, **h).items())
    net = os.path.join(d, "synth.json")
    subprocess.run(["yosys", "-q", "-m", "slang", "-l", os.path.join(d, "yosys.log"), "-p",
                    f"read_slang {' '.join(RTL)} {g} --top bench_top; "
                    f"synth_ice40 -top bench_top -json {net}"], check=True, cwd=d)
    cells = collections.Counter(c["type"] for c in
                                json.load(open(net))["modules"]["bench_top"]["cells"].values())
    out = os.path.join(d, "sweep.json")
    subprocess.run([sys.executable, SWEEP, name, net, PCF, "--seeds", str(seeds), "--jobs", str(jobs),
                    "--out", out, "--outdir", os.path.join(d, "seeds")],
                   check=True, stdout=subprocess.DEVNULL)
    r = json.load(open(out))
    r.update(luts=cells["SB_LUT4"], carries=cells["SB_CARRY"],
             ffs=sum(k for t, k in cells.items() if t.startswith("SB_DFF")),
             yosys_brams=sum(k for t, k in cells.items() if t.startswith("SB_RAM")))
    return r


def main():
    p = argparse.ArgumentParser()
    p.add_argument("only", nargs="*", help="variant name prefixes (default: all)")
    p.add_argument("--seeds", type=int, default=16)
    p.add_argument("--jobs", type=int, default=3)
    p.add_argument("--csv", default=os.path.join(ROOT, "bench", "bench.csv"))
    a = p.parse_args()

    cols = ["name", "design", "harness", "threads", "lc", "brams", "luts", "carries", "ffs",
            "fmax_median", "fmax_worst", "seeds"]
    old = {}
    if os.path.exists(a.csv):
        old = {r["name"]: r for r in csv.DictReader(open(a.csv))}
    new = {}
    for name, fin, core, n, fwd, harness in VARIANTS:
        if a.only and not any(name == o or name.startswith(o + "_") for o in a.only):
            continue
        r = build(name, core, n, fwd, harness, a.seeds, a.jobs)
        assert r["ram"] == r["yosys_brams"], (name, r["ram"], r["yosys_brams"])
        new[name] = (dict(name=name, design=fin, harness=harness, threads=n, lc=r["lc"], brams=r["ram"],
                         luts=r["luts"], carries=r["carries"], ffs=r["ffs"],
                         fmax_median=r["fmax_median"], fmax_worst=r["fmax_worst"], seeds=r["seeds"]))
        print(f"{name:10s} {r['lc']:4d} LC {r['ram']:2d} BRAM  LUT {r['luts']:4d} carry {r['carries']:3d} "
              f"FF {r['ffs']:4d}  {r['fmax_median']:6.1f} / {r['fmax_worst']:6.1f} MHz", flush=True)
    with open(a.csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(new.get(v[0]) or old[v[0]] for v in VARIANTS if v[0] in new or v[0] in old)


if __name__ == "__main__":
    main()
