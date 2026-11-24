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

**Re-measured 2026-11-23 with a corrected harness.** The harness memories now carry
`(* no_rw_check *)`. Without it, Yosys builds extra logic so that a read during a write to
the same address returns the old value. That cost 76–135 cells per core and was not part
of the cores themselves (`docs/phase2/primitives.md`). Leros's harness memory is a ROM, so
its row is unchanged. Re-measured on linux-aarch64, which reproduces linux-x86_64 exactly
on every design tried. The "Phase 0" column is the original figure.

| Core | ISA / width | LC used | of 1280 | Phase 0 LC | BRAM total (core-only) | Fmax median | Fmax worst | Fmax best |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **SERV** | RV32I, bit-serial | **336** | 26% | 456 | 9 (1) | **112.7** | 106.8 | 117.9 |
| **Leros** (VHDL, 2011) | 16-bit accumulator | **343** | 27% | 343 | 9 (1) | 84.1 | 80.7 | 89.0 |
| QERV | RV32I, 4-bit serial | 463 | 36% | 584 | 9 (1) | 91.7 | 85.1 | 96.4 |
| FazyRV-4 | RV32I, 4-bit chunks | 594 | 46% | 729 | 12 (4) | 50.2 | 47.3 | 53.2 |
| FazyRV-8 | RV32I, 8-bit chunks | 723 | 56% | 851 | 12 (4) | 41.1 | 39.3 | 46.4 |
| FemtoRV32-Quark | RV32I, multi-cycle | 879 | 69% | 960 | 12 (4) | 56.1 | 54.0 | 59.3 |
| **J1a** (swapforth) | 16-bit Forth stack | **898** | 70% | 1013 | 8 (0) | 88.5 | 82.2 | 90.9 |
| Minimax | RVC-first, microcoded | 1177 | **92%** | 1253 | 12 (4) + 2 KB only | 57.8 | 54.6 | 59.7 |
| PicoRV32 small | RV32I | **does not fit** (1426 on HX8K) | — | 1517 | 12 (4) | 77.0* | 65.5* | 80.0* |
| PicoRV32 small, RV32E | RV32E | **does not fit** (1390 on HX8K) | — | 1482 | 12 (4) | 77.6* | 72.9* | 82.4* |
| J4a (4-thread J1) | 16-bit Forth, barrel | **does not fit** (3417 on HX8K) | — | 3494 | 8 (0) | 101.5* | 96.7* | 108.9* |
| *J1a, BRAM stacks (Phase 2)* | 16-bit Forth stack | *422* | 33% | 511 | 10 (2) | 87.0 | 82.1 | 91.6 |

Minimax and PicoRV32 still contain this kind of logic inside their own register files.
There it is needed: they read the register file without a clock and register the result
later, and adding the attribute to their register files changes nothing. Their rows include
it as a real cost of those designs.

\* Placed on HX8K-CT256 with unconstrained pins because the design does not fit the HX1K. The fabric is the same speed grade, but routing differs, so treat these Fmax values as indicative only.

MHz throughout. "Core-only BRAM" = total minus the 8 main-memory blocks. For Minimax, the 8 mirrored memory blocks also count as main memory.

### Where the cells go (Yosys cell breakdown; supplementary)

| Core | LUT4 | DFF | CARRY | Note |
|---|---:|---:|---:|---|
| Leros | 259 | 121 | 47 | register file and data share one BRAM |
| SERV | 240 | 171 | 10 | |
| QERV | 341 | 200 | 22 | |
| FazyRV-4 / -8 | 451 / 579 | 276 / 278 | 14 / 20 | |
| FemtoRV-Quark | 824 | 132 | 160 | 32-bit adders/comparators dominate |
| J1a | 844 | **583** | 45 | **512 DFFs are the two stacks** (`stack2.v`: 15 + 17 deep × 16 bit shift registers) |
| J1a, BRAM stacks | 386 | 80 | 55 | Phase 2: stacks in 2 BRAMs |
| J4a | 1490 | **2549** | 46 | four copies of both stacks + PC delay lines in DFFs |
| Minimax | 996 | 275 | 71 | |
| PicoRV32 small | 1268 | 446 | 212 | |

## What the baselines already tell us

1. **iCE40 has no LUT RAM, so every bit of state outside BRAM costs a logic cell.** Half of J1a's cells are its stacks. Its 4-thread sibling J4a needs 3.8× the cells of J1a for one extra datapath's worth of work, because each thread's stacks are again FFs. Any stack or barrel design must keep stacks and contexts in BRAM. This is the single most important constraint the literature does not state for this chip.
2. **A 16-bit, CPI-1 core with its register file in BRAM is far ahead on work per cell.** Leros: 343 LC at 84 MHz. The non-serial 32-bit RISC-V cores that fit are 2.6–3.4× larger: FemtoRV-Quark (879 LC) and Minimax (1177 LC, 92% of the chip). PicoRV32 (both configs) does not fit at all.
3. **Serialising the datapath saves cells, but throughput falls faster.** SERV (336 LC) is now the smallest core measured, 7 LC smaller than Leros, yet it needs roughly 32–40 cycles per instruction. QERV and FazyRV trade more cells for fewer cycles. The per-core control and bus overhead does not shrink with the datapath.
4. **Fmax on this chip is set by routing and wide muxes, not by the adder.** SERV and QERV have the shortest LUT paths and the highest Fmax. FazyRV's shared-bus harness (the same structure as its own SoC) and FemtoRV's 32-bit compare/shift paths land at 42–57 MHz.

### Indicative throughput per cell (ESTIMATE — replaced by measured benchmark cycles in Phase 3)

Nominal cycles per instruction are my estimates from each core's documented pipeline. They are not measured, and the instructions do unequal work (a 32-bit RISC-V op does more than a 16-bit accumulator op, but CRC-16, 16×16 multiply, sort and memcpy are all 16-bit-friendly).

| Core | Assumed CPI (estimate) | MIPS at median Fmax | MIPS per 1000 LC |
|---|---|---:|---:|
| Leros | 1 | 84 | ~245 |
| J1a, BRAM stacks (Phase 2) | ~1.1 | ~79 | ~188 |
| J1a | ~1.1 | ~80 | ~90 |
| Minimax | ~1.25 (RVC-heavy code) | ~46 | ~39 |
| QERV | ~11 | ~8 | ~18 |
| FemtoRV-Quark | ~4 | ~14 | ~16 |
| SERV | ~36 | ~3.1 | ~9 |
| FazyRV-8 / -4 | ~8 / ~12 | ~5 / ~4 | ~7 |

These estimates give the baseline to beat on the project's figure of merit: about **250 MIPS per 1000 LC (Leros-class)**. J1a was far behind only because of its FF stacks; with its stacks in BRAM it reaches ~190.

## Reproduce

```
scripts/fetch_toolchain.sh && scripts/fetch_baselines.sh
cd baselines && SEEDS=16 ./build.sh            # all; or ./build.sh j1a leros ...
                                                # JOBS=2 on small machines (1 GB RAM)
python3 ../scripts/yosys_stats.py build/*.yslog # supplementary breakdown
```
Source revisions are pinned in `scripts/fetch_baselines.sh`.

Not yet done (belongs to Phase 1): hardware confirmation of Fmax with a PLL sweep, and `results.csv` per commit with CI.
