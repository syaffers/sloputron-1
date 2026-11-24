# Phase 3 — The D-002 benchmarks on F1 and F5

The four D-002 kernels (crc16, sort, mul16, memcpy), run on the two cores left after
[D-005](../decisions/D-005-f1-f5-benchmarks.md):
- **F1**, the barrel, with 4 and 8 threads;
- **F5**, the single thread, with one-cycle stalls and with forwarding.

Both cores run the same instruction set and the same programs.

OSS CAD Suite 2026-11-01 (Yosys 0.70+286, nextpnr 0.11.1-85-ga2c64799), `--freq 100`,
seeds 1..16, measured on linux-aarch64. Regenerate with `bench/run.py` (about 35 min on
3 cores), then `bench/score.py`. Raw numbers are in `bench/bench.csv` and `bench/score.csv`.

## Result

| Core | Cells | Fmax median / worst (MHz) | crc16 | sort | mul16 | memcpy | **Geometric mean** |
|---|---:|---|---:|---:|---:|---:|---:|
| **F1, 4 threads** | 330 | 74.0 / 70.2 | 15,122 | 33,186 | 19,679 | 123,978 | **33,264** |
| F1, 8 threads | 337 | 74.0 / 71.3 | 14,825 | 32,533 | 19,291 | 121,551 | 32,610 |
| F5, stalls | 336 | 66.4 / 59.7 | 10,559 | 22,651 | 13,548 | 95,175 | 23,566 |
| F5, forwarding | 386 | 63.2 / 59.1 | 10,139 | 19,208 | 12,732 | 90,459 | 21,762 |

Each kernel column is iterations/s per 1000 cells: copies × Fmax median ÷ cycles ÷ cells. A
barrel runs N copies at once (D-004). Cells are the core in the standard skeleton harness,
the same measurement as Phase 2.

- **F1 leads F5 by 1.41× on the geometric mean.** Per kernel the lead is 1.43–1.47×, except
  memcpy at 1.30×. This matches the 1.42× from the Phase 2 crc test.
- **4 and 8 threads score the same.** 8 threads cost 7 more cells and run the same clock.
- **Forwarding loses again**, now on all four kernels: 50 more cells and a slower clock buy
  2% (sort) to 14% (crc16) fewer cycles.

Cycles (all copies) and instructions per copy:

| Kernel | Instructions per copy | F1, 4 threads | F1, 8 threads | F5, stalls | F5, forwarding |
|---|---:|---:|---:|---:|---:|
| crc16 | 14,818 | 59,274 | 118,546 | 18,721 | 16,149 |
| sort | 6,752 | 27,010 | 54,018 | 8,727 | 8,524 |
| mul16 | 11,387 | 45,550 | 91,098 | 14,591 | 12,860 |
| memcpy | 1,807 | 7,230 | 14,458 | 2,077 | 1,810 |

F1 issues one instruction every cycle, shared among its threads. F5 needs 1.15–1.29 cycles
per instruction (taken skips, calls and stalls).

**Code size** (the secondary metric): crc16 34 words, sort 34, mul16 43, memcpy 24. That is
135 words (270 bytes) in total, including a 13-word start-up and finish in each kernel.

## Two things that qualify the result

### 1. The new compare-and-skip costs both cores 15–23% of their clock

Sort and the multiply's carry need an unsigned compare. The instruction set gained a skip
that compares two registers through the ALU's carry. That carry now sits on each core's
longest path:
- **F1:** register file → operand mux → 16-bit carry chain → skip decision → next PC →
  PC memory. 87 → 74 MHz.
- **F5:** register file → carry chain → skip decision → discard the next instruction → next
  fetch address → program ROM. 86 → 66 MHz.

F5 loses more because its skip also steers the fetch in the same cycle. Some of F1's lead
(how much is not measured) therefore comes from this one instruction. A cheaper design
would take the compare off the critical path:
- **a carry flag:** a compare or an add writes a 1-bit flag, and the skip tests the flag a
  cycle later;
- **or a late PC select:** write the PC memory on the falling edge.

The flag costs one extra instruction per compare in sort's inner loop. That is the next
experiment.

### 2. Counting the whole system's cells shrinks the gap

N copies need N output regions. F1's data memory grows to 256 × (N+1) words, and the logic
that joins those blocks into one memory is cells. The "fit" rows of `bench/bench.csv` hold
the whole system each configuration needs: a 1 KB ROM, the data RAM, 12-bit data addresses,
16 seeds.

| System | Cells | BRAM | Fmax median | Geometric mean (per 1000 system cells) |
|---|---:|---:|---|---:|
| F1, 4 threads | 392 | 10 | 70.7 | 26,784 |
| F1, 8 threads | 479 | 14 | 71.5 | 22,171 |
| F5, stalls | 335 | 6 | 68.5 | 24,362 |
| F5, forwarding | 372 | 6 | 63.0 | 22,517 |

On system cells, F1 with 4 threads leads F5 by only 1.10×, and F1 with 8 threads falls
behind F5. The extra cells pay only for the N-copy benchmark rule. A real program running
on F1 would not need 8 separate 256-word output buffers. The table above therefore scores
the core, as Phase 2 did. All four systems fit the chip: at most 14 of 16 BRAMs and 479 of
1,280 cells.

## How it was built

- **Instruction set v2** (`bench/rtl/r_f1.sv` documents the encoding) is the Phase 2
  two-operand set with three changes:
  - the skip compares two registers, with 8 conditions: always, zero, non-zero, negative,
    non-negative, unsigned <, unsigned ≥, odd;
  - data addresses are as wide as the data memory (12 bits here);
  - r15 holds the thread number from configuration, so each thread finds its own region.
- **Cores:** `bench/rtl/r_f1.sv` and `r_f5.sv` are the Phase 2 skeletons with these
  changes. `r_alu.sv` is the skeleton ALU plus a carry out and the 8 conditions. F1
  computes PC+2 a stage early, so a taken skip only selects it.
- **Harness:** `bench/rtl/bench_top.sv` is the skeleton harness with the ROM and RAM sizes
  as parameters.
- **Memory layout (D-005):** the shared read-only input is at 0x000–0x0FF. Thread t owns
  0x100·(t+1) onwards. A store to 0xFFF signals that a thread has finished.
  - crc16 stores one byte per word, in the high half.
  - sort's 64 words are copied into each thread's region before the run (not timed).
- **Programs** (`bench/kernels.py`): straightforward loops, not unrolled. Each load is
  scheduled at least two instructions before its use, so F5 never stalls on a load.
  Loop overhead dominates: crc16 spends 7 instructions per bit, of which 3 are loop
  control. Unrolling would help both cores about equally.
- **Checks:**
  - A reference interpreter in `bench/kernels.py` runs every kernel and must reproduce
    D-002's check values: crc 0x2865; sort's min, max and weighted sum; the first product
    and the XOR of the 64 products; memcpy equality.
  - The testbench (`make sim`, units `r_f1` and `r_f5`) runs each kernel on the RTL and
    compares the whole 4096-word data memory with the interpreter's.
  - A pseudo-random hazard program tests the pipeline: back-to-back dependencies, compare
    skips right after a write, loads used at once.
  - Ten broken variants of the cores all fail at least one test.

## Next
1. **Take the compare off the critical path** in both cores (a carry flag, or a late PC
   select). Then re-measure. This affects F5 more than F1, so it could narrow the 1.41×.
2. **Unroll the inner loops** (crc16's bit loop, mul16's bit loop). This is code-size
   against speed, which D-002 tracks as the secondary metric.
3. **Commit to a concept** once item 1 is in. On these numbers it would be F1 with 4
   threads.
