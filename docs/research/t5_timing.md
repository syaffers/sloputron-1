# T5 — Does nextpnr's clock predict the chip?

**Status:** first analysis done (2026-11-27), from data already in the repo. The designed
experiment is not yet run. Decision: D-010.

**Toolchain:** OSS CAD Suite 2026-11-01 (Yosys 0.70+286, nextpnr-ice40 0.11.1-85-ga2c64799),
linux-aarch64. One iCEstick, at room temperature.

## The data we have
There are 74 board builds in `docs/phase3/board_sweep.csv` (ISA 0.3 and 1.0) and
`docs/phase4/board_sweep.csv` (step 2b). `scripts/board_sweep.py` makes one build per clock
setting, because the PLL setting is part of the design. So each row is a different placement,
tested at one clock only:
- nextpnr's figure for each build is recorded;
- whether that build passed the stress test at its clock is recorded;
- the build's own limit, the clock at which it would start to fail, is **not** recorded.

## Finding 1 — the board's clock figure is often not the CPU's
nextpnr reports the slowest path in the whole design. Of the build folders still in
`build/board_sweep/`, 34 can be matched to a row in the CSVs (same seed, clock and nextpnr
figure). Those are all 23 Phase 4 builds, plus 11 Phase 3 ISA 1.0 builds at 108–129 MHz.
Their slowest paths:

| slowest path | Phase 4 | Phase 3, ISA 1.0 | nextpnr figure |
|---|---:|---:|---|
| starts in the CPU (a register read), ends at `pcm`, `y3`, the LEDs or the UART transmit register | 16 | 4 | 87.9–103.4 MHz |
| **inside the UART receiver's bit counter** (`u_rx.count`) | 7 | 7 | 75.3–89.9 MHz |

In those 14 builds, the reported clock says nothing about the CPU. They include:
- all three Phase 3 builds at 123 MHz (75.3, 77.8 and 79.7 MHz), which are the "77.8 MHz
  build ran at 123 MHz" example in `threads.md`;
- at 129 MHz, two builds whose slowest path had the same nextpnr figure (89.9 MHz). One
  passed and one failed. Those builds passed, but the stress test checks the CPU's
answers. It only weakly checks the receiver: it sends one byte at a time, and the reply comes
whatever byte arrives.

**Consequence.** Comparing board results against the board's nextpnr figure mixes two
circuits. The core's own score (`bench/run.py core`) has no UART, so it is not affected.

## Finding 2 — the figure does not separate passes from failures
Ratio = the clock the build was run at ÷ nextpnr's figure for that build:

| design | builds | highest ratio that passed | ratios that failed | lowest failing clock |
|---|---:|---:|---|---:|
| Phase 3, ISA 0.3 | 26 | 1.54 | 1.41–1.56 | 117 MHz |
| Phase 3, ISA 1.0 | 25 | 1.63 | 1.43 | 129 MHz |
| Phase 4, step 2b | 23 | 1.50 | 1.50–1.59 | 138 MHz |

- The ranges overlap: builds failed at ratios lower than other builds passed at. So no
  single safety margin over nextpnr's figure predicts pass or fail.
- One sign that placement matters more than the figure: Phase 3 ISA 0.3, seed 3, failed at
  117, passed at 120, then failed at 123 and 126. Each of those clocks is a different
  placement.
- In the band where passes and failures overlap, nextpnr's figure ranks them only weakly:
  - ISA 0.3, 117–123 MHz, 7 builds: area under the ROC curve 0.79 (1.0 would be a perfect
    ranking, 0.5 chance);
  - ISA 1.0 at 129 MHz, 3 builds: 0.25.

  These samples are tiny, and they still include the UART-receiver figures from finding 1.

**What can be said now:** no build failed below 1.41× its nextpnr figure, and none passed
above 1.63×. Whether nextpnr *ranks* builds correctly cannot be
answered from these data, because no build's own limit was measured.

## The designed experiment (next)
1. **One placement, many clocks.** Keep the placement fixed and change only the PLL setting,
   so that each build's own failing clock is measured: 114 to 150 MHz in 2 MHz steps.
   - The PLL setting is a few configuration bits in the bitstream. The plan is to patch them
     in the `.asc` file (Project IceStorm documents these bits), so nothing else changes.
   - Feasibility is to be checked first. Rebuilding at another clock does not keep the
     placement: between the 126 and 132 MHz builds of seed 1, about two thirds of the `.asc`
     file's 10,459 lines differ.
2. **The CPU's figure, apart from the UART's.** For each build, record the slowest path that
   starts and ends in the CPU, as well as the overall figure.
3. **16 placements** (seeds 1–16) of the step 2b design, each run to its own limit. Then:
   - test whether nextpnr's rank matches the measured rank (Spearman's ρ, with its
     confidence interval);
   - repeat each limit at least 3 times, to see how much one board's limit moves between
     runs.
4. **Temperature,** only if it can be controlled. Otherwise record the room temperature.

**What would be new.** A calibrated margin for iCE40 + nextpnr: how much faster than nextpnr's
figure a given build really runs, and how much that varies, measured per build rather than
per clock setting.
