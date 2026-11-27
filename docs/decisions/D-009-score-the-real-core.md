# D-009 — Score the CPU core itself, not its benchmark copy

**Status:** accepted by the owner, 2026-11-27 (Phase 4 plan, step 0).
**Builds on:** D-002 (figure of merit), D-006 (F1, 4 threads) and D-008 (ISA 1.0).

## Context
The Phase 3 score, 48,768, was measured on `bench/rtl/r_f1.sv` with X = 7. That is the
benchmark copy of the core. The board runs `rtl/core/f1_core.sv`. Both have the same
datapath and decode and run the same kernels in the same cycles. `f1_core` also has:
- **the start-up hold:** iCE40 BRAMs read wrong for a short time after configuration, so
  the core writes nothing for 1,024 clocks;
- **a load strobe for the I/O,** which is not connected in the benchmark harness;
- **the retirement port,** which synthesis removes.

Phase 4 changes the core itself, so its score must come from the core itself.

## Options
1. **Keep scoring `r_f1`,** and port every Phase 4 change to both files. This means two
   copies to keep in step, and a score for a core that is not the one on the board.
2. **Score `f1_core`,** with the board's 1,024-clock hold, in the same standard harness.
   Count kernel cycles from the end of the hold: it happens once at power-up and is not
   per-iteration work. `r_f1` stays as the record of Phase 3.

## Measurements
Standard harness, 16 seeds, OSS CAD Suite 2026-11-01, linux-aarch64
(`docs/phase4/breakdown.md`):

| | Cells | Fmax median / worst | Score |
|---|---:|---|---:|
| `r_f1` x7 (Phase 3) | 354 | 95.4 / 91.8 MHz | 48,768 |
| `f1_core` | 374 | 95.4 / 90.7 MHz | 46,175 |

The cycles are identical. 19 of the 20 extra cells are the start-up hold.

## Decision
Option 2. **The Phase 4 baseline is 374 cells, 95.4 MHz, score 46,175.** From here on,
every score is for `f1_core` (`bench/run.py core`, `bench/score.py`, row `core`). Phase 4
reports its result against both 46,175 (like for like) and 48,768 (Phase 3).

## Consequences
- The score drops 5.3%. Nothing changed; the hold is now counted as part of the CPU.
- Making the hold shorter (Phase 4 step 2d) now raises the score, as it should, since the
  hold is real hardware on the board.
- Changes are made in one file, `f1_core.sv`. `make sim-f1_core` and the lockstep test
  check them.
