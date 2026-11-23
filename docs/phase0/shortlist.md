# Phase 0 — Shortlist and decision record D-001

**Status:** proposed, 2026-11-22. **Inputs:** `baselines.md` (measured), `bibliography.md`, `tricks.md`.

## The two axes that matter on this chip

The baseline measurements reduce the nine candidate concepts to two independent questions:

1. **Thread organisation: single thread, or barrel?** A barrel hides the synchronous BRAM read for free and removes forwarding and hazard logic, but each thread runs at Fmax/N. J4a (3494 LC on HX8K) against J1a (1013 LC) shows a barrel is only viable if per-thread state is in BRAM.
2. **Operand model: stack, or register window/accumulator in BRAM?** Stacks give the densest code (J1, F18A) but the stacks must leave the FFs. Register windows give the best measured cells/throughput (Leros: 343 LC, 84 MHz, CPI 1) and make thread contexts free.

So the shortlist is a 2 × 2, which lets Phase 3 separate the effect of threading from the effect of the operand model:

| | Stack (BRAM stacks) | Register window / accumulator (BRAM RF) |
|---|---|---|
| **Single thread** | **F2** — J1 lineage, done right | **F3** — Leros/TMS9900 lineage |
| **Barrel, 4–8 threads** | **F4** — J4/Hive lineage, done right | **F1** — Octavo/BRISKI/XMOS lineage |

## Finalists

**F1 — Barrel + BRAM register windows (concepts 1 + 7; tricks T2, T3, T5, T7, T9, T10).**
4–8 threads, round-robin. PCs and registers live in BRAM, and the register address is `{thread, r}` (optionally `{wp, r}` for TMS9900-style windows). The decode table may also be in BRAM, which costs no extra stage in a barrel. Some threads are software peripherals (UART). *Why:* it is the only organisation where every BRAM read stage is already paid for, and it is the published leader in throughput per LUT (BRISKI, Tinsel). *Risk:* single-thread benchmarks run at Fmax/N; see open question Q1.

**F2 — Single-thread stack machine with stacks in BRAM (concept 5 + 6; T1, T12–T14, T17, T20).**
The J1 instruction format (fused ALU/stack/return fields), stacks in BRAM, T (and possibly N) in FFs, Transputer-style prefix literals, optional F18A slot packing. *Why:* it is the declared baseline to beat, and the measured J1a shows exactly where its area goes (512 of 628 DFFs are stacks). Est. ~450–550 LC once the stacks move. *Risk:* stack-pointer arithmetic and the read-ahead needed to hide BRAM latency.

**F3 — Single-thread accumulator / workspace-register machine (concept 7; T2, T6, T15, T17, T18, T20).**
Leros-style: a 16-bit, CPI-1 pipeline whose register/data window is a BRAM, plus a workspace pointer (TMS9900) and an option for implicit destinations (belt). *Why:* it is the best measured baseline (~245 MIPS per 1000 LC, estimated) and the simplest datapath. *Risk:* more instructions per task than a 2- or 3-operand machine, so code size needs checking against 8 KB.

**F4 — Barrel stack machine (concepts 1 + 5).**
F2's ISA with per-thread stacks as regions of the same BRAMs (16 entries × N threads per block). *Why:* it is the remaining cell of the 2 × 2, prior art exists (J4a, Hive), and J4a measured the cost of getting it wrong (2594 DFFs). *Risk:* stack-pointer state is per thread. Keeping N stack pointers out of FFs needs them in a BRAM or in the PC table.

## Absorbed, not standalone

| Concept | Decision | Reason |
|---|---|---|
| 2. Belt machine | **Absorbed** into F1/F3 as encoding option T15 | At single issue a belt is a BRAM register file whose destination is a counter, so it is the F3 datapath plus ~8 LC. Its benefit is a missing destination field, which is an encoding question for Phase 3. Its costs (re-dropping long-lived values, no human-friendly assembly) matter more without a compiler. |
| 6. Transputer | **Absorbed** into F2/F3 | Its three best ideas are encoding or storage tricks, not a datapath: the prefix encoding (T14), the 3-deep register stack (which is F2's TOS/NOS caching) and the workspace pointer (T2). Channels are F1's software peripherals. |
| 8. BRAM-microcoded control | **Absorbed** as an implementation option (T5) for every finalist | It is a way to build any decoder, not an architecture. Phase 2 prices LUT decode against a BRAM table for each skeleton. It is likely to win only in F1/F4, where the stage is free. |

## Dropped

| Concept | Reason (measured where possible) | What we keep |
|---|---|---|
| 3. Transport-triggered architecture | TTA removes decode, which is small in a 16-bit single-issue core: the whole Leros is 343 LC including decode. What TTA adds lands on both binding constraints. Every function-unit input becomes a socket mux (the result-mux cost, T21, now per FU), operand and trigger registers are added, and code grows. The published soft-core study reports extra multiplexing and +21–49% program size versus VLIW. TTA's real advantage, ILP through several buses, needs multi-ported register files, which here means more duplicated BRAMs taken from the 8 KB program store. | MAXQ-style memory-mapped "trigger" registers as the cheap custom-unit and I/O interface. |
| 4. Bit/nibble-serial multicore | Measured: serial RV32 cores cost 456–851 LC for an estimated 3–9 MIPS, roughly 6–15 MIPS per 1000 LC against ~245 for Leros. The datapath shrinks, but per-core control, bus and sequencing overhead does not. Thread parallelism is cheaper through F1 (one datapath, contexts in BRAM) than through N cores. N cores also need N sets of BRAM ports, which fragments the 16 blocks and the 8 KB store, plus a network (Hoplite) or mailboxes. | Serial multiply step (T20) and serial shifts as ALU options. |
| 9. Triggered instructions | The trigger scheduler must evaluate every resident instruction's predicate each cycle, so its logic grows with program size. It suits PEs holding ≤ ~16 instructions in a spatial array; CRC-16, sort, multiply and memcpy plus a UART need hundreds of instructions in one core. | Event-wait slot scheduling in F1/F4 (T9). |

## Add-ons evaluated on every finalist (not concepts)
SWAR 2×8-bit add (T18), enumerated shifts (T17), compressed or variable-length encoding (T13, T14, T16), reset removal (T22).

## Open questions for the project owner

- **Q1 — Figure of merit for multithreaded designs.** *Resolved 2026-11-23 by [D-002](../decisions/D-002-benchmarks.md): barrels are ranked on N independent copies (N−1 with a UART thread); single-copy is reported for information.*
- **Q2 — Software UART.** *Resolved 2026-11-23 by [D-002](../decisions/D-002-benchmarks.md): the UART thread's slot is overhead, so benchmarks get N−1 threads.*

## Phase 2 entry list (from this decision)
1. J1a with BRAM stacks (confirms the F2 estimate; quickest high-value experiment).
2. Primitive cost table: 16-bit adder, N:1 mux per bit (N = 2…8), BRAM RF 1R/2R, shifter variants, thread-PC storage in FF vs BRAM, decode in LUT vs BRAM.
3. Bare datapath skeletons for F1–F4, 16 seeds each.
