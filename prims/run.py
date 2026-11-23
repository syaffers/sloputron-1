#!/usr/bin/env python3
"""Phase 2 primitive cost table: synthesize and place & route every primitive in prims.sv
inside the same measurement harness, over N seeds, and subtract the harness itself.

usage: prims/run.py [--seeds 16] [--jobs 3] [--csv prims/prims.csv] [name-prefix ...]

Harness (generated per variant as build/prims/<name>/top.sv):
    sin --> [NIN-bit shift chain, enable `sen`] --> primitive --> [NOUT-bit register] --> XOR --> sout
- The input chain lets a primitive have 100+ inputs on 3 pins. It is marked keep, so every
  harness has exactly NIN chain FFs. Its enable keeps Yosys from merging the output register
  with chain bits.
- The output register is where a datapath would register the result anyway, so a
  primitive's last LUT level can pack into it, as it would in a real design.
- `p_wire` with the same NIN/NOUT measures the harness alone. A primitive's cost is
  LC(harness + primitive) - LC(harness): the cells it adds to a registered datapath.
- Fmax is the clk domain: input chain -> primitive -> output register (or the primitive's own
  registers). The bare harness runs far faster, so it doesn't limit the figure.
Cells and BRAMs come from nextpnr --report; LUT/carry/FF counts are from the Yosys netlist (info).
"""
import argparse, collections, csv, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRIMS = os.path.join(ROOT, "prims", "prims.sv")
PCF = os.path.join(ROOT, "prims", "prims.pcf")
BUILD = os.path.join(ROOT, "build", "prims")
SWEEP = os.path.join(ROOT, "scripts", "pnr_sweep.py")

def clog2(n):
    return max(1, (n - 1).bit_length())

# name, group, instance, NIN, NOUT, extra synth_ice40 flags, generated module source
V = []
def var(name, group, inst, pw, nout, flags="", gen=""):
    # pw = the primitive's input width. The chain is at least NOUT long, so the matching
    # wire baseline exists; extra chain bits are kept but unused.
    V.append(dict(name=name, group=group, inst=inst, pw=pw, nin=max(pw, nout), nout=nout,
                  flags=flags, gen=gen))

var("add16",    "arith", "p_add #(.W(16))",    32, 16)
var("addsub16", "arith", "p_addsub #(.W(16))", 33, 16)
var("addsub16_x", "arith", "p_addsub_x #(.W(16))", 33, 16)
var("inc13",    "arith", "p_inc #(.W(13))",    13, 13)
var("eq16",     "arith", "p_eq #(.W(16))",     32, 1)
var("ltu16",    "arith", "p_ltu #(.W(16))",    32, 1)
var("logic16",  "arith", "p_logic #(.W(16))",  34, 16)
for n in range(2, 9):
    var(f"mux{n}x16", "mux", f"p_mux #(.N({n}), .W(16))", clog2(n) + 16 * n, 16)
for n in (4, 8):
    var(f"mux1h{n}x16", "mux", f"p_mux1h #(.N({n}), .W(16))", n + 16 * n, 16)
var("shift1x16", "shift", "p_shift1 #(.W(16))", 18, 16)
var("bshl16",    "shift", "p_bshl #(.W(16))",   20, 16)
var("bshift16",  "shift", "p_bshift #(.W(16))", 22, 16)
var("bshift16_f", "shift", "p_bshift_f #(.W(16))", 22, 16)
var("rf256x16_1r_bram", "regfile", "p_rf_bram #(.R(1), .W(16))", 1 + 8 + 16 + 8, 16)
var("rf256x16_2r_bram", "regfile", "p_rf_bram #(.R(2), .W(16))", 1 + 8 + 16 + 16, 32)
var("rf8x16_2r_ff",     "regfile", "p_rf_ff #(.R(2), .D(8), .W(16))", 1 + 3 + 16 + 6, 32)
var("rf16x16_2r_ff",    "regfile", "p_rf_ff #(.R(2), .D(16), .W(16))", 1 + 4 + 16 + 8, 32)
for n in (4, 8):
    var(f"tpc{n}_ff",   "threadpc", f"p_tpc_ff #(.N({n}), .W(13))",   14, 13)
    var(f"tpc{n}_bram", "threadpc", f"p_tpc_bram #(.N({n}), .W(13))", 14, 13)

def rand_table(k, seed):
    x, out = seed, []
    for _ in range(1 << k):
        x ^= (x << 13) & 0xFFFFFFFF; x ^= x >> 17; x ^= (x << 5) & 0xFFFFFFFF
        out.append(x & 0xFFFF)
    return out

for k in (4, 5, 6, 8):
    t = rand_table(k, 0x1234567 + k)
    cases = "\n".join(f"        {k}'d{j}: o = 16'h{v:04x};" for j, v in enumerate(t))
    var(f"dec{k}_lut", "decode", f"p_dec_lut{k}", k, 16, flags="-nobram", gen=f"""
// random {k}-bit opcode -> 16 control bits (worst case: no structure to exploit)
module p_dec_lut{k} (input wire clk, input wire [{k-1}:0] i, output logic [15:0] o);
    always_comb case (i)
{cases}
        default: o = 'x;
    endcase
endmodule
""")
for k in (8,):
    t = rand_table(k, 0x1234567 + k)
    init = "\n".join(f"        rom[{j}] = 16'h{v:04x};" for j, v in enumerate(t))
    var(f"dec{k}_bram", "decode", f"p_dec_bram{k}", k, 16, gen=f"""
// same table in a BRAM ROM: no logic, one BRAM, one extra cycle of latency
module p_dec_bram{k} (input wire clk, input wire [{k-1}:0] i, output logic [15:0] o);
    (* ram_style = "block" *) logic [15:0] rom [{1 << k}];
    initial begin
{init}
    end
    always_ff @(posedge clk) o <= rom[i];
endmodule
""")

# harness baselines, one per distinct (NIN, NOUT)
for nin, nout in sorted({(v["nin"], v["nout"]) for v in V}):
    var(f"wire_{nin}_{nout}", "harness", f"p_wire #(.NIN({nin}), .NOUT({nout}))", nin, nout)

HARNESS = """`default_nettype none
module top (input wire clk, input wire sin, input wire sen, output wire sout);
    (* keep *) logic [{nin}-1:0] in_r = '0;   // all NIN chain FFs, used or not
    logic [{nout}-1:0] y, out_r = '0;
    always_ff @(posedge clk) if (sen) in_r <= {{in_r[{nin}-2:0], sin}};
    {inst} u (.clk(clk), .i(in_r[{pw}-1:0]), .o(y));
    always_ff @(posedge clk) out_r <= y;
    assign sout = ^out_r;
endmodule
{gen}"""

def build(v, seeds, jobs):
    d = os.path.join(BUILD, v["name"]); os.makedirs(d, exist_ok=True)
    top = os.path.join(d, "top.sv")
    with open(top, "w") as f:
        f.write(HARNESS.format(**v))
    net = os.path.join(d, "synth.json")
    subprocess.run(["yosys", "-q", "-m", "slang", "-l", os.path.join(d, "yosys.log"), "-p",
                    f"read_slang {PRIMS} {top} --top top; synth_ice40 {v['flags']} -top top -json {net}"],
                   check=True)
    cells = collections.Counter(c["type"] for c in
                                json.load(open(net))["modules"]["top"]["cells"].values())
    row = os.path.join(d, "sweep.json")
    subprocess.run([sys.executable, SWEEP, v["name"], net, PCF, "--seeds", str(seeds),
                    "--jobs", str(jobs), "--out", row, "--outdir", os.path.join(d, "seeds")],
                   check=True, stdout=subprocess.DEVNULL)
    r = json.load(open(row))
    r.update(luts=cells["SB_LUT4"], carries=cells["SB_CARRY"],
             ffs=sum(n for t, n in cells.items() if t.startswith("SB_DFF")),
             yosys_brams=sum(n for t, n in cells.items() if t.startswith("SB_RAM")))
    return r

def main():
    p = argparse.ArgumentParser()
    p.add_argument("only", nargs="*", help="variant name prefixes (default: all)")
    p.add_argument("--seeds", type=int, default=16)
    p.add_argument("--jobs", type=int, default=3)
    p.add_argument("--csv", default=os.path.join(ROOT, "prims", "prims.csv"))
    a = p.parse_args()

    todo = [v for v in V if v["group"] != "harness"
            and (not a.only or any(v["name"].startswith(o) for o in a.only))]
    need = {f"wire_{v['nin']}_{v['nout']}" for v in todo}
    todo = [v for v in V if v["name"] in need] + todo
    res = {}
    for v in todo:
        res[v["name"]] = r = build(v, a.seeds, a.jobs)
        print(f"{v['name']:18s} {r['lc']:4d} LC {r['ram']:2d} BRAM  "
              f"{r['fmax_median']:6.1f} / {r['fmax_worst']:6.1f} MHz", flush=True)

    cols = ["name", "group", "nin", "nout", "lc", "lc_harness", "lc_prim", "luts_prim",
            "carries_prim", "ffs_prim", "brams", "fmax_median", "fmax_worst", "seeds"]
    rows = []
    for v in todo:
        r = res[v["name"]]
        h = res[f"wire_{v['nin']}_{v['nout']}"]
        rows.append(dict(name=v["name"], group=v["group"], nin=v["nin"], nout=v["nout"],
                         lc=r["lc"], lc_harness=h["lc"], lc_prim=r["lc"] - h["lc"],
                         luts_prim=r["luts"] - h["luts"], carries_prim=r["carries"] - h["carries"],
                         ffs_prim=r["ffs"] - h["ffs"], brams=r["ram"],
                         fmax_median=r["fmax_median"], fmax_worst=r["fmax_worst"], seeds=r["seeds"]))
    with open(a.csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)
    print("\n| primitive | cells added (registered output) | LUT4 | carry | FF | BRAM | Fmax median / worst (MHz) |")
    print("|---|---:|---:|---:|---:|---:|---|")
    for r in rows:
        if r["group"] != "harness":
            print(f"| {r['name']} | {r['lc_prim']} | {r['luts_prim']} | {r['carries_prim']} | {r['ffs_prim']} "
                  f"| {r['brams']} | {r['fmax_median']:.1f} / {r['fmax_worst']:.1f} |")

if __name__ == "__main__":
    main()
