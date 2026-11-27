# sloputron-1

An original 16-bit CPU for the Lattice iCE40HX1K (iCEstick). The goal is the most benchmark
work per logic cell. Every design choice rests on numbers measured on this chip with a
pinned open-source toolchain (OSS CAD Suite 2026-11-01).

## What it is
- **A 4-thread barrel CPU** (D-006). Four programs take turns, one instruction each per
  clock. Each instruction has four clocks to finish, so there are no pipeline hazards and
  no forwarding logic.
- **State lives in block RAM.** Registers (16 × 16 bits per thread), the PCs and the carry
  flags sit in BRAMs, so the core itself stays small.
- **ISA 1.0** (D-008): 16-bit instructions, two-operand ALU, skips and conditional
  branches on carry, carry shifts, loads and stores with a 4-bit offset. One TOML file,
  [`isa/isa.toml`](isa/isa.toml), generates the [spec](docs/isa/isa.md), the RTL decode
  and the simulator's decode, and drives the assembler.

## Where it stands
| | Cells | Clock (nextpnr, 16 seeds, median / worst) |
|---|---:|---|
| The core, as scored (score **61,215**: iterations/s per 1000 cells, D-002 kernels) | 301 | 101.8 / 97.4 MHz |
| The whole CPU on the board: core, 4 KB ROM, 2 KB RAM, UART, LEDs | 401 of 1,280 | 97.7 / 94.6 MHz |

Phase 4 (in progress) took the core from 374 cells and a score of 46,175
(`docs/phase4/alu.md`).

- **On the board** it prints a banner and echoes bytes over the UART. With the PLL it runs
  a self-checking stress test correctly up to 132 MHz.
- **Verification:** a C instruction-set simulator checks every instruction the RTL
  finishes, in lockstep, on test programs and random ones.
- **For scale,** the smallest existing cores measured the same way are SERV (336 cells,
  but about 36 clocks per instruction) and Leros (343 cells, 84 MHz)
  ([baselines](docs/phase0/baselines.md)).

**Now:** Phase 4, making the core smaller and its clock faster with the ISA unchanged
([plan](docs/phase4/plan.md)).

## Quick start (Debian or macOS)
```
scripts/setup_debian.sh        # or scripts/setup_macos.sh; installs the pinned toolchain
make sim lint                  # all simulations, the ISS and the lockstep check
make prog D=sloputron          # build and flash the CPU (board on this machine)
make uart-test                 # echo test through the board's UART
make help                      # everything else
```

## Where to read more
| | |
|---|---|
| Project brief, rules, status | [`CLAUDE.md`](CLAUDE.md) |
| Decisions, one record each | [`docs/decisions/`](docs/decisions/README.md) |
| Phase 0: survey, baselines, shortlist | [`docs/phase0/`](docs/phase0/) |
| Phase 1: board bring-up | [`docs/phase1/bringup.md`](docs/phase1/bringup.md) |
| Phase 2: primitive costs, datapath skeletons | [`docs/phase2/`](docs/phase2/) |
| Phase 3: benchmarks, the chosen CPU, the board, verification | [`docs/phase3/summary.md`](docs/phase3/summary.md) |
| Phase 4: optimise cells and clock | [`docs/phase4/plan.md`](docs/phase4/plan.md) |
| Measurement and CI rules | [`docs/process.md`](docs/process.md) |
