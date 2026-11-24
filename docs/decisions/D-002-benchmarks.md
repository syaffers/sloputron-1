# D-002 — Figure-of-merit rules and benchmark definitions

**Status:** accepted, 2026-11-23 (owner). **Resolves:** Q1 and Q2 of D-001, the
benchmark-variant question, the C-compiler question, and Q3. No questions left open.
**Amended 2026-11-24 by [D-004](D-004-uart-not-scored.md):** the UART is left out of the
score, so decision 1 (N−1 copies) no longer applies. Barrels are scored on all N copies.

## Decisions
0. **Q1: barrels are scored on N copies.** A barrel design with N threads runs one
   independent copy of each kernel on every benchmark thread, and the score counts the
   total iterations/s. (Under Q2 this was N−1 copies when one thread is the UART. D-004
   removed that exception.) A single-thread design runs one copy, so its score is the same under either rule. The
   single-copy figure is reported too, but only for information. The owner chose this
   knowing it flatters barrels, because N fully independent copies are the best case for
   them.
1. ~~**Q2: the software UART costs one slot.**~~ *Superseded by D-004.* On a barrel design (F1/F4) with a UART thread,
   benchmarks get N−1 threads. That slot pays for the ~80 cells a hardware UART would cost.
2. **Assembly only.** No C compiler is planned. The ISA is shaped only by cells × speed ×
   code size. It does not need a frame pointer, a general register set, or anything else a
   compiler back end would want.
3. **Benchmark set.** These are the four kernels below. Each one is a single run over
   fixed data. One run is one *iteration* in the figure of merit. Inputs are small enough
   that each kernel's data fits in one 256×16 BRAM.

### Shared input generator
16-bit Galois LFSR. Mask `0xB400`, seed `0xACE1`. Each step is
`lsb = x & 1; x >>= 1; if lsb: x ^= 0xB400`, and the output is the new `x`. Every kernel
restarts the generator from the seed. Inputs are generated ahead of time and are not timed.

| Kernel | Definition | Input | Check value |
|---|---|---|---|
| **crc16** | CRC-16/CCITT-FALSE: poly `0x1021`, init `0xFFFF`, no reflection, no final XOR. Bitwise, MSB first, no lookup table. | 256 bytes: the low byte of LFSR outputs 1..256 (`70 38 9C 4E …`). How bytes pack into words is up to the ISA. | `0x2865`. The self-test `"123456789"` gives `0x29B1`. |
| **sort** | Insertion sort, ascending, unsigned 16-bit, in place. | 64 words: LFSR outputs 1..64 (`E270 7138 389C 1C4E …`) | min `0x0E27`, max `0xFBB0`, Σ(i+1)·s[i] mod 2¹⁶ = `0xE0FB` (i from 0) |
| **mul16** | 64 unsigned 16×16 multiplies. Each 32-bit product is stored. Done in software unless a hardware multiplier pays for its cells. | 64 pairs (a, b), each made from two consecutive LFSR outputs: a = output 2k+1, b = output 2k+2 | first product `0x6424F880`, XOR of all 64 products = `0x755EA6D0` |
| **memcpy** | Copy 256 words. Source and destination are word-aligned and do not overlap. | any data | destination equals source |

The check values come from a Python reference model (2026-11-23). A real harness will
replace that model with the C99 ISS in Phase 3.

4. **Q3: the four kernels combine by geometric mean.** The figure of merit is
   iterations/s at Fmax ÷ LC, measured per kernel. The overall figure is the geometric mean
   of the four. That way no single kernel dominates, and a 2× gain on any one kernel counts
   the same. Code size, the secondary metric, is reported per kernel and as a total.

## Consequences
- Phase 3's ISS and RTL testbenches check the values above. The Phase 2 skeletons do not
  depend on this record.
- mul16 is the test of whether a hardware multiplier is worth its cells. Shift-add in
  software is the baseline, and a multiply step instruction or a full multiplier has to
  beat it on the figure of merit.
- F1–F4 all stay in the running. Phase 3 ranks them on the N-copy geometric mean.
