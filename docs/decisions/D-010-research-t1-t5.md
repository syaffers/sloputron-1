# D-010 — Take up research threads T1 (timing isolation, proven) and T5 (nextpnr against the chip)

**Status:** accepted by the owner, 2026-11-27.
**Builds on:** `docs/research/threads.md` (T1–T7). Phase 4 step 2c (PC+2) stays parked.

## Context
Phase 4 steps 2a–2b brought the core to 301 cells at 101.8 MHz (score 61,215). After that the
owner asked for a breadth-first look before more local tuning. Seven threads were opened. Two
of them question the foundations the project stands on:
- **T5:** every clock figure in the project is nextpnr's estimate. The board runs each build
  28–63% faster than that, and we have not checked whether the estimate even ranks builds in
  the right order.
- **T1:** the barrel's main property is that every instruction of every thread takes
  exactly 4 clocks, whatever the other threads do. That property is not proven anywhere.
  It is also the tool that would settle whether parked step 2c (PC+2) is safe.

## Options
1. Go back to Phase 4 step 2c and the start-up hold.
2. Take T5 first, because it is cheap and uses data we already have. Then T1, in two stages.
3. Take all seven threads at once.

## Decision
Option 2.

**T5 — does nextpnr's clock predict the chip.** Analyse the existing board sweeps first, then
run a sweep built to answer the question (`docs/research/t5_timing.md`). The project's
scoring rule does not change: any change to how clocks are scored is a separate owner
decision.

**T1 — timing isolation, proven.** The rules for the proof:
1. **The theorem comes first,** in plain words and in symbols, with every premise listed,
   before any proof is run.
2. **Unbounded proofs.** Use k-induction in SymbiYosys, not only a bounded check of N clocks.
3. **Planted leaks.** Each proof is run against copies of the core with a leak planted on
   purpose, such as a stall that depends on another thread's data. The proof must fail on
   every one of them. A proof that nothing can break proves nothing.
4. **Vacuity checks.** Cover statements show that the assumptions still allow real
   behaviour: every instruction class retires, every thread runs, and the two copies really
   do hold different data.
5. **Optionally, a check of the reasoning.** The step from "the circuit satisfies these
   properties" to "the theorem holds" can be written in Lean, so that no hand step is
   wrong.

The work comes in two stages:
- **Stage 1:** each thread retires exactly one instruction every 4 clocks, whatever it
  runs and whatever the other threads run.
- **Stage 2:** non-interference by self-composition. Two copies of `f1_core` get the same
  thread-0 program and data. The other threads differ freely. Thread 0's retirement trace
  (when it retires, and what) must be the same in both copies. Shared memory and the UART
  are intended channels. The theorem names them, and the proof models them explicitly.

## Consequences
- No RTL change from this decision, so no `results.csv` rows. If a proof finds a channel
  and closing it changes the RTL, that change follows the normal rules.
- The formal tools are already in the pinned toolchain (`sby`, `yosys-smtbmc`, yices,
  boolector, bitwuzla, z3).
- Any claim that the work is new waits for a proper literature check (threads.md, T1).
