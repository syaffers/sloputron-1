# Phase 2, item 2 — Primitive cost table

What each building block costs on the iCE40HX1K, measured the same way for every block so
the finalists' datapaths can be priced before any are built. Regenerate with
`prims/run.py` (≈10 min on 4 cores). Raw numbers are in `prims/prims.csv`.

OSS CAD Suite 2026-11-01 (Yosys 0.70+286, nextpnr 0.11.1-85-ga2c64799), `--freq 100`,
seeds 1..16, measured on linux-aarch64. 1,280 cells is the whole chip.

## How it is measured
Each block sits in the same harness: input pin → shift chain (one FF per input bit) →
**block** → output register → XOR → output pin. The same harness with a plain wire in
place of the block gives the overhead, and **cells added** is the difference.

The output register matters. An iCE40 logic cell has a LUT4, a carry and a flip-flop
together. If a block's last LUT feeds a register directly, that LUT shares the register's
cell for free. So "cells added" is a block's cost when its result is registered, which is
the usual case at the end of a pipeline stage. **LUT4** is the block's logic on its own,
which is closer to the cost when its output feeds more logic, such as the ALU result mux.

Fmax is the clock through the block, from the input chain to the output register. The bare
harness runs above 400 MHz, so it never limits the figure.

## Results

| Block | Cells added (registered) | LUT4 | Carry | FF | BRAM | Fmax median / worst (MHz) |
|---|---:|---:|---:|---:|---:|---|
| **Arithmetic** | | | | | | |
| 16-bit add | 1 | 16 | 15 | | | 253.7 / 253.7 |
| 16-bit add/sub, as written (`s ? a-b : a+b`) | 46 | 60 | 30 | | | 169.5 / 146.2 |
| 16-bit add/sub, one adder (`a + (b^s) + s`) | **17** | 31 | 15 | | | 194.4 / 185.8 |
| 13-bit increment (PC+1) | 1 | 13 | 11 | | | 280.7 / 280.7 |
| 16-bit equal | 15 | 15 | | | | 258.1 / 239.7 |
| 16-bit unsigned less-than | 17 | 17 | 16 | | | 194.6 / 181.5 |
| 16-bit and/or/xor/not (4 ops) | 0 | 16 | | | | 422.6 / 400.2 |
| **Multiplexers, 16 bits wide** | | | | | | |
| 2:1 | 1 | 16 | | | | 438.2 / 400.2 |
| 3:1 | 17 | 32 | | | | 318.9 / 267.5 |
| 4:1 | 33 | 48 | | | | 292.1 / 263.1 |
| 5:1 | 32 | 48 | | | | 289.2 / 258.3 |
| 6:1 | 65 | 80 | | | | 227.8 / 212.3 |
| 7:1 | 65 | 80 | | | | 231.2 / 199.5 |
| 8:1 | 81 | 96 | | | | 213.9 / 196.8 |
| 4:1, one-hot select | 33 | 48 | | | | 286.3 / 254.2 |
| 8:1, one-hot select | 64 | 80 | | | | 260.2 / 254.2 |
| **Shifters, 16 bits** | | | | | | |
| shift by 1: left, right, arithmetic right | 14 | 30 | | | | 348.4 / 300.1 |
| barrel, left only (0–15) | 48 | 55 | | | | 200.6 / 192.3 |
| barrel, 4 ops (shl/shr/sar/rotl), as written | 220 | 233 | 3 | | | 131.2 / 124.3 |
| barrel, 4 ops, one funnel shifter | **134** | 149 | | | | 132.7 / 125.3 |
| **Register files, 16 bits** | | | | | | |
| 256 entries, 1 read port, BRAM | 2 | 1 | | | 1 | 257.2 / 233.5 |
| 256 entries, 2 read ports, BRAM | 1 | 1 | | | 2 | 253.6 / 243.6 |
| 8 entries, 2 read ports, flip-flops | 296 | 200 | | 128 | | 202.6 / 181.5 |
| 16 entries, 2 read ports, flip-flops | 658 | 434 | | 256 | | 181.4 / 164.3 |
| **Barrel thread PCs, 13 bits (PC+1 or branch)** | | | | | | |
| 4 threads, flip-flops | 122 | 69 | 11 | 54 | | 117.7 / 108.5 |
| 4 threads, BRAM | **30** | 26 | 11 | 2 | 1 | 146.4 / 141.9 |
| 8 threads, flip-flops | 220 | 114 | 12 | 107 | | 91.7 / 85.7 |
| 8 threads, BRAM | **33** | 27 | 12 | 3 | 1 | 146.4 / 137.0 |
| **Decode: random table, opcode → 16 control bits** | | | | | | |
| 4-bit opcode, LUTs | 2 | 17 | | | | 331.1 / 294.9 |
| 5-bit opcode, LUTs | 49 | 64 | | | | 247.6 / 227.1 |
| 6-bit opcode, LUTs | 144 | 159 | | | | 189.6 / 176.4 |
| 8-bit opcode, LUTs | 556 | 571 | | | | 122.5 / 113.0 |
| 8-bit opcode, BRAM ROM (+1 cycle latency) | 1 | 0 | | | 1 | 279.9 / 257.2 |

The two "one adder" and "funnel" rows are formally proven equivalent to their "as written"
rows (Yosys SAT miter over all inputs). A deliberately broken add/sub fails the same proof.

## What this says for the design
1. **Registers belong right after the last LUT level.** A result that goes straight into a
   register costs almost nothing for an add, an increment, logic ops or a 2:1 mux. The same
   adder feeding a result mux costs its full 16 cells.
2. **Multiplexer cost per bit: 2:1 = 1 LUT, 4:1 = 3, 8:1 = 6.** Selection costs as much as
   arithmetic, so the number of sources into the ALU result and the operand inputs is a
   first-order cost. One-hot selects save nothing.
3. **Write add/sub as one adder.** That saves 29 cells and is faster.
4. **A full barrel shifter costs 134 cells, about 10% of the chip.** Shift-by-one costs 14.
   Multi-bit shifts should be a loop of single shifts, or a small fixed set (1, 4, 8), unless
   the benchmarks show the shifter pays. crc16 is bitwise and needs only shift-by-one.
5. **Register files must be in BRAM.** A BRAM register file costs 1–2 cells. Eight
   flip-flop registers with two read ports cost 296 cells, 23% of the chip.
6. **Barrel thread state belongs in BRAM.** Eight thread PCs cost 33 cells in BRAM against
   220 in flip-flops, and run at 146 MHz instead of 92.
7. **Decode in BRAM wins for a dense or irregular opcode space beyond about 5 bits.** Random
   tables are the worst case; a structured encoding costs much less. The BRAM's extra cycle
   is free in a barrel (F1/F4), but costs a pipeline stage in a single-thread design.

## Synthesis gotchas found here
- **`(* no_rw_check *)` on BRAM memories.** Without it, Yosys guarantees "a read during a
  write to the same address returns the old value" by building extra logic: about 57 cells
  per read port. A CPU usually doesn't care what that read returns. The Phase 0 baseline
  harness had the same issue: J1a's harness RAM cost 115 cells this way (1013 → 898 LC with
  the attribute). The baselines have been re-measured with the fix (`docs/phase0/baselines.md`).
- **Yosys moves small flip-flop register files into BRAM by itself** when the read output is
  registered (`rf16x16_2r_ff` came out as 2 BRAMs). `(* ram_style = "logic" *)` forces the
  flip-flop version for comparison.
- **Write-it-plainly is not free.** `s ? a-b : a+b` builds two adders and four shift
  operators build four shifters. Hand-shaped versions are smaller and provably the same.
