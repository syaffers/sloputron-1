# sloputron-1 — an original 16-bit CPU for the iCE40HX1K (iCEstick)

Read this first. The repo is the single source of truth for the project. The claude.ai
project "iCE40HX1K 16-bit CPU" mirrors `docs/`. When you change a doc here, the mirror is
updated from a claude.ai session, so say in your summary which docs changed.

## Goal and figure of merit
Design an original 16-bit CPU that gets the most useful work per logic cell while fitting
entirely in an iCE40HX1K-TQ144.
- **Figure of merit:** benchmark iterations/s at measured Fmax ÷ logic cells used, per kernel,
  combined by geometric mean. Barrels count N copies. The UART is not scored for any design.
  See D-002 and D-004.
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
- The ISA is one TOML spec (`isa/isa.toml`) that generates the SV decode package and the
  docs and drives the assembler (customasm dropped, D-008). Planned: C decode tables with a
  C99 cycle-counting ISS; Verilator lockstep with an RVFI-style retirement port; SymbiYosys
  formal checks; icebram + iceprog for program loading.
- nextpnr flags: `--hx1k --package tq144 --freq 100 --timing-allow-fail`, seeds 1..16.

## Layout
```
CLAUDE.md                 this file
Makefile                  the flow: bits, prog, sim, lint, sweep, report, check (`make help`)
results.csv               one row per design per hardware commit (docs/process.md)
board/icestick.pcf        every iCEstick pin, by port name (clk, led[4:0], uart_tx/rx, pmod[7:0], hdr_j1/j3)
rtl/board/                top-level designs (top module name = design name); sloputron.sv = the CPU on the board
rtl/core/                 the CPU core: f1_core.sv (D-006) and isa_pkg.sv (generated from isa/isa.toml)
rtl/lib/                  shared RTL (uart_rx, uart_tx, stack_bram)
isa/                      the ISA: isa.toml (single source), isa.py/asm.py (assembler), gen.py (spec doc + isa_pkg.sv), iss.py (Python ISS of the board), test_isa.py
programs/                 assembly programs: demo.s (banner + echo), stress.s (clock-sweep test); make assembles them to build/programs/*.hex
docs/isa/isa.md           the written ISA spec (generated; edit isa/isa.toml, then `make isa`)
sim/                      self-checking Verilator testbenches (print PASS or $fatal)
docs/process.md           results.csv protocol and CI rules
docs/phase0/              baselines.md, bibliography.md, tricks.md, shortlist.md (decision D-001)
docs/phase1/bringup.md    board bring-up steps and checklist
docs/phase2/              Phase 2 experiments (j1a_bram.md, primitives.md, skeletons.md)
docs/phase3/              Phase 3: benchmarks.md (D-002 kernels, ISA 1.0 study), board.md (the CPU on the iCEstick, PLL sweep), board_sweep.csv
docs/decisions/           decision record index
baselines/                uniform harnesses for third-party cores + build.sh + results CSVs
prims/                    primitive cost table: prims.sv, run.py (harness + 16-seed sweep), prims.csv
bench/                    Phase 3 benchmark cores (F1, F5; ISA v3 + D-008 extensions X): rtl/, sim/, kernels.py (assembler, kernels, reference interpreter), run.py (16-seed sweep -> bench.csv), score.py (figure of merit -> score.csv)
skel/                     F1–F5 datapath skeletons: rtl/, sim/ (crc16 + hazard tests), asm.py (+ reference interpreter), run.py (16-seed sweep), skel.csv
scripts/pnr_sweep.py      multi-seed nextpnr sweep -> LC, BRAM, Fmax median/worst/best (JSON/CSV)
scripts/report.py         append results.csv rows; scripts/check_results.py = CI gate
scripts/uart_test.py      host-side loopback test against uart_echo (or sloputron's echo)
scripts/board_sweep.py    PLL clock sweep on the board: build at each clock, flash, check programs/stress.s
scripts/setup_*.sh        one-shot setup: setup_debian.sh (apt, udev, groups) / setup_macos.sh; both fetch the toolchain
scripts/fetch_*.sh        pinned toolchain and baseline sources (into tools/ and ext/, gitignored)
.github/workflows/ci.yml  lint, sim, bitstreams, 16-seed sweep, results.csv gate (linux-x86_64 + macOS arm64)
```

## Commands
```
make help                         # all targets
make bits / make prog D=uart_echo # build / flash (board machine only)
make sim lint                     # before every commit (sim also runs isa-test)
make isa                          # after editing isa/isa.toml: regenerate docs/isa/isa.md + rtl/core/isa_pkg.sv
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
  - Skeletons of F1–F4 done (`docs/phase2/skeletons.md`, `skel/`). They share an ALU and a
    harness, and each passes a crc16 test. Cells / Fmax median (16 seeds): F1 barrel
    registers 312 (4 threads) / 320 (8) at 87 MHz; F2 stack 359 at 83; F3 accumulator 292
    at 96; F4 barrel stack 338 / 345 at 87. 4 → 8 threads costs 7–8 LC. The shared ALU
    (118 LUT) is the largest block and sets most critical paths. The cost table
    under-predicts whole cores by 21–44%.
  - F5 control (D-003): F1's instructions on one thread. 329 LC at 86 MHz with one-cycle
    stalls; forwarding (368 LC, 78 MHz) does not pay. On the crc test, two-operand
    instructions give 1.24× F3's work per cell, and F1's threads add a further 1.42×
    (N copies; the UART is not scored, D-004).
- **Phase 3 (in progress):** D-005 narrowed the shortlist to F1 (barrel) and F5 (single
  thread), which share a two-operand register ISA (v2).
  - All four D-002 kernels run on both, checked against a reference interpreter
    (`docs/phase3/benchmarks.md`, `bench/`).
  - ISA v3 adds a carry flag and `cmp`. v2 compared in one cycle through the ALU carry,
    which cost both cores 15–23% of their Fmax.
  - Geometric mean, iterations/s per 1000 core cells (D-005: core cells only; 16 seeds):
    - F1 4 threads: 37,364 (336 LC, 90.0 MHz);
    - F1 8 threads: 35,974;
    - F5 stalls: 28,526 (338 LC, 84.1 MHz).

    F1 with 4 threads leads by 1.31×. On whole-system cells the two are level (1.02×).
  - **D-006: the CPU is F1 with 4 threads** (barrel, two-operand registers, state in BRAM).
  - **ISA spec 0.3** (= v3) is written: `isa/isa.toml` generates `docs/isa/isa.md` and
    `rtl/core/isa_pkg.sv` and drives the assembler `isa/asm.py`. Every canonical encoding
    round-trips. customasm is not in the toolchain, so its rules are deferred.
  - **D-007: hardware UART**, memory-mapped at 0xFFC–0xFFF beside the LEDs.
  - **The CPU runs on the board** (design `sloputron`, `docs/phase3/board.md`):
    - the four-thread demo prints `crc16=29B1` and echoes 4,096 bytes with 0 errors;
    - iCE40 BRAMs read wrong just after configuration, so the core holds for 1,024
      clocks (19 LC).
  - **PLL sweep** (`scripts/board_sweep.py`, 3 seeds, `docs/phase3/board.md`):
    - every build runs the stress program correctly up to 114 MHz (ISA 0.3) and 126 MHz
      (ISA 1.0);
    - nextpnr's ~90 MHz is therefore conservative by at least 25% on this board at room
      temperature.
  - **Whole CPU with ISA 1.0:** 481 LC, 15 BRAMs, 89.5 / 86.7 MHz (16 seeds).
  - **D-008: ISA 1.0** = 0.3 + branch on C (`bcc`/`bcs`) + carry shifts (`rcl`/`rcr`;
    shifts set C) + a 4-bit load/store offset. That is 1.23× the work per clock per cell:
    354 LC, geometric mean 48,768 (0.3: 38,295 in the same run). No 12-bit PC, multiply
    step or shift-by-N. The board runs 1.0.
  - Next:
    - the C99 ISS and Verilator lockstep (`isa/iss.py` is a Python start).

Shortlist (D-001), a 2×2 of thread organisation × operand model. D-005 narrowed it to F1
and F5 (F5 runs F1's ISA on a single thread, D-003). **D-006 chose F1 with 4 threads.**

| | Stack (stacks in BRAM) | Register window / accumulator (RF in BRAM) |
|---|---|---|
| Single thread | **F2** — J1 lineage | **F3** — Leros/TMS9900 lineage |
| Barrel, 4–8 threads | **F4** — J4/Hive lineage | **F1** — Octavo/BRISKI/XMOS lineage |

## Open questions (owner decides; don't assume)
- None open right now.
- Settled in D-002: Q1 (barrels are ranked on N copies), Q3 (geometric mean), the benchmark
  variants, and assembly only.
- Settled in D-004: Q4. The UART is not scored for any design: a single-thread core's
  hardware UART cells don't count, and barrels count all N copies. This replaces D-002's
  Q2 rule (N−1 copies).

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
