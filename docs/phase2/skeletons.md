# Phase 2, item 3 — Bare datapath skeletons for F1–F4 (and the F5 control)

The four finalists from D-001, each built as the smallest core that still runs real code.
That means an ALU, operand storage, loads and stores, conditional branches, and call/return.
All four share the same ALU and the same harness, so the differences come from how each one
holds its operands and threads. Each one runs a crc16 test program in simulation.

A fifth skeleton, **F5**, was added afterwards as a control ([D-003](../decisions/D-003-f5-control.md)).
It runs F1's instructions on a single thread, to show how much of F1's lead comes from its
instruction set and how much from its threads. See [F5](#f5-threads-or-instructions).

OSS CAD Suite 2026-11-01 (Yosys 0.70+286, nextpnr 0.11.1-85-ga2c64799), `--freq 100`,
seeds 1..16, measured on linux-aarch64 (cells are identical on x86; see `docs/process.md`).
Regenerate with `skel/run.py`, which takes about 30 min on 3 cores (`skel/run.py f5` reruns
one design; the other rows are kept). Raw numbers are in
`skel/skel.csv`.

## What was built

| | F1 | F2 | F3 | F4 | F5 (control) |
|---|---|---|---|---|---|
| Organisation | barrel, 4 or 8 threads | single thread | single thread | barrel, 4 or 8 threads | single thread |
| Operands | 16 registers per thread, two-operand (`rd ← rd op rs`) | stack: T in FFs, N and R as `stack_bram` | accumulator A in FFs, 256 registers in BRAM | stack, every thread's T/N/R in BRAM | as F1: 16 registers in BRAM, two-operand, same binary |
| Per-thread state | PC and registers in BRAM | — | — | PC, T, stack pointers, both stacks in BRAM | — |
| Pipeline | 4 stages, one thread per stage | none: next PC and next T computed in the same cycle (J1 style) | 3 stages: fetch, register read, execute | 3 stages | 3 stages (decode/register read, execute, write-back on the falling edge); next fetch address computed in the same cycle, as in F2 |
| Hazards | none: a thread's next instruction starts after the previous one finishes | none | no forwarding (one-instruction rule after a register write); taken branches lose 2 cycles | none | in hardware. A register read straight after its write either is forwarded (`FWD=1`) or stalls 1 cycle (`FWD=0`). Taken skips and calls lose 1 cycle; jumps lose none |
| Source | `skel/rtl/skel_f1.sv` | `skel_f2.sv` | `skel_f3.sv` | `skel_f4.sv` | `skel_f5.sv` |

Shared by all four:
- **ALU** (`skel_alu.sv`), 8 operations: add, sub (one adder), and, or, xor, pass, shift
  left 1, shift right 1. There is no barrel shifter and no multiplier.
- **Branch conditions**: always, zero, non-zero, negative.
- **Harness** (`skel_top.sv`): a 4 KB program ROM (8 BRAMs, the same size as the J1a baseline
  harness), a 256-word data RAM (1 BRAM), and a 5-bit LED port at data address 0xFF. The
  ROM and RAM are filled with random words for synthesis, so nothing can be optimised
  away.

The instruction sets are **provisional**. They exist so the datapath has something real to
do. Phase 3 designs the real ones. F2 and F4 share one stack instruction set (J1-like). F1
and F3 have their own. Each file's header documents its encoding, and `skel/asm.py`
assembles them.

**Test** (`make sim`): each skeleton runs CRC-16/CCITT-FALSE over `"123456789"` through a
subroutine and must store `0x29B1`. Every barrel thread runs its own copy and all of them must
be right. Eight deliberately broken variants (a wrong ALU op, a missed stack write, an
inverted skip, a missing branch squash and so on) all fail the test.

The register cores (F1, F5) also run a **hazard test** (`prog_reg_hz.hex`). It is a fixed
pseudo-random sequence of 227 instructions, dense with back-to-back register dependencies,
loads used straight away, addresses changed right before a load or store, and skips. Every
result is folded into a checksum. A reference interpreter in `skel/asm.py` computes the
expected value, and F1 agrees with it. Ten broken variants of F5 (no forwarding on either
operand, no load stall, a stall that checks only one operand, a rising-edge write, and so
on) all fail.

## Results (16 seeds)

| Skeleton | Cells | BRAM | LUT4 | Carry | FF | Fmax median / worst (MHz) |
|---|---:|---:|---:|---:|---:|---|
| F1 barrel registers, 4 threads | 312 | 12 | 264 | 34 | 81 | 87.3 / 81.2 |
| F1 barrel registers, 8 threads | 320 | 12 | 267 | 35 | 85 | 87.7 / 79.9 |
| F2 stack | 359 | 11 | 317 | 32 | 72 | 82.9 / 78.2 |
| **F3 accumulator** | **292** | 10 | 245 | 24 | 76 | **95.9 / 90.3** |
| F4 barrel stack, 4 threads | 338 | 14 | 290 | 30 | 82 | 86.4 / 79.5 |
| F4 barrel stack, 8 threads | 345 | 14 | 292 | 31 | 85 | 86.8 / 84.0 |
| F5 registers, single thread, stalls | 329 | 11 | 288 | 24 | 72 | 86.4 / 79.2 |
| F5 registers, single thread, forwarding | 368 | 11 | 328 | 24 | 74 | 78.1 / 72.7 |
| *context: J1a with BRAM stacks* | *422* | *10* | | | | *87.0 / 82.1* |
| *context: Leros* | *343* | | | | | *84.1* |

Cells and BRAMs include the harness (its LED port is about 8 cells). The context rows use
their own Phase 0 harnesses (`docs/phase0/baselines.md`).

## Priced with the cost table

I priced each skeleton from `docs/phase2/primitives.md` before synthesizing it, then
compared the estimate with the measurement.

| Skeleton | Predicted | Measured | Under by |
|---|---:|---:|---:|
| F1 (4 threads) | ~258 | 312 | 21% |
| F2 | ~250 | 359 | 44% |
| F3 | ~225 | 292 | 30% |
| F4 (4 threads) | ~270 | 338 | 25% |
| F5, stalls | ~315 | 329 | 4% |
| F5, forwarding | ~340 | 368 | 8% |

The table got the **order** mostly right but every **total** too low, for two reasons:
- **The shared ALU is bigger than its parts.** The parts are an add/sub adder (31 LUTs),
  4 logic ops (16), 2 shifts and a 3-way combine. They should add up to about 95 LUTs, but
  the ALU synthesizes to **118 LUTs** on its own. It is the largest block in every
  skeleton, at a third or more of the cells (33% of F2, 40% of F3).
- **Chains of blocks lose the free register.** The table prices each block with its output
  registered, so its last LUT shares the register's cell. In a core, decode feeds a mux, the
  mux feeds the ALU, and the ALU feeds another mux. Only the last block in the chain gets
  the free register. F2 has the longest chains: instruction → decode → ALU → T-source mux →
  next T and the data-memory address, all in one cycle. That is why its estimate is the
  furthest off.

So the cost table prices single blocks well, but a whole core comes out about 25–45% higher.
Use that factor for whole-core estimates in Phase 3.

F5 was priced differently: as changes to the measured F1 (remove the threads, add the
hazard and fetch logic). That estimate was within 4–8%. **Pricing a design as a change to a
measured core is far more accurate than pricing it from scratch.**

## Work per cell on the test program (indicative only)

These figures use provisional instruction sets and hand-written code on a 9-byte input, not
the D-002 benchmarks. They show the shape of the trade-off, not the final ranking.

| Skeleton | Cycles per crc run (one copy) | Instructions per run | Runs/s (all copies) | Runs/s per 1000 cells |
|---|---:|---:|---:|---:|
| F1, 4 threads | 2,202 | 550 | 158.5 k | 508 k |
| F1, 8 threads | 4,402 | 550 | 159.4 k | 498 k |
| F2 | 1,303 | 1,302 | 63.6 k | 177 k |
| F3 | 1,138 | 814 (+324 branch bubbles) | 84.3 k | 289 k |
| F4, 4 threads | 5,209 | 1,302 | 66.4 k | 196 k |
| F4, 8 threads | 10,417 | 1,302 | 66.6 k | 193 k |
| F5, stalls | 734 | 550 (+41 skips, 18 calls, 123 stalls) | 117.8 k | 358 k |
| F5, forwarding | 611 | 550 (+41 skips, 18 calls) | 127.8 k | 347 k |

The UART is left out of the score for every design ([D-004](../decisions/D-004-uart-not-scored.md)),
so barrels count all N copies. An earlier version of this table also scored barrels on N−1
copies, under the D-002 rule that D-004 replaced.

How to read it:
- A barrel issues one instruction per cycle in total, shared round-robin. One copy runs N
  times slower, but N copies run at once. D-002 ranks on N copies.
- **F2 and F4 run the same program**, so they isolate the effect of threading. F4 costs
  14–21 cells *less* than F2 and runs at about the same clock, so the barrel's N copies
  cost nothing extra in cells.
- **F1 against F3** mixes threading with a different instruction set. Most of F1's lead
  comes from needing 550 instructions per run against F3's 814 and F2/F4's 1,302. Two
  register operands do in one instruction what the accumulator does in two or three.
- F3 loses 28% of its cycles to branch bubbles. Delay slots or branch prediction would
  recover some of that.

## F5: threads or instructions?

F5 runs exactly F1's binary on one thread. Comparing it with F3 and F1 splits F1's lead into
its two causes:

| Step | Work per cell | What changed |
|---|---:|---|
| F3 → F5 (stalls) | 289 k → 358 k, **1.24×** | accumulator → two-operand registers, both single-thread |
| F5 → F1 | 358 k → 508 k (4 threads), **1.42×**; 498 k (8), 1.39× | threads added, same instructions |

- **Both causes are real.** Two-operand instructions beat the accumulator by 1.24× and the
  single-thread stack machine (F2) by 2×. Threads add a further 1.4×.
- **The UART is not scored** ([D-004](../decisions/D-004-uart-not-scored.md)). Before that
  decision the split depended on it. If a single-thread core's ~80-LC hardware UART had
  counted, F1 would lead F5 by 1.3–1.5×. If barrels had been scored on N−1 copies, the
  lead would be only 1.06–1.22×.
- **One program runs 3× faster on F5.** One crc copy takes 8.5 µs on F5 against 25 µs on
  F1 with 4 threads. D-002 ranks on N copies, so this is information only. It matters for
  anything that cannot be split into independent copies.
- **Forwarding does not pay.** It costs 39 LC (+12%) and 10% of the clock for 17% fewer
  cycles, which leaves work per cell slightly lower (347 k against 358 k). The stall
  version is better. This crc code has 123 back-to-back dependencies in 550 instructions.
  Sort and memcpy load more often, and every load followed straight away by its use stalls
  in both versions, so F5's cycle counts there are still unknown.
- **F5's clock is limited by its fetch.** As in F2, the next fetch address is computed in
  the same cycle. The longest path runs from the register file, through the skip test
  (is the register zero?), to the decision to discard the next instruction, then to the
  ROM address: 7 logic levels, 8 with forwarding. A registered fetch would shorten it but
  costs a cycle on every jump. That has not been measured yet.

## What this says for the design

1. **Threads are almost free when their state is in BRAM.** Going from 4 to 8 threads costs
   8 cells in F1 and 7 in F4, against J4a's 3,417 cells with thread state in FFs. All of
   that cost is pipeline registers (thread number, PC+1, decoded fields), not per-thread
   state.
2. **The ALU is the largest block and sets Fmax in three of the four skeletons.** The
   critical paths (seed 1):
   - F2: instruction → decode → ALU → next T → data-memory address;
   - F4: instruction → decode → ALU;
   - F3: register → ALU → A;
   - F1 with 8 threads: operand → ALU → result. With 4 threads, F1's longest path is the
     skip test → next-PC adder → PC BRAM, which is just as long.
   - F5: register → skip test → next fetch address → ROM (see above).

   Shrinking the ALU (a hand-mapped version should reach about 96 LUTs) helps all four
   finalists equally.
3. **The barrels are not faster yet.** F4 decodes and executes in the same stage, and F1's
   execute stage holds the operand mux and the ALU. A barrel can add a pipeline stage
   without slowing any thread, as long as N ≥ stages, so splitting decode from execute is
   the obvious next step for F1/F4. That has not been measured yet.
4. **The single-thread stack machine (F2) is the largest of the four finalists, not the smallest.** Its
   T-source mux, the J1-style speculative next-T address and two `stack_bram` heads cost
   more than F3's accumulator, and it runs the slowest clock. The J1a-with-BRAM-stacks
   baseline (422 cells) has a larger ALU (barrel shifts, compares), which explains the 63
   cells between it and F2.
5. **F3 is the smallest and fastest single block** (292 cells, 95.9 MHz). It lacks the
   instructions-per-run advantage of two register operands, though.
6. **BRAM limits program size.** 16 blocks hold 8 KB in total, so every block a core uses
   comes out of program space. With one data block, the most program each design can hold
   is: F3 7 KB (14 blocks), F2 6.5 KB, F5 6.5 KB, F1 6 KB, F4 5 KB.

## For Phase 3
- **F1 looks strongest** on this first test: 1.7× F3's runs per 1000 cells. F5 splits that
  lead: the instruction set gives 1.24× and threading a further 1.42×.
- **The two-operand register model wins over both stacks and the accumulator**, single
  thread or barrel. The open choice is F1 (barrel) against F5 (single thread). On crc, F1
  leads by 1.4×. The other three benchmarks will decide, especially sort and memcpy,
  where F5 stalls on every load that is used straight away.
- **The ALU is common to all four, so optimise it once.** Reasonable targets are 96 LUTs
  and a shorter carry path.
- **Measure an extra pipeline stage in F1/F4** (decode separate from execute) to see how
  much Fmax a barrel can buy.
- **Use the cost table with a 1.25–1.45 multiplier** for whole-core estimates.

## Files
- `skel/rtl/`: `skel_top.sv` (harness), `skel_alu.sv`, and `skel_f1.sv` … `skel_f5.sv`. F2
  also uses `rtl/lib/stack_bram.sv`.
- `skel/sim/skel_tb.sv`: the crc16 test, plus the hazard test for F1 and F5 (`make sim`).
- `skel/asm.py`: assembler for the three provisional instruction sets, the test programs, and
  a reference interpreter for the register instruction set.
- `skel/run.py`: synthesis, then a 16-seed nextpnr sweep → `skel/skel.csv`.
