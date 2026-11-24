# Phase 2, experiment 1 — J1a with its stacks in BRAM

**Question:** Phase 0 found that 512 of J1a's 628 flip-flops are its two stacks. If those
stacks move into BRAM, does J1a land near the D-001 estimate of ~450–550 LC?
**Answer:** yes. It is **422 LC** with the corrected harness (511 LC with the original Phase 0
harness), at the same Fmax.

## Results
OSS CAD Suite 2026-11-01 (Yosys 0.70+286, nextpnr 0.11.1-85-ga2c64799), `--freq 100`,
seeds 1..16, uniform Phase 0 harness (`baselines/j1a/top.v`: 4 KB RAM, LED port).
Measured on linux-aarch64. That platform reproduces the linux-x86_64 numbers exactly for
J1a, blinky and uart_echo.

The harness RAM now has `(* no_rw_check *)` (see `docs/phase2/primitives.md`). Without it,
Yosys spends about 90–115 cells on harness logic that has nothing to do with the core. Both
harnesses are shown:

| | J1a | J1a, BRAM stacks | Change |
|---|---:|---:|---:|
| **Corrected harness:** logic cells | 898 | **422** | −53% |
| Fmax median / worst / best (MHz) | 88.49 / 82.19 / 90.93 | 87.01 / 82.13 / 91.63 | −2% |
| *Original harness:* logic cells | 1013 | 511 | −50% |
| Fmax median / worst / best (MHz) | 79.40 / 75.01 / 84.05 | 82.68 / 77.71 / 86.08 | +4% |
| BRAMs | 8 | 10 | +2 |
| Flip-flops (Yosys, corrected harness) | 583 | 80 | −503 |
| LUT4s (Yosys, corrected harness) | 844 | 386 | −458 |

The flip-flops fall by exactly the 512 stack bits, less the 9 pointer bits added (4 + 5).
The LUTs fall almost as far, because each shift-register bit also needed its own push/pop
mux. The two extra BRAMs leave 6 of 16 free.

With the same per-instruction behaviour in less than half the cells, J1a's figure of merit
roughly doubles before any change to its ISA. Estimated, at J1a's assumed CPI of 1.1: ~188
MIPS per 1000 LC, against ~245 for Leros (`docs/phase0/baselines.md`).

## How it works (`rtl/lib/stack_bram.sv`)
A drop-in replacement for swapforth's `stack2`, with the same ports and `DEPTH` parameter.
`j1.v` is unmodified. The wrapper is `baselines/j1a_bram/stack2.v`.

- The top entry (`head`) stays in 16 flip-flops, as before. Everything below it is in one
  BRAM, at a pointer `p`. The BRAM's built-in output register holds the entry just below
  the top, so that value costs no flip-flops.
- **Falling-edge speculative write, with no bypass logic.** A BRAM read in the same cycle
  as a write to that address returns stale data. The usual fix is a 16-bit bypass register
  plus a mux, about 32 cells per stack. Instead, the write port runs **every cycle, on the
  falling clock edge**, and writes `head` into `mem[p+1]`, the free slot just above the
  stored part. A dead slot can always be overwritten. When a push makes that slot live,
  the value was already written half a cycle before the next rising-edge read. iCE40 BRAM
  inverts its clock for free (`SB_RAM40_4KNW`), so the trick costs no cells.
- The cost is a half-cycle timing path from `p` (through a 4–5 bit increment) and `head` to
  the BRAM write port. nextpnr does time it as a half cycle: on a test design, a 5.22 ns
  rising-to-falling path gave Fmax = 1 / (2 × 5.22 ns) = 96 MHz. In J1a-BRAM it is not the
  critical path on any of the 16 seeds. The worst path is always the usual
  rising-to-rising J1 datapath.
- Overflow and underflow differ from `stack2`. The pointer wraps, while `stack2` drops the
  bottom entry and fills with `0x55aa`. Within `DEPTH` entries the two behave identically.

## Verification
`sim/stack_bram_tb.sv` (`make sim`) runs `stack_bram` against a behavioural model of
`stack2`. It uses 200,000 random push/pop/write cycles at each of J1a's two depths (15 and
17), and reaches full depth at both. Result: 0 mismatches. As a mutation check, the same
test with the write moved to the rising edge gives about 13,000 mismatches per depth, so
the test does detect the hazard the falling-edge write avoids.

## Not done yet
- **No hardware confirmation.** The harness runs random code, so there's nothing to check
  on the board. A PLL sweep of a real J1a program comes with Phase 3's benchmark harness.
- **The pointers could be cheaper.** J1 already tracks the data-stack depth in `dsp`, so
  the data-stack pointer duplicates it. Sharing it would save about 4 FFs plus an adder,
  but needs a change to `j1.v`. This experiment kept J1 unmodified.

## Consequences for the shortlist
- F2's area estimate holds, and is beaten. The single-thread stack machine starts from
  about 420 LC rather than 900, which leaves roughly 800 LC of the 1216-LC budget for ISA
  improvements.
- `stack_bram` is reusable. F4 (barrel stack machine) needs per-thread stacks, which are
  the same structure with the thread number added to the BRAM address.
