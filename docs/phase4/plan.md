# Phase 4 — Plan: optimise cells and clock

**Status:** steps 0 and 1 measured, 2026-11-27 (`breakdown.md`). The real core is 374 cells,
95.4 MHz, score 46,175; D-009 makes it the baseline (accepted). The table there re-orders
step 2. Steps 2a and 2b (the ALU result path and its operand, `alu.md`): 301 cells,
101.8 MHz, score 61,215. Every expected gain below is an estimate and is labelled as one.

## Goal
Raise the figure of merit (D-002): iterations/s per 1000 core cells, as the geometric mean
over the four kernels. Do it by changing how the core is built, not what it does.
- **The ISA stays at 1.0.** Any ISA change needs its own measurement and decision record,
  as D-008 had.
- **Starting point** (Phase 3, `docs/phase3/summary.md`): **354 cells, 95.4 MHz median,
  score 48,768**, for the benchmark copy of the core. Step 0 replaces it with the real
  core's figure.

The two levers multiply: 10 cells fewer is about +3%, and 10% more clock is +10%.

## Rules for every experiment
- **Measure.** Build each change as a parameter or variant beside the current core:
  - cells from nextpnr;
  - Fmax as the median and worst of 16 seeds;
  - cycles from the kernel simulations.
- **Remember the noise.** Fmax moves about ±3% with placement alone (Phase 3, lesson 1).
  - Judge changes that save cells by the **work per clock per cell**.
  - Judge changes that aim at the clock with **32 seeds**, and count a gain under ~3% as
    none.
- **Correctness first.** A change is adopted only if `make sim` passes: the kernels
  against their reference images, the hazard test, and the lockstep against the C ISS
  with random ROMs.
- **Finish properly.** An adopted change goes into `rtl/core/f1_core.sv` and gets:
  - `make report` rows;
  - the banner and echo test on the board;
  - a short decision record if it changes the architecture.

## Step 0 — Score the real core
The score so far comes from `bench/rtl/r_f1.sv` with X = 7. The board runs
`rtl/core/f1_core.sv`, which adds three things:
- the start-up hold (about 19 cells);
- the load strobe;
- the retirement port, which synthesis removes.

**Do:**
1. Add `f1_core` to the scored variants (`bench_top` CORE = 0, with its real 1,024-clock
   hold).
2. Count kernel cycles from the first instruction, not from power-up. The hold happens once
   at start-up and is not per-iteration work.
3. Make the real core the baseline. Keep `r_f1` only as the record of Phase 3.

**Expected** (estimate): about 375 cells, so a score near 46,000, lower than 48,768. The
hold is part of the CPU, so it should count.

**Owner decision:** re-baseline on the real core. Accepted as D-009, 2026-11-27.

## Step 1 — Find where the cells go
**Two measurements:**
- **Hierarchy.** Synthesise with the module structure kept, and count LUTs, carry cells and
  flip-flops per block.
- **Ablation.** Build the core once per block with that block removed or tied off, and
  take the change in cells from nextpnr. This catches packing effects that a per-module
  count misses.

**The blocks:**
- ALU: the adder, the logic operations, the shifts, the output multiplexer;
- operand source multiplexer (rs, immediate, ldhi, PC + 1);
- decode;
- skip condition;
- next-PC logic: PC + 1, PC + 2, the 4-way choice;
- carry-flag logic;
- the load/store offset adder;
- the start-up hold;
- the thread counter and pipeline registers.

**Deliverable:** `docs/phase4/breakdown.md`, the blocks ranked by cells. It decides the
order of step 2.

## Step 2 — Shrink the largest blocks
These are hypotheses to test in the order step 1 gives, each as a variant of `f1_core`.

| | Idea | Why it might work | Estimate |
|---|---|---|---|
| a | **`shl` and `rcl` through the adder**: x + x + carry-in | x + x is a left shift. Its carry out is the old bit 15, which is exactly the C that `shl` sets, and a carry-in of C gives `rcl`. The left shifts then need no output multiplexer input of their own, but the adder's second operand needs x as a new input, so part of the saving goes back. | 0–15 cells fewer |
| b | **Logic operations in one LUT per bit** | and, or, xor and pass are four functions of (x, s). One 4-input LUT per bit, with two op bits, can make all four. Yosys may not find this by itself. | 10–20 cells fewer |
| c | **A cheaper next-PC path** | PC + 1 and PC + 2 are two 11-bit adders, computed early for speed. One adder plus a carry-in may do, if the clock allows. | up to ~11 cells fewer |
| d | **A shorter start-up hold** | Measure on the board how long the block RAMs actually need after configuration: try shorter holds, with many power cycles each. Then shorten the counter, or reuse PLL lock time. | up to ~10 cells fewer |
| e | **Recheck the load/store offset** | D-008 called it marginal: +11 cells at the board's 12-bit addresses. Re-measure it on the real core. Removing it would change the ISA, so it needs a decision record. | ±11 cells |

**Adopt** a change when it improves the work per clock per cell and does not lower Fmax
beyond the noise.

## Step 3 — Shorten the critical path
The slowest path today runs from a register-file read, through the 16-bit adder and the
carry-flag logic, into the PC/flag BRAM write (`pcm`). The board build of 2026-11-25
confirms it ends at `pcm` WDATA.

| | Idea | What it changes | Estimate |
|---|---|---|---|
| a | **Keep C in 4 flip-flops, written one stage later** | The carry out is registered at the end of S2 and written into the thread's flag in S3. The thread's next instruction first needs C in its own S1, 2 clocks later, so there is no hazard. `pcm` then holds only the PC, and the adder no longer feeds a BRAM write. | +5–15% Fmax for about 6–8 cells |
| b | **The next limit, probably the skip test** | After (a), the slowest path is likely rd == 0 → skip → next PC → `pcm`. Options: resolve skips one stage later, which needs a 5th pipeline stage, so 5 or more threads; or cheaper zero-detect logic. | depends on (a) |
| c | **8 threads and a 5th stage** | Only if (a) and (b) are not enough. Phase 3 measured 8 threads at +13 cells and no faster, but that was without splitting any path. One program would run at an eighth of the clock instead of a quarter. The score counts all copies, so this does not lower it. | unknown |

**Owner decisions:**
- **(a) keeps 4 bits of state in flip-flops,** a small exception to "state belongs in
  BRAM";
- **(c) halves the speed of a single program.**

Both would get decision records.

## Alongside (small, any time)
- **Program loading with `icebram`:** swap the ROM contents in a built bitstream, in about
  3 s instead of a 40 s rebuild. It speeds up every board test above.
- **Board clock:** run the board design from the PLL by default, for example at 90 MHz,
  within nextpnr's figure.
- **Formal checks (SymbiYosys):** worth adding if step 3 changes the pipeline. Two
  properties:
  - one thread can never change another's state;
  - exactly one instruction finishes per clock.

## Order, size and exit
| Step | Rough size (estimate) | Gives |
|---|---|---|
| 0 | half a day | the honest baseline |
| 1 | half a day | the ranked target list |
| 2 | 1–2 days | fewer cells |
| 3 | 1–2 days | a faster clock |

**Phase 4 ends when:**
- every idea in steps 2 and 3 has been measured and adopted or rejected;
- the adopted ones are in `f1_core`;
- the board passes its tests, including a PLL sweep;
- `docs/phase4/summary.md` records the new figure against 48,768 (and against the step 0
  baseline).

**Stop early** if step 1 shows no block worth more than about 2% of the score.
