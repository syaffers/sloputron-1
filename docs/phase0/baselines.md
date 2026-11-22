# Phase 0 — Baseline measurements

All numbers below were measured in this session with the pinned toolchain. Published figures are not used.

## Toolchain (pinned)

| Tool | Version |
|---|---|
| OSS CAD Suite | release **2026-11-01** (`oss-cad-suite-linux-x64-20261101.tgz`) |
| Yosys | 0.70+286 (git 63eecf3dd) — `synth_ice40 -top top` defaults (ABC9 flow) |
| Front ends | yosys-slang plugin as bundled (`read_slang --allow-use-before-declare`); GHDL 7.0.0-dev plugin for Leros (VHDL); Yosys `read_verilog -sv` only where slang refused the source (J4a) |
| nextpnr-ice40 | 0.11.1-85-ga2c64799, `--hx1k --package tq144 --freq 100 --timing-allow-fail` |
| Seeds | 16 (seeds 1–16) per design |

Cell and BRAM counts are nextpnr post-placement `ICESTORM_LC` / `ICESTORM_RAM` from `--report`. Fmax is the `clk` domain from the same report. The LC count was identical across all 16 seeds of every design.

## Uniform harness

Each core is unmodified and wrapped in the same minimal SoC so the numbers compare like with like:

- clock on pin 21 (12 MHz oscillator net, no PLL), reset from header pin 112;
- **4 KB main memory** in BRAM (8 × SB_RAM40_4K), filled with random words so nothing constant-folds;
- one 5-bit output register on the core's I/O or bus path driving the 5 LEDs (read back so the input path also exists);
- no UART, timer or debug logic.

Exceptions, all forced by the cores' memory interfaces:
- **Minimax** needs three ports on one memory (16-bit fetch, 32-bit data read, write). A BRAM has one read port, so memory is mirrored (instruction copy + data copy, both written). Only 2 KB fits at 8 BRAMs.
- **Leros** (original 16-bit VHDL) is Harvard: 4 KB instruction ROM (`IM_BITS=11`, native is 9) plus its own 256 × 16 data memory. Two synthesis-hygiene patches let GHDL elaborate without inferring latches. Both are in `baselines/leros/`: an unreachable `when others` branch now assigns a value, and unused IM write fields are tied off. Neither changes behaviour.
- **SERV/QERV** use `servile` (SERV's own minimal wrapper: bus arbiter + RF-in-RAM interface), `with_csr=0`, no timer.
- **FemtoRV32-Quark** uses its IceStick configuration (24-bit cycle counter, `ADDR_WIDTH=24`).
- **PicoRV32** uses the repo's "small" configuration (`scripts/vivado/synth_area_top.v`); `picorv32e` additionally sets `ENABLE_REGS_16_31=0`.
- **FazyRV** (extra, 2024, iCE40-targeted) uses `CONF=MIN`, default `RFTYPE=BRAM_DP_BP`, memory shared between imem/dmem as in its own `fsoc.sv`.
- **J4a** (extra): swapforth's 4-thread barrel version of J1a, same harness as J1a.

## Results (16 seeds, HX1K tq144)

| Core | ISA / width | LC used | of 1280 | BRAM total (core-only) | Fmax median | Fmax worst | Fmax best |
|---|---|---:|---:|---:|---:|---:|---:|
| **Leros** (VHDL, 2011) | 16-bit accumulator | **343** | 27% | 9 (1) | 84.1 | 80.7 | 89.0 |
| SERV | RV32I, bit-serial | 456 | 36% | 9 (1) | **114.7** | 107.6 | 118.0 |
| QERV | RV32I, 4-bit serial | 584 | 46% | 9 (1) | 94.8 | 88.4 | 100.6 |
| FazyRV-4 | RV32I, 4-bit chunks | 729 | 57% | 12 (4) | 49.3 | 45.3 | 50.8 |
| FazyRV-8 | RV32I, 8-bit chunks | 851 | 66% | 12 (4) | 41.9 | 39.3 | 44.5 |
| FemtoRV32-Quark | RV32I, multi-cycle | 960 | 75% | 12 (4) | 57.3 | 53.1 | 61.5 |
| **J1a** (swapforth) | 16-bit Forth stack | **1013** | 79% | 8 (0) | 79.4 | 75.0 | 84.1 |
| Minimax | RVC-first, microcoded | 1253 | **98%** | 12 (4) + 2 KB only | 60.0 | 55.9 | 61.0 |
| PicoRV32 small | RV32I | **does not fit** (1517 on HX8K) | — | 12 (4) | 75.2* | 66.9* | 81.7* |
| PicoRV32 small, RV32E | RV32E | **does not fit** (1482 on HX8K) | — | 12 (4) | 77.5* | 67.5* | 82.2* |
| J4a (4-thread J1) | 16-bit Forth, barrel | **does not fit** (3494 on HX8K) | — | 8 (0) | 101.6* | 92.9* | 109.5* |

\* Placed on HX8K-CT256 with unconstrained pins because the design does not fit the HX1K. The fabric is the same speed grade, but routing differs, so treat these Fmax values as indicative only.

MHz throughout. "Core-only BRAM" = total minus the 8 main-memory blocks. For Minimax, the 8 mirrored memory blocks also count as main memory.

### Where the cells go (Yosys cell breakdown; supplementary)

| Core | LUT4 | DFF | CARRY | Note |
|---|---:|---:|---:|---|
| Leros | 259 | 121 | 47 | register file and data share one BRAM |
| SERV | 285 | 253 | 10 | |
| QERV | 388 | 282 | 22 | |
| FazyRV-4 / -8 | 507 / 633 | 358 / 360 | 18 / 21 | |
| FemtoRV-Quark | 847 | 214 | 160 | 32-bit adders/comparators dominate |
| J1a | 916 | **628** | 45 | **512 DFFs are the two stacks** (`stack2.v`: 15 + 17 deep × 16 bit shift registers) |
| J4a | 1541 | **2594** | 46 | four copies of both stacks + PC delay lines in DFFs |
| Minimax | 1030 | 324 | 71 | |
| PicoRV32 small | 1285 | 528 | 212 | |

## What the baselines already tell us

1. **iCE40 has no LUT RAM, so every bit of state outside BRAM costs a logic cell.** Half of J1a's cells are its stacks. Its 4-thread sibling J4a needs 3.4× the cells of J1a for one extra datapath's worth of work, because each thread's stacks are again FFs. Any stack or barrel design must keep stacks and contexts in BRAM. This is the single most important constraint the literature does not state for this chip.
2. **A 16-bit, CPI-1 core with its register file in BRAM is far ahead on cells.** Leros: 343 LC at 84 MHz. The 32-bit RISC-V baselines that fit are 1.3–3.7× larger; PicoRV32 (both configs) does not fit at all, and Minimax fills 98% of the chip.
3. **Serialising the datapath saves LUTs but not enough.** SERV (456 LC) is still 113 LC larger than Leros in the same harness, yet it needs roughly 32–40 cycles per instruction. QERV and FazyRV trade more cells for fewer cycles. The per-core control and bus overhead does not shrink with the datapath.
4. **Fmax on this chip is set by routing and wide muxes, not by the adder.** SERV and QERV have the shortest LUT paths and the highest Fmax. FazyRV's shared-bus harness (the same structure as its own SoC) and FemtoRV's 32-bit compare/shift paths land at 42–57 MHz.

### Indicative throughput per cell (ESTIMATE — replaced by measured benchmark cycles in Phase 3)

Nominal cycles per instruction are my estimates from each core's documented pipeline. They are not measured, and the instructions do unequal work (a 32-bit RISC-V op does more than a 16-bit accumulator op, but CRC-16, 16×16 multiply, sort and memcpy are all 16-bit-friendly).

| Core | Assumed CPI (estimate) | MIPS at median Fmax | MIPS per 1000 LC |
|---|---|---:|---:|
| Leros | 1 | 84 | ~245 |
| J1a | ~1.1 | ~72 | ~71 |
| Minimax | ~1.25 (RVC-heavy code) | ~48 | ~38 |
| FemtoRV-Quark | ~4 | ~14 | ~15 |
| QERV | ~11 | ~9 | ~15 |
| SERV | ~36 | ~3.2 | ~7 |
| FazyRV-8 / -4 | ~8 / ~12 | ~5 / ~4 | ~6 |

These estimates give the baseline to beat on the project's figure of merit: about **250 MIPS per 1000 LC (Leros-class)**, with J1a far behind only because of its FF stacks.

## Reproduce

```
scripts/fetch_toolchain.sh && scripts/fetch_baselines.sh
cd baselines && SEEDS=16 ./build.sh            # all; or ./build.sh j1a leros ...
python3 ../scripts/yosys_stats.py build/*.yslog # supplementary breakdown
```
Source revisions are pinned in `scripts/fetch_baselines.sh`.

Not yet done (belongs to Phase 1): hardware confirmation of Fmax with a PLL sweep, and `results.csv` per commit with CI.
