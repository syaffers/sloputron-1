# D-006 — Commit to F1, the barrel register machine, with 4 threads

**Status:** accepted, 2026-11-24 (owner). **Closes:** the concept choice for Phase 3
(D-001, narrowed by D-005).

## Context
The four D-002 kernels ran on the two cores left after D-005, both on the same two-operand
register instruction set (v3, with a carry flag). Results are in
`docs/phase3/benchmarks.md`: OSS CAD Suite 2026-11-01, 16 seeds. Each figure is
iterations/s per 1000 core cells, as the geometric mean over the four kernels.

| Core | Cells | Fmax median / worst | Geometric mean |
|---|---:|---|---:|
| **F1, 4 threads** | 336 | 90.0 / 87.1 MHz | **37,364** |
| F1, 8 threads | 349 | 90.0 / 86.6 MHz | 35,974 |
| F5, single thread, stalls | 338 | 84.1 / 74.3 MHz | 28,526 |
| F5, single thread, forwarding | 377 | 76.7 / 69.6 MHz | 25,701 |

F1 with 4 threads leads on every kernel, by 1.24× (memcpy) to 1.36× (crc16), and by 1.31×
overall. Of the 4- and 8-thread versions, 4 wins: 8 threads add 13 cells and run no faster.

## Decision
The CPU is **F1 with 4 threads**:
- a 4-thread round-robin barrel;
- each thread's PC (and carry flag) and its 16 registers live in BRAM;
- two-operand register instructions;
- a 4-stage pipeline with no forwarding, interlocks or branch penalty.

## What the owner accepted with it
- **One program runs at a quarter of the clock.** A single program gets one cycle in four.
  F5 ran a single crc16 3× faster than one F1 thread (223 µs against 659 µs). D-002 ranks
  on N copies, so this does not count against F1. It matters for any job that cannot be
  split across threads.
- **The lead rests on scoring the core's cells.** Counting the whole system, including
  the extra memory logic for 4 separate output buffers, F1 and F5 are level (1.02×).
  D-005 decision 4 scores the core.
- **The instruction set is still provisional (v3).** Phase 3 defines the real one for F1
  alone. F1 no longer has to share it with a single-thread core.

## Consequences
- F2, F3, F4 and F5 stop here. Their skeletons, benchmark cores and measurements stay in
  the repo as the record (`skel/`, `bench/`).
- **Remaining Phase 3 work, now for F1 only:**
  - the ISA spec (TOML), from which the assembler rules, decode tables and docs are
    generated;
  - a C99 cycle-counting ISS, which replaces `bench/kernels.py` as the reference;
  - Verilator lockstep against the ISS, and formal checks;
  - icebram program loading.
- **The core moves into `rtl/`** as a board design. From then on every hardware change
  adds `results.csv` rows, and Fmax is confirmed on the board with a PLL sweep.
- **The UART is still open as an engineering choice.** It is not scored (D-004), but the
  chip needs one. The options are a hardware UART (~80 LC, estimated) or a software UART
  in one of the 4 threads (trick T10).
- **Ideas to measure on F1:** unrolled inner loops (code size against speed), and the
  thread-count and stage options that the barrel allows.
