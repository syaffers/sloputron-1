#!/usr/bin/env python3
"""Clock sweep of the sloputron CPU on the iCEstick: find the highest clock it runs at.

usage: scripts/board_sweep.py [--mhz 12,48,60,...] [--seed 1] [--secs 4] [--port /dev/ttyUSB1]
                              [--csv docs/phase3/board_sweep.csv] [--no-prog]

For each clock it builds the `sloputron` design with programs/stress.s in ROM, the clock
from the PLL (settings from `icepll -i 12 -o MHZ`; 12 means the oscillator, no PLL) and the
UART divider for that clock. Then it runs nextpnr with one seed, flashes the board, and
queries the stress program over the UART:
  - every reply must be a well-formed line, and every failure count must stay 0;
  - every worker's pass count must rise;
  - the pass rate times the clocks per pass (from isa/iss.py) gives the clock the CPU
    actually ran at, so a wrong PLL setting cannot pass unnoticed.
The UART divider follows the clock, so even the reply text depends on the clock being right.
A row per clock goes to --csv. Flashing needs the plugdev group and the UART the dialout
group (scripts/setup_debian.sh); when they are not active yet, the commands run via `sg`.
"""
import argparse, csv, datetime, grp, json, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools", "oss-cad-suite", "bin")
if os.path.isdir(TOOLS):
    os.environ["PATH"] = TOOLS + os.pathsep + os.environ["PATH"]
sys.path.insert(0, os.path.join(ROOT, "isa"))
from iss import Board, read_hex  # noqa: E402

SRC = ["rtl/core/isa_pkg.sv", "rtl/core/f1_core.sv", "rtl/board/sloputron.sv",
       "rtl/lib/uart_rx.sv", "rtl/lib/uart_tx.sv", "rtl/lib/sb_pll40_core.sv"]
PROGRAM = "build/programs/stress.hex"
COUNTS = 0x020                       # programs/stress.s: P1 F1 P2 F2 P3 F3
WORKERS = {1: "crc16", 2: "mul16", 3: "sort"}
LINE = re.compile(rb"^([0-9A-F]{4}) ([0-9A-F]{4}) ([0-9A-F]{4}) ([0-9A-F]{4}) "
                  rb"([0-9A-F]{4}) ([0-9A-F]{4})\r\n$")


def sh(cmd, group=None, **kw):
    """Run cmd (a list) in ROOT; via `sg GROUP` when that group is not active in this shell."""
    if group and grp.getgrnam(group).gr_gid not in os.getgroups():
        cmd = ["sg", group, "-c", " ".join(cmd)]
    return subprocess.run(cmd, cwd=ROOT, check=True, **kw)


def pll(mhz):
    """(DIVR, DIVF, DIVQ, FILTER_RANGE, achieved MHz) from icepll."""
    out = subprocess.run(["icepll", "-i", "12", "-o", str(mhz)], capture_output=True,
                         text=True, check=True).stdout
    get = lambda k: int(re.search(rf"^{k}:\s*(\d+)", out, re.M).group(1))
    f = float(re.search(r"F_PLLOUT:\s*([\d.]+) MHz \(achieved\)", out).group(1))
    return get("DIVR"), get("DIVF"), get("DIVQ"), get("FILTER_RANGE"), f


def clocks_per_pass():
    """Clocks between successive pass-count stores of each worker, from the ISS."""
    b, last, per = Board(read_hex(os.path.join(ROOT, PROGRAM))), {}, {}

    def on_store(b, t, a, v):
        if a == COUNTS + 2 * (t - 1):
            if t in last:
                per[t] = b.clock - last[t]
            last[t] = b.clock
    b.on_store = on_store
    while len(per) < len(WORKERS):
        b.run(10_000)
    return per


def build(mhz, seed, out):
    os.makedirs(out, exist_ok=True)
    if mhz == 12:
        divr = divf = divq = filt = 0
        f = 12.0
    else:
        divr, divf, divq, filt, f = pll(mhz)
    g = dict(CLK_HZ=round(f * 1e6), PLL_DIVR=divr, PLL_DIVF=divf, PLL_DIVQ=divq, PLL_FILTER=filt)
    gs = " ".join(f"-G {k}={v}" for k, v in g.items()) + f' -G ROM="{PROGRAM}"'
    sh(["yosys", "-q", "-m", "slang", "-l", f"{out}/yosys.log", "-p",
        f"read_slang {' '.join(SRC)} --top sloputron {gs}; "
        f"synth_ice40 -top sloputron -json {out}/synth.json"])
    sh(["nextpnr-ice40", "--hx1k", "--package", "tq144", "--pcf", "board/icestick.pcf",
        "--freq", "100", "--timing-allow-fail", "--seed", str(seed), "--json",
        f"{out}/synth.json", "--asc", f"{out}/top.asc", "--report", f"{out}/pnr.json",
        "-l", f"{out}/nextpnr.log", "-q"])
    sh(["icepack", f"{out}/top.asc", f"{out}/top.bin"])
    r = json.load(open(os.path.join(ROOT, out, "pnr.json")))
    fmax = min(v["achieved"] for v in r["fmax"].values())
    return f, g, r["utilization"]["ICESTORM_LC"]["used"], fmax


def query(port, timeout):
    """Send one byte, return (host time, line or None)."""
    port.reset_input_buffer()
    port.write(b"r")
    line = port.readline()
    t = time.monotonic()
    return t, (line if LINE.match(line or b"") else (line or None))


def test(dev, secs, per, mhz):
    import serial
    res = dict(lines=0, bad=0, fails=0, rises=True, mhz_meas={})
    with serial.Serial(dev, 115200, timeout=1.0) as s:
        time.sleep(0.5)                                   # start-up line "S"
        samples = []
        t_end = time.monotonic() + secs
        while True:
            t, line = query(s, 1.0)
            if line is None or not LINE.match(line):
                res["bad"] += 1
                if res["bad"] >= 3:
                    break
            else:
                res["lines"] += 1
                v = [int(x, 16) for x in LINE.match(line).groups()]
                res["fails"] = max(res["fails"], v[1], v[3], v[5])
                samples.append((t, v))
            if time.monotonic() > t_end:
                break
            time.sleep(0.25)
    if len(samples) >= 2:
        (t0, a), (t1, b) = samples[0], samples[-1]
        for k, t in enumerate(WORKERS):
            d = (b[2 * k] - a[2 * k]) % 65536
            res["rises"] &= d > 0
            res["mhz_meas"][WORKERS[t]] = d * per[t] / (t1 - t0) / 1e6
    else:
        res["rises"] = False
    meas = list(res["mhz_meas"].values())
    clock_ok = bool(meas) and all(abs(m / mhz - 1) < 0.01 for m in meas)
    res["pass"] = res["bad"] == 0 and res["fails"] == 0 and res["rises"] and clock_ok
    return res


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mhz", default="12,48,60,72,84,90,96,102,108,114,120,126,132,144")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--secs", type=float, default=4)
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--csv", default=os.path.join(ROOT, "docs/phase3/board_sweep.csv"))
    p.add_argument("--stop-after", type=int, default=2, help="stop after this many failures in a row")
    a = p.parse_args()

    sh(["make", "-s", PROGRAM])
    per = clocks_per_pass()
    print("clocks per pass:", {WORKERS[t]: n for t, n in per.items()})
    import tomllib
    isa_version = tomllib.load(open(os.path.join(ROOT, "isa", "isa.toml"), "rb"))["isa"]["version"]
    tool = subprocess.run(["yosys", "-V"], capture_output=True, text=True).stdout.split()[1]
    new = not os.path.exists(a.csv)
    fh = open(a.csv, "a", newline="")
    w = csv.writer(fh)
    if new:
        w.writerow(["date", "yosys", "isa", "seed", "mhz_requested", "mhz_pll", "lc", "nextpnr_fmax",
                    "mhz_measured", "lines", "bad_lines", "fails", "result"])
    fails_in_row = 0
    for mhz in [float(x) for x in a.mhz.split(",")]:
        mhz = int(mhz) if mhz == int(mhz) else mhz
        out = f"build/board_sweep/s{a.seed}_{mhz}"
        f, g, lc, fmax = build(mhz, a.seed, out)
        sh(["iceprog", f"{out}/top.bin"], group="plugdev", capture_output=True)
        # the UART needs the dialout group; re-run this part under sg when it is missing
        if grp.getgrnam("dialout").gr_gid in os.getgroups():
            r = test(a.port, a.secs, per, f)
        else:
            q = subprocess.run(["sg", "dialout", "-c", f"python3 {__file__} --_test {a.port} "
                                f"{a.secs} {f} '{json.dumps(per)}'"], capture_output=True,
                               text=True, check=True)
            r = json.loads(q.stdout.strip().splitlines()[-1])
        meas = r["mhz_meas"]
        m = sum(meas.values()) / len(meas) if meas else 0
        verdict = "PASS" if r["pass"] else "FAIL"
        print(f"{mhz:>6} MHz req  {f:7.2f} PLL  {lc} LC  nextpnr {fmax:6.2f}  measured {m:7.2f}  "
              f"lines {r['lines']}  bad {r['bad']}  fails {r['fails']}  {verdict}  "
              + " ".join(f"{k} {v:.2f}" for k, v in meas.items()), flush=True)
        w.writerow([datetime.date.today().isoformat(), tool, isa_version, a.seed, mhz, f"{f:.3f}", lc,
                    f"{fmax:.2f}", f"{m:.2f}", r["lines"], r["bad"], r["fails"], verdict])
        fh.flush()
        fails_in_row = 0 if r["pass"] else fails_in_row + 1
        if fails_in_row >= a.stop_after:
            break


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--_test":      # the UART part, run under sg
        port, secs, f, per = sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), json.loads(sys.argv[5])
        r = test(port, secs, {int(k): v for k, v in per.items()}, f)
        print(json.dumps(r))
    else:
        main()
