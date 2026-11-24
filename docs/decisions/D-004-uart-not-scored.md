# D-004 — The UART is left out of the score

**Status:** accepted, 2026-11-24 (owner). **Resolves:** Q4 (raised by D-003).
**Supersedes:** D-002 decision 1 (Q2: "the software UART costs one slot").

## Context
D-002 scored a barrel on N−1 copies when one thread runs the UART in software. That slot
was meant to stand in for the ~80 cells a hardware UART costs. D-002 did not say what a
single-thread core pays for its UART. That core cannot run one in software, so it needs
the hardware UART.

The F5 control (D-003) showed this choice decides F1 against F5:
- with the UART's ~80 cells charged to F5, F1 leads by 1.3–1.5×;
- with nothing charged to F5 and N−1 copies for F1, F1 leads by only 1.06–1.22×.

## Decision
The UART is not part of the score for any design.
- **Single-thread cores:** the hardware UART's cells are not counted.
- **Barrels:** scored on all N copies. If a hardware UART is free for one design, a barrel
  could use one too and keep every thread, so N−1 would charge the barrel for something
  it does not need to pay.

A design may still choose a software UART thread. That is an engineering choice measured
on its own, not a scoring rule. The chip-level budget is unchanged: whatever UART ships
must fit in the 1,280 cells (CLAUDE.md, "Everything counts").

## Consequences
- D-002 decision 0 (barrels scored on N copies) now applies without the N−1 exception.
  The single-copy figure is still reported for information.
- On the crc skeleton test, F1 leads F5 by **1.42×** with 4 threads and **1.39×** with 8.
  F5 leads F3 by 1.24× (`docs/phase2/skeletons.md`). These are indicative: one kernel,
  provisional instruction sets.
- The ranking no longer rewards a software UART thread (trick T10). T10 still matters for
  cutting the cells the real chip uses.
