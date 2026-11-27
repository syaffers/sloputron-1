#!/usr/bin/env python3
"""Phase 4 step 1: where the cells of the CPU core go (docs/phase4/breakdown.md).

usage: bench/ablate.py [--rev d59bb57] [--seeds 1] [--csv bench/ablate.csv] [ablation ...]

Two measurements of rtl/core/f1_core.sv in the standard harness (bench_top CORE 0, score
sizes, the board's 1024-clock start-up hold), as bench/run.py builds it for the score:
  hierarchy  read_slang --keep-hierarchy, synth_ice40 -noflatten: LUTs, carries and flip-flops per module
             (f1_core, f1_alu, f1_cond; the harness is the rest). Information only.
  ablation   the core rebuilt with one block removed or tied off, by text substitution on a
             copy of f1_core.sv. The change in nextpnr's logic cells (ICESTORM_LC) is what
             that block costs once packed. The cell count is the same on every seed, so one
             seed is enough; --seeds > 1 also reports Fmax.
The substitutions match f1_core.sv as it was for step 1 (commit d59bb57, before step 2a
rewrote the ALU); --rev reads the core from that commit. The "base" row works on any version.
An ablated core does not run the ISA: it is a measuring device only. The blocks overlap
(for example the operand multiplexer feeds the adder), so the savings do not add up to the
total exactly.
"""
import argparse, collections, csv, json, os, random, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, "rtl", "core", "f1_core.sv")
PKG = os.path.join(ROOT, "rtl", "core", "isa_pkg.sv")
TOP = os.path.join(ROOT, "bench", "rtl", "bench_top.sv")
STUBS = [os.path.join(ROOT, "bench", "rtl", f) for f in ("r_alu.sv", "r_f1.sv", "r_f5.sv")]
PCF = os.path.join(ROOT, "board", "icestick.pcf")
BUILD = os.path.join(ROOT, "build", "bench", "ablate")
SWEEP = os.path.join(ROOT, "scripts", "pnr_sweep.py")
TOOLS = os.path.join(ROOT, "tools", "oss-cad-suite", "bin")
if os.path.isdir(TOOLS):
    os.environ["PATH"] = TOOLS + os.pathsep + os.environ["PATH"]
PARAMS = dict(CORE=0, N=4, X=7, ROMA=11, DEPTH=256, DA=8, STARTUP=1024)

# name, block, [(text in f1_core.sv, replacement)]: each text must occur exactly once
ABLATIONS = [
    ("hold", "start-up hold (counter, go, g0..g3)", [
        ("    logic [$clog2(STARTUP)-1:0] wait_n = '0;\n    logic go = 1'b0, g0 = 1'b0, g1 = 1'b0, g2 = 1'b0, g3 = 1'b0;",
         "    wire go = 1'b1, g0 = 1'b1, g1 = 1'b1, g2 = 1'b1, g3 = 1'b1;"),
        ("        if (!run)    wait_n <= '0;\n        else if (!go) wait_n <= wait_n + 1'b1;\n"
         "        if (&wait_n) go <= 1'b1;\n        g0 <= go;\n        g1 <= g0;\n        g2 <= g1;\n        g3 <= g2;\n", ""),
    ]),
    ("logic", "ALU logic ops (and, or, xor, pass)", [
        ("        ALU_AND:  y = x & s;\n        ALU_OR:   y = x | s;\n        ALU_XOR:  y = x ^ s;\n        ALU_PASS: y = s;\n", ""),
    ]),
    ("shifts", "ALU shifts (shl, shr, rcl, rcr) and their carry", [
        ("        ALU_SHL:  y = {x[14:0], ci};\n        default:  y = {ci, x[15:1]};", "        default:  y = x & s;"),
        ("    assign so = op == ALU_SHL ? x[15] : x[0];", "    assign so = 1'b0;"),
    ]),
    ("alu_mux", "ALU output multiplexer (y = sum always)", [
        ("    always_comb case (op)\n        ALU_ADD, ALU_SUB: y = sum[16:1];", "    assign y = sum[16:1];\n    always_comb case (op)\n        ALU_ADD, ALU_SUB: ;"),
        ("        ALU_AND:  y = x & s;\n        ALU_OR:   y = x | s;\n        ALU_XOR:  y = x ^ s;\n        ALU_PASS: y = s;\n", ""),
        ("        ALU_SHL:  y = {x[14:0], ci};\n        default:  y = {ci, x[15:1]};", "        default: ;"),
    ]),
    ("sub", "ALU subtract (operand inversion)", [
        ("    wire sub = op == ALU_SUB;", "    wire sub = 1'b0;"),
    ]),
    ("opmux", "operand multiplexer (s = rs only)", [
        ("    always_comb case (src2)\n        2'd0: s = xs;", "    assign s = xs;\n    always_comb case (src2)\n        2'd0: ;"),
        ("        2'd1: s = {{8{ins2[7]}}, ins2[7:0]};\n        2'd2: s = {ins2[7:0], xd[7:0]};\n        default: s = {5'd0, pc12};",
         "        default: ;"),
    ]),
    ("cond", "skip conditions (skip always)", [
        ("    f1_cond cnd (.v(xd), .cf(cf2), .cc(cc2), .t(c));", "    assign c = 1'b1;"),
    ]),
    ("pc2", "PC+2 adder (a taken skip goes to PC+1)", [
        ("        pc2 <= q[10:0] + 11'd2;", "        pc2 <= q[10:0] + 11'd1;"),
    ]),
    ("nextpc", "next-PC multiplexer and PC+2 (next PC = PC+1)", [
        ("    wire [10:0] pcn = jmp2 ? ins2 : jal2 ? xs[10:0] : (sk2 & c) ? pc22 : pc12;",
         "    wire [10:0] pcn = pc12;"),
    ]),
    ("carry", "carry-flag rule (C never changes)", [
        ("    wire        cfn = setc2 ? co : sh2 ? so : cf2;", "    wire        cfn = cf2;"),
    ]),
    ("branch", "branch on C (jmp only)", [
        ("(insn[12:11] == 2'd0 | (insn[11] & cf1) | (insn[12] & !cf1))", "1'b1"),
    ]),
    ("offset", "load/store offset adder (address = rs)", [
        ("    wire [DA-1:0] ea = xs[DA-1:0] + DA'(off2);", "    wire [DA-1:0] ea = xs[DA-1:0];"),
    ]),
    ("wbmux", "write-back multiplexer (ALU result only)", [
        ("    wire [15:0] wd = ld3 ? drd : y3;", "    wire [15:0] wd = y3;"),
    ]),
]


def random_hex(path, n, seed):
    rng = random.Random(seed)
    with open(path, "w") as f:
        for _ in range(n):
            f.write(f"{rng.getrandbits(16):04x}\n")


def synth(d, core, flatten=True):
    os.makedirs(d, exist_ok=True)
    random_hex(os.path.join(d, "skel_rom.hex"), 2 ** PARAMS["ROMA"], 1)     # as bench/run.py
    random_hex(os.path.join(d, "skel_ram.hex"), PARAMS["DEPTH"], 2)
    g = " ".join(f"-G {k}={v}" for k, v in PARAMS.items())
    net = os.path.join(d, "synth.json")
    subprocess.run(["yosys", "-q", "-m", "slang", "-l", os.path.join(d, "yosys.log"), "-p",
                    f"read_slang {PKG} {core} {TOP} {' '.join(STUBS)} {g} --top bench_top"
                    f"{'' if flatten else ' --keep-hierarchy'}; "
                    f"synth_ice40 -top bench_top {'' if flatten else '-noflatten'} -json {net}"],
                   check=True, cwd=d)
    return net


def counts(cells):
    c = collections.Counter(x["type"] for x in cells.values())
    return dict(luts=c["SB_LUT4"], carries=c["SB_CARRY"],
                ffs=sum(k for t, k in c.items() if t.startswith("SB_DFF")))


def place(name, d, net, seeds):
    out = os.path.join(d, "sweep.json")
    subprocess.run([sys.executable, SWEEP, name, net, PCF, "--seeds", str(seeds), "--jobs", "4",
                    "--out", out, "--outdir", os.path.join(d, "seeds")],
                   check=True, stdout=subprocess.DEVNULL)
    return json.load(open(out))


def hierarchy(src):
    d = os.path.join(BUILD, "hierarchy")
    os.makedirs(d, exist_ok=True)
    core = os.path.join(d, "f1_core.sv")
    open(core, "w").write(src)
    mods = json.load(open(synth(d, core, flatten=False)))["modules"]
    rows = {}
    for m, body in mods.items():
        name = re.sub(r"^\$paramod.*?\\", "", m).split("$")[0]
        if any(name.startswith(k) for k in ("f1_core", "f1_alu", "f1_cond", "bench_top")):
            rows[name] = counts(body["cells"])
    return rows


def main():
    p = argparse.ArgumentParser()
    p.add_argument("only", nargs="*", help="ablation names (default: all)")
    p.add_argument("--seeds", type=int, default=1)
    p.add_argument("--csv", default=os.path.join(ROOT, "bench", "ablate.csv"))
    p.add_argument("--hierarchy-only", action="store_true")
    p.add_argument("--rev", help="git revision to read f1_core.sv from (default: the working tree)")
    a = p.parse_args()

    src = (subprocess.run(["git", "show", f"{a.rev}:rtl/core/f1_core.sv"], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout if a.rev else open(CORE).read())
    print("hierarchy (Yosys, -noflatten):")
    for m, c in hierarchy(src).items():
        print(f"  {m:12s} LUT {c['luts']:4d}  carry {c['carries']:3d}  FF {c['ffs']:4d}")
    if a.hierarchy_only:
        return

    rows = []
    for name, block, subs in [("base", "f1_core as it is", [])] + ABLATIONS:
        if a.only and name != "base" and name not in a.only:
            continue
        s = src
        for old, new in subs:
            assert s.count(old) == 1, (name, old[:60], s.count(old))
            s = s.replace(old, new)
        d = os.path.join(BUILD, name)
        os.makedirs(d, exist_ok=True)
        core = os.path.join(d, "f1_core.sv")
        open(core, "w").write(s)
        net = synth(d, core)
        r = place(name, d, net, a.seeds)
        c = counts(json.load(open(net))["modules"]["bench_top"]["cells"])
        rows.append(dict(name=name, block=block, lc=r["lc"], **c,
                         fmax_median=r["fmax_median"], fmax_worst=r["fmax_worst"], seeds=r["seeds"]))
        base = rows[0]["lc"]
        print(f"{name:8s} {r['lc']:4d} LC ({r['lc'] - base:+4d})  LUT {c['luts']:4d} carry {c['carries']:3d} "
              f"FF {c['ffs']:4d}  {r['fmax_median']:6.1f} MHz  {block}", flush=True)
    with open(a.csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main()
