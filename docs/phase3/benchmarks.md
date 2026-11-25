# Phase 3 — The D-002 benchmarks on F1 and F5

The four D-002 kernels (crc16, sort, mul16, memcpy), run on the two cores left after
[D-005](../decisions/D-005-f1-f5-benchmarks.md):
- **F1**, the barrel, with 4 and 8 threads;
- **F5**, the single thread, with one-cycle stalls and with forwarding.

Both cores run the same instruction set and the same programs.

OSS CAD Suite 2026-11-01 (Yosys 0.70+286, nextpnr 0.11.1-85-ga2c64799), `--freq 100`,
seeds 1..16, measured on linux-aarch64. Regenerate with `bench/run.py` (about 35 min on
3 cores), then `bench/score.py`. Raw numbers are in `bench/bench.csv` and `bench/score.csv`.

## Result (instruction set v3, with a carry flag)

| Core | Cells | Fmax median / worst (MHz) | crc16 | sort | mul16 | memcpy | **Geometric mean** |
|---|---:|---|---:|---:|---:|---:|---:|
| **F1, 4 threads** | 336 | 90.0 / 87.1 | 18,070 | 30,965 | 23,514 | 148,143 | **37,364** |
| F1, 8 threads | 349 | 90.0 / 86.6 | 17,397 | 29,812 | 22,639 | 142,644 | 35,974 |
| F5, stalls | 338 | 84.1 / 74.3 | 13,292 | 23,427 | 17,747 | 119,810 | 28,526 |
| F5, forwarding | 377 | 76.7 / 69.6 | 12,590 | 19,514 | 15,810 | 112,329 | 25,701 |

These are the figures behind D-006. The D-008 run re-measured F1 with 4 threads at 92.2 MHz
(38,295), the same cells and cycles. Only the placement changed (see "ISA 1.0" below).
`bench/bench.csv` and `bench/score.csv` now hold that row.

Each kernel column is iterations/s per 1000 cells: copies × Fmax median ÷ cycles ÷ cells. A
barrel runs N copies at once (D-004). Cells are the core in the standard skeleton harness
(D-005 decision 4), the same measurement as Phase 2.

- **F1 with 4 threads leads F5 by 1.31× on the geometric mean**, and by 1.24× (memcpy) to
  1.36× (crc16) per kernel. The carry flag narrowed the lead from 1.41× (v2, below) because
  it gave F5 back more clock speed than F1.
- **4 threads beat 8** by 4%. 8 threads cost 13 more cells and run the same clock.
- **Forwarding loses on every kernel.** 39 more cells and a 9% slower clock buy 2% (sort)
  to 14% (crc16) fewer cycles.
- **One program on its own runs 3× faster on F5** (crc16: 223 µs against 659 µs on F1
  with 4 threads). D-002 ranks on N copies, so this is information only.

Cycles (all copies) and instructions per copy:

| Kernel | Instructions per copy | F1, 4 threads | F1, 8 threads | F5, stalls | F5, forwarding |
|---|---:|---:|---:|---:|---:|
| crc16 | 14,818 | 59,274 | 118,546 | 18,721 | 16,149 |
| sort | 8,647 | 34,590 | 69,178 | 10,622 | 10,419 |
| mul16 | 11,387 | 45,550 | 91,098 | 14,022 | 12,860 |
| memcpy | 1,807 | 7,230 | 14,458 | 2,077 | 1,810 |

F1 issues one instruction every cycle, shared among its threads. F5 with stalls needs
1.15–1.26 cycles per instruction (taken skips, calls and stalls).

**Code size** (the secondary metric): crc16 34 words, sort 37, mul16 43, memcpy 24. That is
138 words (276 bytes) in total, including a 13-word start-up and finish in each kernel.

## The compare fix (v2 → v3)

The first run (v2) gave unsigned compares a skip that compared two registers through the
ALU's carry, all in one cycle. That carry chain then sat on both cores' longest path:
- **F1:** register → carry chain → skip decision → next PC → PC memory.
- **F5:** register → carry chain → skip decision → next fetch address → program ROM.

v3 replaces it with a **carry flag C**:
- `add` and `sub` set C;
- `cmp` is a `sub` that does not write its result;
- the skip tests C one instruction later.

In F1, each thread's C is stored as bit 11 of its PC entry, so it costs no flip-flops per
thread. In F5, C is one flip-flop. Sort pays one `cmp` per compare: 28% more instructions.
mul16 uses the carry of its `add` directly, so it costs nothing there.

| Core | v2: cells, Fmax | v2 geometric mean | v3: cells, Fmax | v3 geometric mean |
|---|---|---:|---|---:|
| F1, 4 threads | 330, 74.0 MHz | 33,264 | 336, 90.0 MHz | **37,364** (+12%) |
| F1, 8 threads | 337, 74.0 MHz | 32,610 | 349, 90.0 MHz | 35,974 (+10%) |
| F5, stalls | 336, 66.4 MHz | 23,566 | 338, 84.1 MHz | 28,526 (+21%) |
| F5, forwarding | 386, 63.2 MHz | 21,762 | 377, 76.7 MHz | 25,701 (+18%) |

Sort still loses a little on F1, where the extra `cmp` costs more than the clock gains
(33,186 → 30,965). Every other kernel gains on both cores. The v2 code and numbers are in
PR #10 (branch `phase3-bench`).

## Whole-system cells (reported, not scored)

N copies need N output regions, so F1's data memory grows to 256 × (N+1) words. The logic
that joins those blocks into one memory adds cells. The "fit" rows of `bench/bench.csv` hold
the whole system each configuration needs: a 1 KB ROM, the data RAM, 12-bit data
addresses, 16 seeds.

| System | Cells | BRAM | Fmax median | Geometric mean (per 1000 system cells) |
|---|---:|---:|---|---:|
| F1, 4 threads | 402 | 10 | 89.5 | 31,084 |
| F1, 8 threads | 484 | 14 | 88.5 | 25,505 |
| F5, stalls | 334 | 6 | 88.4 | 30,350 |
| F5, forwarding | 377 | 6 | 78.4 | 26,281 |

On system cells F1 with 4 threads and F5 are level (1.02×). That gap pays only for the
N-copy rule, so the score counts the core (D-005 decision 4, owner). All systems fit the
chip: at most 14 of 16 BRAMs and 484 of 1,280 cells.

## How it was built

- **Instruction set v3** (`bench/rtl/r_f1.sv` documents the encoding) is the Phase 2
  two-operand set plus:
  - the carry flag and `cmp`;
  - 8 skip conditions: always, zero, non-zero, negative, non-negative, C clear, C set, odd;
  - data addresses as wide as the data memory (12 bits here);
  - r15 holds the thread number from configuration, so each thread finds its own region.
- **Cores:** `bench/rtl/r_f1.sv` and `r_f5.sv` are the Phase 2 skeletons with those
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
  control.
- **Checks:**
  - A reference interpreter in `bench/kernels.py` runs every kernel and must reproduce
    D-002's check values: crc 0x2865; sort's min, max and weighted sum; the first product
    and the XOR of the 64 products; memcpy equality.
  - The testbench (`make sim`, units `r_f1` and `r_f5`) runs each kernel on the RTL and
    compares the whole data memory with the interpreter's (except the shared done word).
  - A pseudo-random hazard program, with different values in every thread, tests
    back-to-back dependencies, compares, carry-flag skips (including after a discarded
    instruction) and loads used at once.
  - 13 broken variants of the v3 cores all fail.

## ISA 1.0: the instruction set for F1 alone (D-008)

After D-006 the instruction set no longer had to suit F5. Three extensions were tried on
F1 with 4 threads, each in encoding space that v3 left unused:
- **B**, branch on C (`bcc`, `bcs`);
- **S**, carry shifts (`shl`/`shr` set C, and `rcl`/`rcr` shift it in);
- **O**, a 4-bit load/store offset.

They are switched on by `X` in `bench/rtl/r_f1.sv`, and `bench/kernels.py` writes each
kernel to use what X provides. Same toolchain, 16 seeds. The v3 core was re-measured in
the same run, and these rows replace its row in `bench/bench.csv`.

| Variant | Cells | Fmax median / worst | crc16 | sort | mul16 | memcpy | **Geometric mean** |
|---|---:|---|---:|---:|---:|---:|---:|
| v3 (0.3) | 336 | 92.2 / 87.7 | 18,520 | 31,736 | 24,100 | 151,831 | **38,295** |
| + B | 338 | 95.6 / 90.2 | 22,139 | 33,177 | 27,281 | 182,127 | 43,708 |
| + S | 350 | 89.5 / 86.3 | 20,024 | 29,571 | 30,015 | 141,474 | 39,821 |
| + B + S | 348 | 93.2 / 90.8 | 24,975 | 31,425 | 35,725 | 172,506 | 46,896 |
| **+ B + S + O = 1.0** | **354** | **95.4 / 91.8** | 25,134 | 35,442 | 36,577 | 173,604 | **48,768** |
| 1.0, unrolled kernels | 354 | 95.4 / 91.8 | 42,301 | 35,442 | 51,274 | 411,167 | 74,980 |

- **The unchanged v3 core measured 92.2 MHz this time,** against 90.0 MHz before. Only
  wire names changed, which moves the placement. So Fmax differences of about ±3% between
  these rows are noise. Work per clock per cell, which leaves Fmax out, is:
  - B: 1.10;
  - S: 1.07;
  - B + S: 1.21;
  - 1.0: **1.23** (all against v3).
- **B** saves one instruction per counted loop. Count up from −n: `add rN, 1` then `bcc`.
- **S** shortens crc16's bit loop. It also turns mul16 into a right-shifting multiply
  through the carry.
- **O** helps sort (the hole is always j + 1) and unrolled copies. On the board's 12-bit
  data addresses it costs 11 cells, not 6 (`fit_f1x7` in `bench/bench.csv`: 421, against
  410).

Cycles for all four copies (instructions per copy = cycles ÷ 4):

| Kernel | v3 | + B | + S | + B + S | 1.0 | 1.0 unrolled |
|---|---:|---:|---:|---:|---:|---:|
| crc16 | 59,274 | 51,086 | 51,082 | 42,894 | 42,894 | 25,486 |
| sort | 34,590 | 34,090 | 34,590 | 34,090 | 30,418 | 30,418 |
| mul16 | 45,550 | 41,458 | 34,078 | 29,986 | 29,474 | 21,026 |
| memcpy | 7,230 | 6,210 | 7,230 | 6,210 | 6,210 | 2,622 |

**Code size:**
- 1.0, rolled: crc16 31 words, sort 32, mul16 33, memcpy 23. That is 119 in all, against
  138 for v3.
- Unrolled: 222 words. The unrolled kernels are crc16's 8 bits, mul16's 16 bits and
  memcpy 8 words per pass; sort has no fixed-count inner loop.

The scored kernels stay rolled (D-008 decision 5).

**Checks:**
- Every variant's kernels match the reference interpreter and the D-002 check values.
- The hazard program draws extra cases for each extension.
- 9 mutants of the new logic were all caught: an inverted or always-taken branch, `rcl`/`rcr`
  ignoring C or reading another thread's C, the shift-out bit swapped, shifts leaving C,
  an offset ignored on a load or a store, and the offset read from the wrong field.
- `rtl/core/f1_core.sv` runs the same kernels with every extension (`make sim-f1_core`).

## Next
- **Decided:** [D-006](../decisions/D-006-commit-f1.md) commits to F1 with 4 threads.
- **Decided:** [D-008](../decisions/D-008-isa-1.0.md), ISA 1.0 for F1. Unrolled kernels are
  measured above and reported, not scored.
