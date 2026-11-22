# sloputron-1

An original 16-bit CPU for the Lattice iCE40HX1K (iCEstick). The goal is the most benchmark
throughput per logic cell. Every design choice is justified by numbers measured on this chip
with a pinned open-source toolchain.

- Project brief, rules and status: [`CLAUDE.md`](CLAUDE.md)
- Phase 0 results:
  - [baselines](docs/phase0/baselines.md)
  - [bibliography](docs/phase0/bibliography.md)
  - [tricks](docs/phase0/tricks.md)
  - [shortlist / D-001](docs/phase0/shortlist.md)

## Baselines on the HX1K
OSS CAD Suite 2026-11-01, 16 nextpnr seeds, uniform harness with 4 KB RAM and an LED port.

| Core | Logic cells | Fmax median / worst (MHz) |
|---|---:|---|
| Leros | 343 | 84.1 / 80.7 |
| SERV | 456 | 114.7 / 107.6 |
| QERV | 584 | 94.8 / 88.4 |
| FazyRV-4 | 729 | 49.3 / 45.3 |
| FemtoRV32-Quark | 960 | 57.3 / 53.1 |
| J1a | 1013 | 79.4 / 75.0 |
| Minimax | 1253 | 60.0 / 55.9 |
| PicoRV32 (small) | does not fit | — |

## Quick start (Debian or macOS)
```
scripts/setup_debian.sh        # or scripts/setup_macos.sh; installs the pinned OSS CAD Suite
make bits && make prog D=uart_echo && make uart-test
make help                      # everything else
```
Measurement and CI rules: [docs/process.md](docs/process.md). Board bring-up:
[docs/phase1/bringup.md](docs/phase1/bringup.md).

## Reproduce the baselines
```
scripts/fetch_toolchain.sh && scripts/fetch_baselines.sh
cd baselines && SEEDS=16 ./build.sh
```
