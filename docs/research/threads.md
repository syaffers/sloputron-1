# Research threads (opened 2026-11-27)

**Status:** open. A breadth-first list, not a plan. Each thread asks a question, says what
is known, proposes a first cheap experiment and says what would make it new. Nothing here
is decided. The owner picks what to pursue, and each pick gets a decision record. Every
gain below is an estimate until measured.

**Where this starts from.** Phase 4 steps 2a–2b (`docs/phase4/alu.md`) took the core to
301 cells at 101.8 MHz, score 61,215. On the board the whole CPU is 401 of 1,280 cells,
uses 15 of 16 BRAMs, and runs up to 132 MHz. Step 2c (PC+2) is parked; see the end.

## What we may not be seeing

Five things about where we stand, before the threads:

1. **We are tuning a model, not the chip.** The score uses nextpnr's clock estimate. The
   board runs every build at least 28% faster than that estimate (126 MHz in Phase 3, 132
   now). Step 2a lowered nextpnr's figure by 2%; we do not know whether the chip got slower.
2. **Cells are not what runs out.** The board uses 31% of the cells and 94% of the BRAMs.
   The figure of merit rewards saving cells, but the next thing the chip cannot fit is
   memory. Code size is only a secondary measure (D-002).
3. **Each step now gains 5–15%.** That is the normal end of a local search. Steps 2a and 2b
   were large because the ALU had never been hand-structured. The remaining blocks are
   smaller.
4. **One architecture family.** Since D-006, all work has been inside "F1, 4 threads, 16-bit
   datapath". The other points (datapath width, thread count, where code lives) were
   measured once, in Phase 2, before the BRAM tricks and hand mapping existed.
5. **The barrel's strongest property is not in the score.** Every instruction of every
   thread takes exactly N clocks, whatever the other threads do. There is no cache, no
   prediction and no speculation. That is a timing and security guarantee that most CPUs
   cannot give. Today it is not measured or proven anywhere.

## The threads

### T1 — Timing isolation, proven (security, guaranteed bounds)
**Question.** Can we *prove* on the RTL that no thread can learn anything about another
thread's data from timing? And that each instruction takes exactly N clocks?

**Why it matters.** Timing side channels (Spectre, cache attacks) come from shared state
that depends on secret data. The barrel shares the pipeline, but only on a fixed schedule.
A machine-checked proof turns "it should be safe" into a guarantee. This would also settle
design questions like the PC+2 skip flag below with a proof, not intuition.

**Known.** PRET machines (bibliography 10: FlexPRET, InterPRET) build time-predictable
threads for real-time use. riscv-formal-style checks prove ISA conformance. We have not
found a formal *non-interference* proof on a whole small FPGA CPU in the sources we read.
That is to be checked properly before claiming novelty.

**First experiment.** Self-composition in SymbiYosys (already planned for the project):
- run two copies of `f1_core` with the same program and the same data for thread 0, and
  different data for threads 1–3;
- assert that thread 0's retirement trace (PC, result, timing) is identical in both
  copies, for a bounded number of clocks;
- then see what breaks the proof. Shared data RAM is an intended channel, and the UART is
  another.

**Measure.** Proof depth and run time; the cell cost of closing any channel it finds
(ideally 0).

**New if.** It is a complete proof at this size, and the cost of the guarantee is reported
in cells.

### T2 — Threads instead of peripherals (remove hardware)
**Question.** With exact timing per thread, how much I/O can software replace? For
example a UART, SPI, I²C, WS2812 LEDs or a VGA test signal, done by bit-banging.

**Why it matters.** "Prefer removing hardware to adding it." On the board, everything
outside the core (UART, I/O decode, memory glue) is about 100 cells.

**Known.** XMOS (bibliography 7), the RP2040's PIO (8), the TI PRU (9) and the Parallax
Propeller do I/O from deterministic threads or tiny state machines.

**First experiment.**
- write a UART transmitter as a thread at 12 MHz, with no UART hardware;
- the ISS gives its exact timing, so the baud error is known before it runs;
- then measure the cells saved, the highest baud rate, and what the thread costs the
  other three.

**New if.** The ISS turns timing into a contract: a timing spec per I/O routine, checked
statically, at fewer cells than any of the above.

### T3 — Code out of BRAM: hide flash latency with threads
**Question.** Half the BRAMs (8 of 16) hold the program. The iCEstick has 4 MB of SPI
flash. Can threads hide the flash's latency, as GPUs and the Tera MTA hide DRAM latency, so
that code runs from flash?

**Why it matters.** It attacks the resource that actually runs out (item 2 above). It
frees BRAM for data, more threads, or a second core.

**Known.** Execute-in-place with caches is standard on microcontrollers. Latency hiding
with many threads is the MTA/GPU idea. Doing it with 4–8 threads on 1,280 cells is the
open part.

**First experiment.** No hardware first. Model it in the ISS:
- flash latency L clocks;
- a small per-thread fetch buffer in one BRAM;
- run the D-002 kernels;
- find how many threads and how much buffer keep the clocks per instruction near 1.

**Measure.** Score and code size against BRAMs freed.

**New if.** It works at this scale, with a proven bound on fetch delay (this links to T1).

### T4 — Width × threads: a design-space map
**Question.** With all state in BRAM, which datapath width gives the most work per cell:
1, 2, 4, 8 or 16 bits? For each width, how many threads fill it?

**Why it matters.** SERV (bit-serial, 336 cells) and our F1 (16-bit, 301 cells) are two
points on one curve, and nobody has drawn the curve on this chip with these tricks.

**Known.** FazyRV and SAILOR (bibliography 24, 25) vary the width from 1 to 32 bits, on
ASICs and single-threaded.
Phase 2 measured F1 skeletons at 4 and 8 threads.

**First experiment.** A parameterised barrel with a W-bit ALU (W = 4, 8, 16) on the
skeleton harness, running the crc16 kernel. Measure cells, Fmax and clocks per
iteration.

**New if.** It is the first measured map of width against threads on a small FPGA, with
state in BRAM.

### T5 — Does nextpnr's clock predict the chip? (methodology)
**Question.** Across many builds, how well does nextpnr's timing predict the clock at which
the board actually fails? Should the score use a measured clock?

**Why it matters.** Item 1 above: every timing decision rests on this model.

**First experiment.** We already have about 40 builds with both numbers
(`docs/phase3/board_sweep.csv`, `docs/phase4/board_sweep.csv`). Then:
- add a finer sweep, in 2 MHz steps near the limit, for 16 seeds of one design;
- test whether nextpnr's figure ranks the builds in the same order as the board does.

The early data says it does not: one build that nextpnr put at 77.8 MHz ran at 123 MHz.

**Measure.** The correlation between predicted and measured clocks, how much the
measurements move from run to run, and temperature if we can control it.

**New if.** It is a calibrated model of the margin for iCE40 + nextpnr. It may also change
how the project scores clocks, which would be an owner decision.

### T6 — Redundant threads for fault tolerance
**Question.** Can two or three threads run the same program and compare results (DMR or
TMR in time), so that bit flips are detected or corrected, for a few cells?

**Why it matters.** It gives cheap reliability on small FPGAs, for radiation or ageing.
The barrel already runs threads in lockstep-like slots.

**First experiment.** Fault injection in Verilator:
- flip random bits in the register-file and PC BRAMs;
- measure how many errors a compare-on-store scheme between threads 0 and 1 catches;
- measure what that scheme costs in cells.

**New if.** It shows detection coverage against cells at this size.

### T7 — Let a search design the ISA
**Question.** `isa/isa.toml` generates the decode, the ISS and the docs. The bench harness
measures cells and cycles. Can an automated search over ISA features find instructions
we would not think of?

**Why it matters.** D-008's extensions came from a short hand study. A search could cover
much more of the space.

**First experiment.**
- start with a small space: which 8 ALU operations, and the offset width;
- give each candidate a script that rewrites the kernels;
- score every candidate with the real toolchain.

The kernels are hand-written assembly, so the hard part is rewriting them for each ISA.
A superoptimiser for short sequences may be needed.

**New if.** The toolchain sits in the loop, giving measured cells, not modelled ones.

## Parked

**Step 2c, PC+2 as a skip flag.** The idea: store "skip next" as a per-thread bit beside C
in the PC memory, and add it at the next fetch.
- This is *not* branch prediction or speculation. Nothing runs and gets undone. The flag is
  per-thread state, like the carry flag, and other threads cannot see it.
- The owner prefers to explore before taking it.
- T1 is the tool that would answer the security question with a proof.
- Estimated 20–25 cells and a shorter critical path; not built.
