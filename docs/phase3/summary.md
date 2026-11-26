# Phase 3 — Summary (done, 2026-11-24 to 2026-11-26)

**Goal of the phase:**
1. Run the D-002 benchmarks on the finalists.
2. Choose the CPU.
3. Define its instruction set.
4. Get it running on the board, and verify it.

All four are done. The details are in the documents linked below. This page records the
outcome, the numbers to beat, what we learned, and what carries over to Phase 4
(`docs/phase4/plan.md`).

## Decisions

| Record | Decision |
|---|---|
| [D-005](../decisions/D-005-f1-f5-benchmarks.md) | Narrow the shortlist to F1 (barrel) and F5 (single thread). They share one ISA. Score the core's cells only. |
| [D-006](../decisions/D-006-commit-f1.md) | **The CPU is F1 with 4 threads.** It led F5 by 1.31× on the score. |
| [D-007](../decisions/D-007-hardware-uart.md) | The UART is hardware, memory-mapped at 0xFFC–0xFFF beside the LEDs. |
| [D-008](../decisions/D-008-isa-1.0.md) | **ISA 1.0** = 0.3 + branch on C + carry shifts + a 4-bit load/store offset: 1.23× the work per clock per cell. There is no 12-bit PC, multiply step or shift-by-N. |

## Where it ended

**The core, as scored** (standard harness, `bench/`, OSS CAD Suite 2026-11-01, 16 seeds).
Score = iterations/s per 1000 cells, geometric mean over the four D-002 kernels:

| | Cells | Fmax median / worst | Score |
|---|---:|---|---:|
| ISA 0.3 (v3), as chosen in D-006 | 336 | 92.2 / 87.7 MHz | 38,295 |
| **ISA 1.0 (D-008), the baseline for Phase 4** | **354** | **95.4 / 91.8 MHz** | **48,768** |

The 0.3 row is its re-measurement in the D-008 run, so the two rows compare like for like.
D-006 itself quoted 37,364 at 90.0 MHz; the cells and cycles were the same, only the
placement differed.

Per kernel, ISA 1.0 needs these cycles for its 4 copies:
- crc16: 42,894;
- sort: 30,418;
- mul16: 29,474;
- memcpy: 6,210.

The code is 119 words for the four kernels.

**The whole CPU on the iCEstick** (design `sloputron`, `docs/phase3/board.md`). It has the
core, a 4 KB program ROM, 1K words of RAM, a hardware UART and the LEDs.
- 482 of 1,280 cells, 15 of 16 BRAMs.
- 91.2 MHz median, 87.5 MHz worst, over 16 seeds.
- **On the board:**
  - it prints its banner, with a crc that one thread computes and another prints;
  - it echoes 4,096 bytes with no errors;
  - with the PLL, every build runs the self-checking stress program correctly up to
    126 MHz (ISA 1.0, 3 seeds).

**Verification** (`docs/phase3/verification.md`):
- `isa/isa.toml` is the single source for:
  - the written spec;
  - the decode constants of the RTL and of the C ISS;
  - the assembler.
- **The C99 ISS** counts clocks exactly.
- **The lockstep test** checks every instruction the RTL finishes against the ISS: the
  demo, the stress test and 8 random ROMs, about 2M instructions, with 0 mismatches. It
  caught all 9 bugs planted in the core.
- **Each kernel** is checked against a reference interpreter and the D-002 check values.
- **`make sim`** runs all of it. CI runs it on every push.

## What we learned

1. **Placement noise is about ±3% of Fmax.** Renaming wires moved the unchanged core
   from 90.0 to 92.2 MHz. For changes smaller than that, compare the work per clock per
   cell, which leaves Fmax out, and treat Fmax differences under ~3% as equal.
2. **A taken skip is free.** The skipped word is never fetched, so it costs no cycle.
   Branch instructions therefore help loops (2 instructions to close a loop instead of 3)
   but not if/else code (sort gained 1.4%). Count cycles before adding instructions.
3. **The carry chain sets the clock.**
   - v2 compared through the ALU's carry in one cycle, which cost 15–23% of Fmax. The
     carry flag (v3) fixed that.
   - The critical path still runs from a register read, through the 16-bit adder and the
     carry flag, into the PC/flag BRAM write. Phase 4's clock work starts there.
4. **iCE40 block RAMs read wrong just after configuration.** Simulation cannot show it.
   The core waits 1,024 clocks before doing anything (19 cells). How long the RAMs really
   need was never measured.
5. **nextpnr is conservative on this board by at least 25%.** Builds that nextpnr put at
   75–98 MHz ran correctly up to 126 MHz. Near the limit, whether a build passes depends
   on its placement, not on nextpnr's figure. The score keeps using nextpnr's median
   (D-002), because it holds for every chip and temperature.
6. **Random tests need their coverage measured.** Random programs fell into 2-word loops
   and "passed" while testing almost nothing. Forcing all control flow forward gave
   1,100–1,250 distinct instruction words per program. Three of the planted bugs were
   found only that way.
7. **The scored core is a copy.** The score comes from `bench/rtl/r_f1.sv` (X = 7). The
   board runs `rtl/core/f1_core.sv`, which has the same datapath plus the start-up hold,
   the load strobe and the retirement port. Phase 4 step 0 closes this gap.
8. **Process:** never change the working tree (no `git stash`, no checkout) while a
   background build reads it. Doing so once gave two invalid board-sweep rows, which were
   thrown away and re-run.

## Carried over

- **To Phase 4** (`docs/phase4/plan.md`):
  - score the real core;
  - find where its cells go;
  - shrink the largest blocks;
  - shorten the critical path.
- **Deferred:**
  - **SymbiYosys formal checks.** The retirement port is the interface they would use.
    They are worth doing if Phase 4 changes the pipeline.
  - **Program loading with `icebram`,** without rebuilding the design.
  - **A faster default clock for the board.** It runs at 12 MHz, although the sweep shows
    large margins.
  - **Measuring how long the block RAMs need after configuration,** which may let the
    start-up hold shrink.
