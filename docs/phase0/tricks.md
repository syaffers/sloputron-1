# Phase 0 — Transferable tricks

Each trick lists where it comes from, what it buys on the HX1K, and how Phase 2 will price it. "Est." = estimate, not yet measured.

## Storage: put state in BRAM

| # | Trick | Source | Expected effect on HX1K | Phase 2 measurement |
|---|---|---|---|---|
| T1 | **Stacks in BRAM, top-of-stack (and maybe NOS) in FFs.** Stack pointer indexes a 256×16 block; push/pop are writes/reads with the pointer pre-computed one cycle early. | J1 lineage, Koopman, F18A | J1a spends 512 of 628 DFFs on stacks. Est. J1-class core drops from 1013 to ~450–550 LC. **Measured (Phase 2):** 898 → 422 LC with the corrected harness (`docs/phase2/j1a_bram.md`). | J1a with `stack2` replaced by BRAM stacks; LC + Fmax over 16 seeds. |
| T2 | **Register file = window into BRAM** (`addr = {base, r}`). Context switch = change `base`. | TMS9900, Leros, Octavo, Transputer Wptr | Thread contexts cost 0 LC. 16 regs × 16 threads = exactly one 256×16 block per read port. | BRAM RF with 1 vs 2 read ports (1 vs 2 BRAMs, duplicated writes). |
| T3 | **Per-thread PCs in a BRAM** read one stage ahead in a barrel. | Octavo, BRISKI | N PCs cost 0 LC instead of 13·N. | Thread-PC storage: FF vs BRAM. |
| T4 | **Duplicate BRAMs instead of multi-port logic.** 2R1W = two copies written together. | LaForest TRETS 2014 | 0 LC per extra read port. Costs 1 BRAM each, and BRAMs are also the program store (16 total). | Count BRAMs left for program + data per design. |
| T5 | **Decode / microcode table in BRAM.** Opcode indexes a 256×16 control word. | Minimax, Glacial, classic microcode | Removes decode LUTs. Costs one BRAM and one pipeline stage, which is free in a barrel. Est. worthwhile only if LUT decode > ~40 LC. | Decode in LUTs vs BRAM on each skeleton. |
| T6 | **Constants and immediates in memory.** No wide immediate fields; a literal pool or prefix. | Octavo, Transputer | Narrower instruction formats; fewer immediate muxes. | ISA-level, Phase 3 code-size count. |

## Pipeline and control

| # | Trick | Source | Effect | Measure |
|---|---|---|---|---|
| T7 | **Barrel interleaving: thread count = longest loop** (fetch→RF read→ALU→write-back). No forwarding, no interlocks, no branch penalty. | Octavo, BRISKI, XMOS | Every synchronous BRAM read hides in a stage that already exists. The result mux and hazard logic disappear. **Measured (Phase 2):** both barrel skeletons need N ≥ 4, and 4 → 8 threads costs 7–8 LC (`docs/phase2/skeletons.md`). | Barrel skeleton at N = 4, 8. |
| T8 | **No-interlock pipelines with software NOPs / delay slots** (single-thread variant). | Langhammer et al. 2026 | Removes hazard detection; costs code size. | Hazard logic LC vs NOP count in benchmarks. |
| T9 | **Event-wait slots.** A thread blocked on a flag or channel is skipped by the scheduler or burns its slot as a NOP. | XMOS events, triggered instructions | Software peripherals with zero-latency wake-up; no interrupt controller. | A few LC in the slot scheduler. |
| T10 | **Software peripherals.** UART, SPI and PWM run as threads with cycle-exact slots, and pins are mapped into register space. | XMOS, PRU (R30/R31), RP2040 PIO | Removes UART hardware (est. 40–80 LC). The I/O budget becomes software. | UART thread at 115200 baud: instructions per bit vs slot rate. |
| T11 | **Side-set + delay fields on I/O instructions.** | RP2040 PIO | A bit-banged UART needs about 2 instructions per bit. | ISA-level. |

## Encoding and code density (program memory ≤ 8 KB)

| # | Trick | Source | Effect | Measure |
|---|---|---|---|---|
| T12 | **Fused stack instruction:** independent fields for ALU op, T→N, R→PC and stack deltas. | J1 | Several Forth words per 16-bit instruction; return is free. | Benchmark code size. |
| T13 | **Slot packing:** 3 × 5-bit ops per 16-bit word for stack code. | F18A | Est. 30–50% fewer fetches for stack-heavy loops. The cost is a slot counter and a mux on the instruction register. | Skeleton LC + code size. |
| T14 | **Prefix literals** (`pfix`/`nfix`) instead of long instruction formats. | Transputer | Fixed 8- or 16-bit units, dense small literals, no variable-length fetch. | Code size. |
| T15 | **Implicit destination (belt-style).** Results go to a rotating position, and operands are named by age. | Mill | Removes the destination field (3–4 bits per instruction). Costs a 4-bit subtractor per read port. | ISA-level code size; ~8 LC. |
| T16 | **Compressed-first 16-bit encoding** with rare long ops emulated by microcode in program memory. | Minimax | 16-bit instructions without a second decoder. | Code size + LC. |

## Datapath

| # | Trick | Source | Effect | Measure |
|---|---|---|---|---|
| T17 | **Enumerated shifts** (shift-by-1/4/8, swap bytes) instead of a barrel shifter. | Langhammer et al.; J1 (shift by 1) | A 16-bit barrel shifter is est. ~40–64 LC; fixed shifts are est. ~1 LC/bit on the result mux. | Shifter variants. |
| T18 | **SWAR 2×8-bit add/sub** by cutting the carry at bit 8. | Fisher & Dietz | Est. 1–2 LC for byte-parallel ops (CRC and memcpy benefit). | Adder variant. |
| T19 | **Share rare, expensive units across threads** (multiplier-step, shifter). | GRVI Phalanx | One copy serves all barrel threads. | — |
| T20 | **Serial multiply step** (`mstep`: conditional add + shift) instead of a parallel multiplier. HX1K has no DSP blocks. | classic, SERV | 16×16 multiply in 16 steps for est. ~16–20 LC. | Benchmark cycles vs LC. |
| T21 | **Small result mux.** Keep the number of sources into the destination register ≤ 4 so each bit is one LUT4. | measured observation (FemtoRV/J1a mux depth) | Wide N:1 muxes are the hidden cost. Each extra source past 4 adds about a LUT per bit. | N:1 mux per bit, Phase 2 cost table. |
| T22 | **Remove resets from datapath registers.** | Langhammer et al. | iCE40 DFF variants with reset (SB_DFFSR/ESR) can block LUT packing. | Compare LC with and without reset. |
