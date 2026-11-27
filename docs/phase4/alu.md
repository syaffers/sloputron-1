# Phase 4 steps 2a and 2b — The ALU result path and its operand

**Measured 2026-11-27** on linux-aarch64 with OSS CAD Suite 2026-11-01: Yosys 0.70+286
(slang) and nextpnr-ice40 0.11.1-85-ga2c64799. Standard harness, score sizes, the board's
1,024-clock start-up hold (`bench/run.py core`, `bench/score.py`).

## Result

| `f1_core` | Cells | Fmax median / worst | Score |
|---|---:|---|---:|
| before (D-009 baseline) | 374 | 95.4 / 90.7 MHz (16 seeds) | 46,175 |
| step 2a: the ALU result path | 312 | 93.5 / 91.4 MHz (16 seeds) | 54,208 |
| the same build, 32 seeds | 312 | 92.3 / 86.7 MHz | — |
| **step 2b: the operand** | **301** | **101.8 / 97.4 MHz (16 seeds)** | **61,215** |
| the same build, 32 seeds | 301 | 101.8 / 95.2 MHz | — |
| step 2b, unrolled kernels (x15) | 301 | same build | 94,116 |

Steps 2a and 2b together: 73 cells fewer (−20%), the clock 6.7% higher, and the score
+32.6% against the baseline (+25.5% against the Phase 3 figure, 48,768). In the fit
harness the core went 454 → 378 → 367 cells. The kernel cycles do not change.

## Step 2a — The ALU result path

- **Cells:** 62 fewer (−17%).
- **Clock:** 2% lower at the median. See "Critical path after step 2a" below; step 2b
  fixes it.
- **Score:** +17.4% against the baseline, and +11.2% against the Phase 3 figure (48,768).
- **Cycles:** the same in every kernel.
- **Checks:** `make sim` passes, including the lockstep check against the C ISS. That is
  1.99 million instructions with 0 mismatches, over random ROMs that use the reserved shift
  encodings as well.

### What changed

**Before.** Yosys built the result as an 8-way choice for each of the 16 bits: sum, and,
or, xor, pass, shift left, shift right. The breakdown (`breakdown.md`) measured it at
102 cells.

**After.** Three logic cells per bit, two of which were there already:

1. **The adder cell.** On iCE40, each bit of an adder is one logic cell: a 4-input LUT that
   makes the sum, and the carry logic beside it. The sum uses 3 of the LUT's inputs (x, s
   and the carry in). The fourth input was unused. It now takes a mode bit `m`, and the
   LUT outputs either the sum (`m` = 0) or the operand s (`m` = 1). The choice is free.
2. **The logic LUT** (one per bit) takes that output `a` and x. A 2-bit code `k` picks
   `a`, `x & a`, `x | a` or `x ^ a`. With `a` = s, that gives and, or and xor; with
   `a` = the sum, it passes the sum through.
3. **The shift LUT** (one per bit) gives `x >> 1` for shr, and otherwise the logic LUT's
   output.

**Shift left uses the adder:** rd + rd = rd << 1. For that, the second register port
reads rd instead of rs on a `shl` (`rcl` adds C as the carry in). The carry out is then the
old bit 15, which is what C must get. The decode in S1 grows by a few LUTs for this.

| op | m | k | invert s | carry in | result |
|---|---:|---:|---:|---|---|
| add | 0 | 0 | 0 | 0 | x + s, C = carry out |
| sub | 0 | 0 | 1 | 1 | x − s, C = no borrow |
| shl, rcl | 0 | 0 | 0 | 0, or C for rcl | rd + rd, C = old bit 15 |
| and / or / xor | 1 | 1 / 2 / 3 | 0 | — | x op s |
| pass (`li`, `mov`, `ldhi`, `jal` link) | 1 | 0 | 0 | — | s |
| shr, rcr | — | — | — | 0, or C for rcr | {carry in, x >> 1}, C = old bit 0 |

**Why the LUTs are instantiated.** Yosys builds the adder from its own cells, and it does
not put other logic into the sum's LUT. So the adder bit (`f1_addcell`: one `SB_LUT4` and
one `SB_CARRY`) is written out by hand, and nextpnr packs each pair into one cell. The two
LUTs after it are written out too (`f1_lut4`). When Yosys mapped them from behavioural
code, it used 18 cells more (330 against 312, one seed). Under Verilator the same truth
tables run as plain logic, so the simulations test them.

### Critical path after step 2a

The slowest path moved. Before, it ran from a register read through the adder to the
carry flag and into the `pcm` write. In the median seed it now runs:

> register read (rfa) → **3 LUTs of the operand multiplexer** → carry chain from bit 5 →
> sum of bit 15 → logic LUT → shift LUT, which feeds the result register y3. 10.85 ns.

The two LUTs after the sum replace a deeper choice, so they are not new delay. The 3 LUT
levels of the operand multiplexer in front of the adder are what to shorten. That is step
2's next item, and it also saves cells:
- in S1, put sext(imm), {imm, 0} for `ldhi` and PC+1 for `jal` into one 16-bit register;
- in S2, the operand is then a 2:1 choice (rs or that register) with the subtract
  inversion, one LUT level;
- `ldhi`'s low byte uses `x | a` with a zero operand, through a separate `k` for each byte.

The estimate was 10–15 cells fewer and two LUT levels off this path.

## Step 2b — The operand

**Before.** The operand s was a 4-way choice in S2, made separately for each of 16 bits:
rs, the sign-extended immediate, {imm, rd's low byte} for `ldhi`, or PC+1 for `jal`. That
is 3 LUT levels, and it sat right in front of the adder.

**After.** Three of the four inputs are constants that the instruction already knows in S1.
So S1 now puts the right one into a single 16-bit register, `im2`:

| instruction | `im2` |
|---|---|
| ALU immediate form | sext(imm) |
| `ldhi` | {imm, 0} |
| `jal` | PC+1, the return address |
| `jmp`, `bcc`, `bcs` | the jump target in bits 10..0, so the old 11-bit target register goes |

In S2 the operand is then just "rs or `im2`", and the subtract inversion fits into the same
LUT. That is one LUT per bit and one level.

**`ldhi`** wrote {imm, rd's low byte}, which needed rd as a fourth input. Now its operand is
{imm, 0}, and the ALU's logic LUT gets its code `k` per byte. The high byte passes the
operand (k = 0); the low byte computes rd | 0 = rd (k = 2).

**Result:** 312 → 301 cells (the estimate was 10–15 fewer), and the median clock is
93.5 → 101.8 MHz. Flip-flops go up from 124 to 136 (the 16-bit `im2` against the 11-bit
target register it replaces, plus the per-byte `k`), but each flip-flop shares a cell with
the LUT that feeds it.

**Checks:** `make sim lint` pass; the lockstep check against the C ISS has 0 mismatches.

### Critical path after step 2b

In the median seed it now runs:

> register read (rfa) → **skip test** (is the 16-bit value zero: 4 LUT levels) →
> next-PC choice (2 levels) → `pcm` write. 9.45 ns.

The skip test is plan step 3's second item. The adder is off the critical path.
