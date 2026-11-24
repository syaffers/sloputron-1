# D-005 — Narrow the shortlist to F1 and F5; memory rules for N-copy benchmarks

**Status:** accepted, 2026-11-24 (owner). **Amends:** D-001 (shortlist) and D-002
(benchmark data layout).

## Context
On the Phase 2 crc test (`docs/phase2/skeletons.md`), the two-operand register cores led:

| Runs/s per 1000 LC | |
|---|---:|
| F1 barrel registers | 498–508 k |
| F5 single-thread registers | 358 k |
| F3 accumulator | 289 k |
| F4 barrel stack | 193–196 k |
| F2 stack | 177 k |

Each extra finalist needs its own version of every benchmark in its own instruction set.

D-002 states that each kernel's data fits in one 256-word BRAM. That is wrong for memcpy:
one copy needs a 256-word source and a 256-word destination. Scoring barrels on N copies
(D-004) also multiplies every output buffer by N.

## Decisions
1. **Only F1 and F5 go on to the benchmarks.** F2, F3 and F4 are dropped:
   - The stack machines (F2, F4) do about half the work per cell of the register cores.
   - F3 is beaten by F5, a core from its own family.

   Their skeletons and measurements stay in the repo as the record.
2. **Data layout for N copies.**
   - Read-only inputs are shared by all threads.
   - Each thread gets its own output region. Sort works in place, so each thread gets its
     own copy of the input in that region. Preparing it is not timed (D-002).
   - Barrels may use more memory blocks than single-thread cores, because blocks are not
     scored. Each configuration must still fit the chip: 16 blocks in total, including the
     program and the core's own blocks.
3. **memcpy needs 512 words per copy** (256 source, 256 destination). D-002's "fits in one
   BRAM" applies to the other three kernels only.

## Consequences
- F1 and F5 share one instruction set, so each kernel is written once and runs on both.
- F1 with 8 threads needs about 9 data blocks for memcpy (1 shared source and 8
  destinations), on top of its 3 core blocks. That leaves 4 blocks (2 KB) of program
  space while memcpy runs.
- **Measured** (`docs/phase3/benchmarks.md`, 16 seeds, OSS CAD Suite 2026-11-01):
  - Geometric mean per 1000 core cells: F1 with 4 threads 33,264; with 8 threads 32,610;
    F5 with stalls 23,566. So F1 leads by 1.41×.
  - On whole-system cells (memory logic included) the lead is 1.10× with 4 threads, and
    F1 with 8 threads falls behind F5.
  - All systems fit: at most 14 BRAMs and 479 cells.
