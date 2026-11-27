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
- The ISA is one TOML spec (`isa/isa.toml`). It generates the SV decode package, the C
  decode header and the docs, and it drives the assembler (customasm dropped, D-008).
- The C99 cycle-counting ISS (`iss/`) checks the RTL in Verilator lockstep through the
  RVFI-style retirement port of `f1_core` (`docs/phase3/verification.md`).
- Planned: SymbiYosys formal checks; icebram + iceprog for program loading.
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
isa/                      the ISA: isa.toml (single source), isa.py/asm.py (assembler), gen.py (spec doc + isa_pkg.sv + iss/isa_gen.h), iss.py (Python ISS of the board), test_isa.py
iss/                      C99 ISS (iss.c, slp-iss CLI in main.c), DPI glue for lockstep (dpi.c), random_rom.py, test_iss.py
programs/                 assembly programs: demo.s (banner + echo), stress.s (clock-sweep test); make assembles them to build/programs/*.hex
docs/isa/isa.md           the written ISA spec (generated; edit isa/isa.toml, then `make isa`)
sim/                      self-checking Verilator testbenches (print PASS or $fatal); lockstep_tb.sv = CPU vs ISS
docs/process.md           results.csv protocol and CI rules
docs/phase0/              baselines.md, bibliography.md, tricks.md, shortlist.md (decision D-001)
docs/phase1/bringup.md    board bring-up steps and checklist
docs/phase2/              Phase 2 experiments (j1a_bram.md, primitives.md, skeletons.md)
docs/phase3/              Phase 3: summary.md (outcome, lessons), benchmarks.md (D-002 kernels, ISA 1.0 study), board.md (the CPU on the iCEstick, PLL sweep), board_sweep.csv, verification.md (C ISS, lockstep)
docs/phase4/              Phase 4: plan.md (optimise cells and clock), breakdown.md (step 0 score of the real core, step 1 ablation), alu.md (step 2a)
docs/research/threads.md  open research threads (T1-T7), breadth-first; owner picks
docs/decisions/           decision record index
baselines/                uniform harnesses for third-party cores + build.sh + results CSVs
prims/                    primitive cost table: prims.sv, run.py (harness + 16-seed sweep), prims.csv
bench/                    benchmark cores: Phase 3 copies (F1, F5; ISA v3 + D-008 extensions X) and, from Phase 4, f1_core itself (variant `core`): rtl/, sim/, kernels.py (assembler, kernels, reference interpreter), run.py (16-seed sweep -> bench.csv), score.py (figure of merit -> score.csv), ablate.py (cells per block -> ablate.csv)
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
make isa                          # after editing isa/isa.toml: regenerate docs/isa/isa.md, rtl/core/isa_pkg.sv, iss/isa_gen.h
make iss                          # C ISS -> build/iss/slp-iss (make sim runs iss-test and sim-lockstep)
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
- **Phase 3 (done, 2026-11-26):** benchmarks, the choice of CPU, its ISA, the board and
  verification. Summary and lessons: `docs/phase3/summary.md`.
  - D-005 narrowed the shortlist to F1 and F5; **D-006 chose F1 with 4 threads** (1.31×
    F5). D-007: hardware UART at 0xFFC–0xFFF.
  - **ISA 1.0 (D-008)** = 0.3 + `bcc`/`bcs` + carry shifts (`rcl`/`rcr`) + a 4-bit
    load/store offset: 1.23× the work per clock per cell. `isa/isa.toml` generates the
    spec, `rtl/core/isa_pkg.sv` and `iss/isa_gen.h`, and drives `isa/asm.py`.
  - **Scored core** (benchmark copy `bench/rtl/r_f1.sv`, X = 7): 354 LC, 95.4 / 91.8 MHz,
    **score 48,768** (iterations/s per 1000 core cells, geometric mean, 16 seeds).
  - **On the board** (`sloputron`, `docs/phase3/board.md`):
    - 482 LC, 15 BRAMs, 91.2 / 87.5 MHz (16 seeds);
    - the banner and a 4,096-byte echo pass;
    - with the PLL, every build passes the stress test up to 126 MHz, so nextpnr is
      conservative by at least 25%;
    - the core holds for 1,024 clocks at start-up, because iCE40 BRAMs read wrong just
      after configuration.
  - **Verification** (`docs/phase3/verification.md`):
    - the C99 ISS (`iss/`) counts clocks exactly;
    - `make sim-lockstep` checks every RTL instruction against it: demo, stress and 8
      random ROMs, 0 mismatches;
    - all 9 planted bugs were caught.
- **Phase 4 (in progress): optimise cells and clock** (`docs/phase4/plan.md`). The ISA
  stays at 1.0.
  0. Done: the real core (`f1_core`, with its start-up hold) is 374 LC, 95.4 / 90.7 MHz,
     score 46,175 (`bench/run.py core`). D-009: it is the Phase 4 baseline.
  1. Done: `docs/phase4/breakdown.md` (`bench/ablate.py`). ALU result multiplexer 102 LC,
     next-PC + PC+2 63, operand multiplexer 49, write-back multiplexer 20, hold 19.
  2. Shrink the largest blocks. 2a done (`docs/phase4/alu.md`): the ALU result path mapped by
     hand (sum or s from the adder's own LUT, then a logic LUT and a shift LUT per bit; shl
     as rd + rd): **312 LC, 93.5 / 91.4 MHz, score 54,208**; board 411 LC, 90.6 / 84.9 MHz.
     Next: the operand multiplexer (now on the critical path), PC+2, start-up hold.
  3. Shorten the critical path (register read → adder → C → `pcm` write): keep C in 4
     flip-flops written a stage later; then the skip path; 8 threads only if needed.

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
