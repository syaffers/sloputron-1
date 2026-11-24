# D-003 — F5: a single-thread core with F1's instructions, as a control

**Status:** accepted, 2026-11-24 (owner). **Amends:** D-001 (adds one measured variant; the
four finalists are unchanged). **Results:** `docs/phase2/skeletons.md`, section "F5".

## Context
On the Phase 2 crc test, the F1 skeleton (barrel, two-operand registers) did 1.7× the
work per cell of F3 (single thread, accumulator). F1 differs from F3 in two ways at once:
- it runs 4–8 threads;
- it uses two-operand instructions (`rd ← rd op rs`), so the crc needs 550 instructions
  against F3's 814.

The 2×2 in D-001 has no single-thread two-operand cell, so the skeletons could not show how
much of F1's lead comes from each.

## Options
1. **Leave it.** Credit F1's lead to F1 as a whole. This risks committing to a barrel when
   the instruction set did most of the work. A single-thread core is simpler to program and
   runs one program N times faster.
2. **Build F5.** Keep F1's instruction set, binary and register file in BRAM, and drop the
   threads. The difference between F1 and F5 is then threading alone.
3. **Three-operand registers (`rd ← rs1 op rs2`).** Not chosen. With 16 registers in a
   16-bit word, the three register fields leave 4 bits for the opcode. That is not enough
   for immediates or a usable instruction set. Dropping to 8 registers would make room,
   but in this code the destination is nearly always one of the sources anyway.

## Decision
Option 2. F5 is a control experiment, not a fifth finalist. It sits in F3's family:
F3's lineage includes the TMS9900, which is a two-operand machine. Whether F5 replaces
any finalist is for the owner to decide once the results are in.

F5 is built in two forms that differ only in how a register is read straight after the
instruction that writes it:
- **forwarding** (`FWD=1`): the result is passed straight to the next instruction;
- **stall** (`FWD=0`): the next instruction waits one cycle.

## Consequences
Measured with OSS CAD Suite 2026-11-01 over 16 seeds. The workload is the crc self-test
only, so the per-cell figures are indicative.
- F5 with stalls: 329 LC, 86.4 MHz, 358 k runs/s per 1000 LC.
- **The instruction set:** F5 does 1.24× F3's work per cell.
- **Threading, all N copies:** F1 does a further 1.42× F5 with 4 threads (1.39× with 8).
- How the UART is scored changed the threading figure. On N−1 copies, F1 was only
  1.06–1.22× F5. With F5's ~80-LC hardware UART counted (an estimate), F1 led by 1.3–1.5×.
  This was open question Q4. [D-004](D-004-uart-not-scored.md) settled it: the UART is not
  scored, so the 1.42× above applies.
- Forwarding does not pay: +39 LC and −10% clock speed buy 17% fewer cycles.
