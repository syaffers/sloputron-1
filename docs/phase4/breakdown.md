# Phase 4 — Where the cells go (steps 0 and 1)

**Measured 2026-11-27** on linux-aarch64 with OSS CAD Suite 2026-11-01: Yosys 0.70+286
(slang) and nextpnr-ice40 0.11.1-85-ga2c64799. The core is in the standard harness
(`bench/rtl/bench_top.sv`, score sizes) with the board's 1,024-clock start-up hold.
Tools: `bench/run.py core` (16 seeds) and `bench/ablate.py` (one seed; the cell count is
the same on every seed).

## Step 0 — The real core, scored

`f1_core` replaces its benchmark copy `r_f1` (X = 7) as the scored core (D-009, accepted).

| | Cells | Fmax median / worst (16 seeds) | Score |
|---|---:|---|---:|
| `r_f1` x7, the Phase 3 figure | 354 | 95.4 / 91.8 MHz | 48,768 |
| **`f1_core`, ISA 1.0** | **374** | **95.4 / 90.7 MHz** | **46,175** |
| `f1_core`, unrolled kernels (x15) | 374 | same build | 70,993 |

**Cycles.** The kernel cycles are exactly those of `r_f1` x7: crc16 42,894, sort 30,418,
mul16 29,474 and memcpy 6,210. They are counted from the clock on which the start-up hold
ends (`bench/sim/bench_tb.sv`). `make sim-f1_core` now runs the scored kernels (x7) as
well as the unrolled ones (x15).

**What the 20 extra cells are.**
- The start-up hold accounts for 19 of them (see the table below).
- The load strobe `dre` is not connected in the harness, so synthesis removes it, and the
  retirement port too.
- **Fmax is unchanged.**

The score drops 5.3%, which is all cells. The step 0 estimate was ~375 cells and ~46,000.

**The fit harness** (12-bit data addresses, the memory the kernels need) gives 454 cells
against 421 for `r_f1` x7, so +33 cells. The hold explains 19 of them. Yosys shows 11
more LUTs than in the score harness, and this was not traced further.

## Step 1 — Ablation: the core with one block removed

Each row rebuilds the core with one block removed or tied off. "Saves" is the drop in
nextpnr logic cells against the unchanged core, 374. An ablated core does not run the
ISA; it is only a way to measure the block. The blocks overlap: for example, the ALU
output multiplexer row includes the logic-op and shift rows. So the rows do not add up to
374.

| Rank | Block removed | Saves | LUT | Carry | FF | Share of 374 |
|---:|---|---:|---:|---:|---:|---:|
| 1 | **ALU output multiplexer**: y is always the sum. It includes the next two rows. | **102** | −103 | 0 | −1 | 27% |
| | of which, the logic ops (and, or, xor, pass) | 66 | −68 | 0 | 0 | 18% |
| | of which, the shifts and their carry | 27 | −28 | 0 | −1 | 7% |
| 2 | **Next-PC multiplexer and PC+2**: next PC is always PC+1 | **63** | −51 | −8 | −25 | 17% |
| | of which, PC+2 alone: a taken skip goes to PC+1 | 40 | −28 | −8 | −23 | 11% |
| 3 | **Operand multiplexer**: s is always rs | **49** | −49 | 0 | −3 | 13% |
| 4 | Write-back multiplexer: no loads | 20 | −20 | −4 | −2 | 5% |
| 5 | Start-up hold | 19 | −14 | −8 | −15 | 5% |
| 6 | Skip conditions: skip always | 11 | −12 | 0 | 0 | 3% |
| 7 | Load/store offset adder | 7 | −7 | −7 | 0 | 2% |
| 8 | Subtract, the operand inversion | 6 | −6 | 0 | 0 | 2% |
| 9 | Branch on C | 0 | −2 | 0 | 0 | 0% |
| 10 | Carry-flag rule | −4 | +4 | −1 | −2 | — |

The core has 304 LUTs, 48 carries and 123 flip-flops. The carry-flag row grows by 4 cells
when the rule is removed. That is a packing effect, and a reminder that one or two cells
of difference is noise.

**By module** (`read_slang --keep-hierarchy`, `synth_ice40 -noflatten`, information only):

| Module | LUTs | Carries |
|---|---:|---:|
| ALU (`f1_alu`) | 121 | 16 |
| skip conditions (`f1_cond`) | 11 | 0 |
| the rest of `f1_core` | 174 | 32 |

That is 40% of the LUTs in the ALU. The flip-flop counts are not comparable: with the
hierarchy kept, Yosys moves fewer registers into the BRAM outputs (202 flip-flops against
123).

**The flip-flops** (123): about 59 are the S1→S2 pipeline registers, 22 the S3 registers,
22 PC+1 and PC+2 in S0, 15 the start-up hold, and 8 the thread number in each stage.

## What it means for step 2

The stop-early rule (`plan.md`: no block above ~2% of the score) does not apply. Three
blocks each hold more than 10% of the cells. Re-ranked by this table (all savings are
estimates until built):

1. **The ALU result path (102 cells in play).** Today Yosys builds roughly an 8-way
   choice for every bit. Hand structure:
   - one LUT per bit makes and/or/xor/pass from (x, s, two op bits), which was plan
     step 2b;
   - a small choice per bit then picks sum, logic or shift.

   About 3 LUTs per bit, 48 in all, against ~103 now. That gives up to ~50 cells fewer
   (estimate). `shl` through the adder (plan step 2a) fits into the same rework.
2. **PC+2 (40 cells).** PC+2 costs an adder and two 11-bit pipeline registers (23
   flip-flops). Instead, the next PC could be PC+1 plus a carry-in of "skip taken",
   computed in S2. That saves the registers and an adder, an estimated 20–30 cells.
   - **Risk:** the 11-bit carry chain then follows the skip test, on the way into the
     `pcm` write.
   - It must be measured against the clock, with 32 seeds.
   - Plan step 2c had estimated up to ~11 cells; the table shows more.
3. **The operand multiplexer (49 cells).** It is a 4-way choice on 16 bits: rs, the
   sign-extended immediate, {imm, rd low} for `ldhi`, and PC+1 for `jal`. Two of the
   inputs are narrow or partly constant. Folding `ldhi` or the `jal` link elsewhere (the
   ALU logic LUT, or the write-back multiplexer) may save 10–20 cells (estimate).
4. **The start-up hold (19 cells)**, after measuring on the board how long the BRAMs need
   (plan step 2d).
5. **Small blocks** (skip conditions 11, offset 7, subtract 6): leave unless a rework
   above touches them. Removing the offset would be an ISA change; at 7 cells it is not
   worth one.

**Clock.** The single-seed Fmax figures of the ablated cores (89–102 MHz) are within
placement noise and are not used. Two hints are worth checking in step 3:
- without the operand multiplexer, 101.8 MHz;
- without branch on C, 101.0 MHz.
