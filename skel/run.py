#!/usr/bin/env python3
"""Phase 2 datapath skeletons: synthesize and place & route each finalist's skeleton in the
shared harness (skel/rtl/skel_top.sv) over N seeds.

usage: skel/run.py [--seeds 16] [--jobs 3] [--csv skel/skel.csv] [variant-prefix ...]

The harness ROM and RAM are filled with random words (fixed seed) so nothing constant-folds.
Cells and BRAMs come from nextpnr --report; LUT/carry/FF counts are from the Yosys netlist (info).
"""
import argparse, collections, csv, json, os, random, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = [os.path.join(ROOT, p) for p in (
    "skel/rtl/skel_top.sv", "skel/rtl/skel_alu.sv", "skel/rtl/skel_f1.sv", "skel/rtl/skel_f2.sv",
    "skel/rtl/skel_f3.sv", "skel/rtl/skel_f4.sv", "rtl/lib/stack_bram.sv")]
PCF = os.path.join(ROOT, "board", "icestick.pcf")
BUILD = os.path.join(ROOT, "build", "skel", "synth")
SWEEP = os.path.join(ROOT, "scripts", "pnr_sweep.py")
TOOLS = os.path.join(ROOT, "tools", "oss-cad-suite", "bin")   # the pinned toolchain, if fetched
if os.path.isdir(TOOLS):
    os.environ["PATH"] = TOOLS + os.pathsep + os.environ["PATH"]

# name, finalist, core, threads
VARIANTS = [
    ("f1_n4", "F1 barrel, registers", 1, 4),
    ("f1_n8", "F1 barrel, registers", 1, 8),
    ("f2",    "F2 stack",             2, 1),
    ("f3",    "F3 accumulator",       3, 1),
    ("f4_n4", "F4 barrel, stack",     4, 4),
    ("f4_n8", "F4 barrel, stack",     4, 8),
]


def random_hex(path, n, seed):
    rng = random.Random(seed)
    with open(path, "w") as f:
        for _ in range(n):
            f.write(f"{rng.getrandbits(16):04x}\n")


def build(name, core, n, seeds, jobs):
    d = os.path.join(BUILD, name)
    os.makedirs(d, exist_ok=True)
    random_hex(os.path.join(d, "skel_rom.hex"), 2048, 1)
    random_hex(os.path.join(d, "skel_ram.hex"), 256, 2)
    net = os.path.join(d, "synth.json")
    subprocess.run(["yosys", "-q", "-m", "slang", "-l", os.path.join(d, "yosys.log"), "-p",
                    f"read_slang {' '.join(RTL)} -G CORE={core} -G N={max(n, 4)} --top skel_top; "
                    f"synth_ice40 -top skel_top -json {net}"], check=True, cwd=d)
    cells = collections.Counter(c["type"] for c in
                                json.load(open(net))["modules"]["skel_top"]["cells"].values())
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
    p.add_argument("--csv", default=os.path.join(ROOT, "skel", "skel.csv"))
    a = p.parse_args()

    cols = ["name", "finalist", "threads", "lc", "brams", "luts", "carries", "ffs",
            "fmax_median", "fmax_worst", "seeds"]
    rows = []
    for name, fin, core, n in VARIANTS:
        if a.only and not any(name.startswith(o) for o in a.only):
            continue
        r = build(name, core, n, a.seeds, a.jobs)
        assert r["ram"] == r["yosys_brams"], (name, r["ram"], r["yosys_brams"])
        rows.append(dict(name=name, finalist=fin, threads=n, lc=r["lc"], brams=r["ram"],
                         luts=r["luts"], carries=r["carries"], ffs=r["ffs"],
                         fmax_median=r["fmax_median"], fmax_worst=r["fmax_worst"], seeds=r["seeds"]))
        print(f"{name:6s} {r['lc']:4d} LC {r['ram']:2d} BRAM  LUT {r['luts']:4d} carry {r['carries']:3d} "
              f"FF {r['ffs']:4d}  {r['fmax_median']:6.1f} / {r['fmax_worst']:6.1f} MHz", flush=True)
    with open(a.csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main()
