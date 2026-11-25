# Decision records

One short record per architectural choice: context, options, measured numbers behind the
choice, decision, and consequences. New records get the next number.

| ID | Date | Title | Status |
|---|---|---|---|
| D-001 | 2026-11-22 | [Phase 0 shortlist: 2×2 of {single, barrel} × {BRAM stack, BRAM register window}](../phase0/shortlist.md) | closed by D-006 (F1 chosen; Q1, Q2 resolved by D-002) |
| D-002 | 2026-11-23 | [Figure-of-merit rules and benchmark definitions](D-002-benchmarks.md) | accepted (decision 1 superseded by D-004) |
| D-003 | 2026-11-24 | [F5: a single-thread core with F1's instructions, as a control](D-003-f5-control.md) | accepted |
| D-004 | 2026-11-24 | [The UART is left out of the score (barrels: N copies)](D-004-uart-not-scored.md) | accepted; supersedes D-002 decision 1 |
| D-005 | 2026-11-24 | [Shortlist narrowed to F1 and F5; memory rules for N-copy benchmarks](D-005-f1-f5-benchmarks.md) | accepted |
| D-006 | 2026-11-24 | [Commit to F1, the barrel register machine, with 4 threads](D-006-commit-f1.md) | accepted |
| D-007 | 2026-11-24 | [A dedicated hardware UART, memory-mapped beside the barrel](D-007-hardware-uart.md) | accepted |
| D-008 | 2026-11-25 | [Instruction set 1.0 for F1: branch on carry, carry shifts, load/store offset](D-008-isa-1.0.md) | accepted (owner may veto) |
