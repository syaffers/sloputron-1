# sloputron-1 — an original 16-bit CPU for the iCE40HX1K (iCEstick)

Read this first. The repo is the single source of truth for the project. The claude.ai
project "iCE40HX1K 16-bit CPU" mirrors `docs/`. When you change a doc here, the mirror is
updated from a claude.ai session, so say in your summary which docs changed.

## Goal and figure of merit
Design an original 16-bit CPU that gets the most useful work per logic cell while fitting
entirely in an iCE40HX1K-TQ144.
- **Figure of merit:** benchmark iterations/s at measured Fmax ÷ logic cells used.
- **Secondary:** code size; program memory is ≤ 8 KB.
- **Benchmarks:** CRC-16, sort, 16×16 multiply, memcpy. Exact variants are still open
  (see "Open questions").

## Chip facts that drive every decision
- 1,280 logic cells (LUT4 + DFF + carry). Everything counts: CPU, I/O, debug. Leave ~5%
  free for routing.
- 16 × SB_RAM40_4K (256×16 natural). Each block has 1 read + 1 write port and a
  synchronous read. A 2-read-port register file = 2 blocks with duplicated writes.
- **No LUT RAM on iCE40.** Any state outside BRAM costs one cell per bit. Measured: 512 of
  J1a's 628 DFFs are its stacks, and the 4-thread J4a needs 3,494 cells. State belongs in
  BRAM.
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
docs/phase0/              baselines.md, bibliography.md, tricks.md, shortlist.md (decision D-001)
docs/decisions/           decision record index
baselines/                uniform harnesses for third-party cores + build.sh + results CSVs
scripts/pnr_sweep.py      multi-seed nextpnr sweep -> LC, BRAM, Fmax median/worst/best (JSON/CSV)
scripts/yosys_stats.py    supplementary LUT/DFF/CARRY breakdown from Yosys logs
scripts/fetch_*.sh        pinned toolchain and baseline sources (into tools/ and ext/, gitignored)
```

## Commands
```
scripts/fetch_toolchain.sh && scripts/fetch_baselines.sh
cd baselines && SEEDS=16 ./build.sh               # all baselines; or ./build.sh leros j1a ...
python3 scripts/pnr_sweep.py NAME netlist.json pins.pcf --seeds 16 --csv out.csv
```
`build.sh` appends to `baselines/baselines.csv`. Use a scratch copy, or set `CSV`, for trial runs.

## Status
- **Phase 0 (done):** literature survey, baselines (16 seeds), shortlist.
  - Best measured: Leros, 343 LC at 84 MHz.
  - J1a: 1013 LC at 79 MHz.
  - PicoRV32 small: does not fit.
  - See `docs/phase0/baselines.md`.
- **Phase 1 (next):** repo skeleton, Makefile, report script, CI, and blinky + UART echo on
  the board to prove the flow.
- **Phase 2:** primitive cost table plus bare datapath skeletons of the finalists. The first
  experiment is J1a with stacks in BRAM, to confirm the estimate of ~450–550 LC.
- **Phase 3:** an ISA, simulator and assembler per finalist; benchmark cycle counts; commit to
  one concept.

Shortlist (D-001), a 2×2 of thread organisation × operand model:

| | Stack (stacks in BRAM) | Register window / accumulator (RF in BRAM) |
|---|---|---|
| Single thread | **F2** — J1 lineage | **F3** — Leros/TMS9900 lineage |
| Barrel, 4–8 threads | **F4** — J4/Hive lineage | **F1** — Octavo/BRISKI/XMOS lineage |

## Open questions (owner decides; don't assume)
- **Q1:** for barrel designs, does throughput count N benchmark copies on N threads?
  Proposed: report both, rank on the aggregate.
- **Q2:** a software-UART thread's slot counts as overhead (benchmarks get N−1 threads).
- Benchmark variants: CRC-16 polynomial, sort algorithm and size, memcpy length, and whether
  the 16×16 multiply returns a 32-bit result.
- Is a C compiler ever a goal, or is assembly enough?

## Working on the board (local sessions)
The iCEstick is attached to the owner's machine; cloud sessions cannot reach it. Flash with
`iceprog <bitstream>.bin`. The UART is the FT2232H's second interface (e.g. `/dev/ttyUSB1` on
Linux). Keep I/O hardware minimal; a UART may end up as a software thread.
