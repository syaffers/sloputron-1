# sloputron-1 — an original 16-bit CPU for the iCE40HX1K (iCEstick)

Read this first. The repo is the single source of truth for the project. The claude.ai
project "iCE40HX1K 16-bit CPU" mirrors `docs/`. When you change a doc here, the mirror is
updated from a claude.ai session, so say in your summary which docs changed.

## Goal and figure of merit
Design an original 16-bit CPU that gets the most useful work per logic cell while fitting
entirely in an iCE40HX1K-TQ144.
- **Figure of merit:** benchmark iterations/s at measured Fmax ÷ logic cells used, per kernel,
  combined by geometric mean. Barrels count N copies (N−1 with a UART thread). See D-002.
- **Secondary:** code size; program memory is ≤ 8 KB.
- **Benchmarks:** crc16 (CCITT-FALSE, 256 B, bitwise), insertion sort of 64 words, 64×
  16×16→32 multiplies, and memcpy of 256 words. Exact inputs and check values are in
  `docs/decisions/D-002-benchmarks.md`. Assembly only; no C compiler.

## Chip facts that drive every decision
- 1,280 logic cells (LUT4 + DFF + carry). Everything counts: CPU, I/O, debug. Leave ~5%
  free for routing.
- 16 × SB_RAM40_4K (256×16 natural). Each block has 1 read + 1 write port and a
  synchronous read. A 2-read-port register file = 2 blocks with duplicated writes.
- **No LUT RAM on iCE40.** Any state outside BRAM costs one cell per bit. Measured: 512 of
  J1a's 583 DFFs are its stacks, and the 4-thread J4a needs 3,417 cells. State belongs in
  BRAM.
- Mark BRAM memories `(* no_rw_check *)` unless the value of a same-address read during a
  write matters. Without it Yosys adds about 57 LC per read port to guarantee the old value
  (`docs/phase2/primitives.md`).
- 12 MHz oscillator, 1 PLL (`icepll`). J1a runs at 48 MHz on this board.
- I/O: FT2232H (channel A = SPI flash/programming, channel B = UART), 5 LEDs, Pmod,
  16 header pins.

## Rules (non-negotiable)
- Cell and BRAM counts come from **nextpnr post-placement utilisation** (`ICESTORM_LC`,
  `ICESTORM_RAM`, via `--report`), never from Yosys `stat` alone.
- Fmax = **median over ≥ 16 nextpnr seeds**; also report the worst seed. Confirm on hardware
  with a PLL sweep.
- Every number carries its toolchain version and seed count. Label estimates as estimates.
- Published figures from other toolchains are context only; never use them for comparison.
- Prefer removing hardware to adding it: what a thread or a BRAM table can do should not be
  logic.
- Every architectural choice gets a short decision record in `docs/decisions/`.
- (Phase 1 onward) Every commit appends a row to `results.csv`: commit, cells, BRAMs, Fmax
  median/worst, benchmark cycles, code size. CI fails if the design exceeds the cell budget
  or regresses without a note.

## Toolchain (pinned)
- OSS CAD Suite **2026-11-01**: Yosys 0.70+286, nextpnr-ice40 0.11.1-85-ga2c64799,
  Verilator 5. Install with `scripts/fetch_toolchain.sh` (or put the same release on PATH).
- HDL: synthesizable SystemVerilog through the Yosys **slang** front end. Instantiate iCE40
  primitives (SB_RAM40_4K, SB_CARRY, SB_LUT4) directly where inference wastes cells.
- Planned: the ISA in one TOML spec that generates customasm rules, C decode tables, an SV
  decode package and docs; a C99 cycle-counting ISS; Verilator lockstep with an RVFI-style
  retirement port; SymbiYosys formal checks; icebram + iceprog for program loading.
- nextpnr flags: `--hx1k --package tq144 --freq 100 --timing-allow-fail`, seeds 1..16.

## Layout
```
CLAUDE.md                 this file
Makefile                  the flow: bits, prog, sim, lint, sweep, report, check (`make help`)
results.csv               one row per design per hardware commit (docs/process.md)
board/icestick.pcf        every iCEstick pin, by port name (clk, led[4:0], uart_tx/rx, pmod[7:0], hdr_j1/j3)
rtl/board/                top-level designs (top module name = design name)
rtl/lib/                  shared RTL (uart_rx, uart_tx, stack_bram)
sim/                      self-checking Verilator testbenches (print PASS or $fatal)
docs/process.md           results.csv protocol and CI rules
docs/phase0/              baselines.md, bibliography.md, tricks.md, shortlist.md (decision D-001)
docs/phase1/bringup.md    board bring-up steps and checklist
docs/phase2/              Phase 2 experiments (j1a_bram.md)
docs/decisions/           decision record index
baselines/                uniform harnesses for third-party cores + build.sh + results CSVs
prims/                    primitive cost table: prims.sv, run.py (harness + 16-seed sweep), prims.csv
scripts/pnr_sweep.py      multi-seed nextpnr sweep -> LC, BRAM, Fmax median/worst/best (JSON/CSV)
scripts/report.py         append results.csv rows; scripts/check_results.py = CI gate
scripts/uart_test.py      host-side loopback test against uart_echo
scripts/setup_*.sh        one-shot setup: setup_debian.sh (apt, udev, groups) / setup_macos.sh; both fetch the toolchain
scripts/fetch_*.sh        pinned toolchain and baseline sources (into tools/ and ext/, gitignored)
.github/workflows/ci.yml  lint, sim, bitstreams, 16-seed sweep, results.csv gate (linux-x86_64 + macOS arm64)
```

## Commands
```
make help                         # all targets
make bits / make prog D=uart_echo # build / flash (board machine only)
make sim lint                     # before every commit
make report NOTE="..."            # 16-seed sweep -> results.csv rows; required with any rtl/ or board/ change
make check                        # what CI runs
cd baselines && SEEDS=16 ./build.sh   # third-party baselines (after scripts/fetch_baselines.sh)
```
`baselines/build.sh` appends to `baselines/baselines.csv`. Set `CSV=<scratch file>` for trial runs.

## Status
- **Phase 0 (done):** literature survey, baselines (16 seeds), shortlist.
  - Best measured: Leros, 343 LC at 84 MHz (SERV is smaller at 336 LC, but ~36 CPI).
  - J1a: 898 LC at 88 MHz (re-measured 2026-11-23 with `no_rw_check` on the harness RAM;
    originally 1013 LC).
  - PicoRV32 small: does not fit.
  - See `docs/phase0/baselines.md`.
- **Phase 1 (in progress):** done in the repo:
  - Makefile flow, results.csv with a CI gate;
  - blinky (30 LC) and hardware UART echo (86 LC), simulation passing.
  - Board run passed 2026-11-23: blinky, UART echo PASS, 2.6 s flash (`docs/phase1/bringup.md`).
- **Phase 2 (in progress):** primitive cost table plus bare datapath skeletons of the
  finalists.
  - Experiment 1 done: J1a with stacks in BRAM is 422 LC, 10 BRAM, 87.0 MHz median (was
    898 LC, 88.5 MHz). It uses `rtl/lib/stack_bram.sv`: falling-edge speculative write, no
    bypass. See `docs/phase2/j1a_bram.md`.
  - Primitive cost table done (`docs/phase2/primitives.md`, `prims/run.py`). BRAM register
    file is 1–2 LC, against 296 LC for 8×16 in FFs. A full barrel shifter is 134 LC,
    against 14 LC for shift-by-1. Mux cost is 1/3/6 LUTs per bit for 2:1/4:1/8:1.
  - The baselines were re-measured with `no_rw_check` on the harness RAMs: 76–135 LC less
    per core. SERV now edges Leros on raw cells; the work-per-cell order is unchanged
    (`docs/phase0/baselines.md`).
- **Phase 3:** an ISA, simulator and assembler per finalist; benchmark cycle counts; commit to
  one concept.

Shortlist (D-001), a 2×2 of thread organisation × operand model:

| | Stack (stacks in BRAM) | Register window / accumulator (RF in BRAM) |
|---|---|---|
| Single thread | **F2** — J1 lineage | **F3** — Leros/TMS9900 lineage |
| Barrel, 4–8 threads | **F4** — J4/Hive lineage | **F1** — Octavo/BRISKI/XMOS lineage |

## Open questions (owner decides; don't assume)
- None open right now.
- Settled in D-002: Q1 (barrels are ranked on N copies), Q2 (the UART thread's slot is
  overhead), Q3 (geometric mean), the benchmark variants, and assembly only.

## Working on the board (local sessions)
- The iCEstick is attached to the owner's machine: a Debian trixie board (aarch64) or a
  MacBook Air M2. Cloud sessions cannot reach it.
- First-time setup: `scripts/setup_debian.sh` (then log out and back in), or
  `scripts/setup_macos.sh`.
- Flash with `make prog D=<design>`. On a Mac, `sudo` if the FTDI device can't be claimed.
- UART (FT2232H channel B): `/dev/ttyUSB1` on Linux, the last `/dev/cu.usbserial-*` on a
  Mac. `make uart-test` picks it; override with `PORT=`.
- results.csv rows record the platform. Cells/BRAMs are identical across platforms; Fmax
  differs slightly (see `docs/process.md`). Comparison tables use linux-x86_64 (CI).
- Keep I/O hardware minimal; a UART may end up as a software thread.
