# Phase 0 — Annotated bibliography

Format per entry: **idea** · **measured cost (as published, other toolchains; not used for comparison)** · **relevance to the HX1K**. Relevance is rated **H**igh / **M**edium / **L**ow. Entries are grouped by theme; within a theme, newest first where it matters.

---

## A. Barrel / fine-grained multithreading and software peripherals

1. **Abdelhamid & Koch — BRISKI: Barrel RISC-V for Kilo-core Implementations** (Heidelberg, 2025; see also "Design Space Exploration of Fast RISC-V Processors for Scalable Kilo-Core FPGA Systems", FPL 2025, doi:10.1109/FPL68686.2025.00046). https://github.com/riadhbenabdelhamid/BRISKI
   *Idea:* 16 harts interleaved per cycle, CPI 1, no hazard logic. *Cost:* ~789 LUTs + 2 RAMB18; 650 MHz single core on VU9P. *Relevance:* **H**. This is the current reference for "barrel = best throughput per LUT" on FPGAs. Contexts live in BRAM, which is the precondition on iCE40.

2. **Naylor, Moore, Thomas — Tinsel: a manythread overlay for FPGA clusters** (FPL 2019). https://www.repository.cam.ac.uk/handle/1810/294801
   *Idea:* 16-thread barrel RV32 with tightly coupled memories and hardware messaging. *Cost:* ~500 ALMs, 450 MHz, quoted 0.9 MIPS/LUT for highly threaded work. *Relevance:* **H**. It shows that per-thread throughput is only useful when the workload has enough threads, which bears on how the benchmark figure of merit is defined.

3. **LaForest & Steffan — Octavo: an FPGA-centric processor family** (FPGA 2012). https://www.eecg.utoronto.ca/~steffan/papers/laforest_octavo_fpga12.pdf · overview https://fpgacpu.ca/octavo/
   *Idea:* 8 threads in a 10-stage pipeline. There is no register file: instructions name BRAM addresses directly (4-bit opcode + three address fields), and immediates live in memory. Thread count is chosen to cover the longest loop in the pipeline. *Cost:* 550 MHz on Stratix IV, where the BRAM pulse width sets the limit; 2,478 ALUTs at 72-bit/256 words. *Relevance:* **H**. A memory-to-memory barrel is the purest form of "state belongs in BRAM". The lessons carry over: size memories to whole BRAM blocks, and choose thread count = loop length.

4. **Gray — GRVI Phalanx** (FCCM 2016 extended abstract, arXiv:1606.01037).
   *Idea:* a ~320-LUT RV32I core; expensive units (barrel shifter, etc.) are shared between cores in a cluster; Hoplite NoC. *Cost:* datapath 250 LUTs, quoted ~0.7 MIPS/LUT. *Relevance:* **M**. Sharing rare, expensive units between threads or cores carries over directly. The cluster scale does not.

5. **Fort, Capalija, Vranesic, Brown — A multithreaded soft processor for SoPC area reduction** (FCCM 2006).
   *Idea:* 4-way interleaved MT Nios II-compatible core instead of 4 cores. *Cost:* ~45% area saving versus replicated processors. *Relevance:* **M**. This is the earliest clear "MT beats replicated cores on area" result.

6. **Labrecque & Steffan — Improving pipelined soft processors with multithreading** (FPL 2007); **Labrecque, Yiannacouras, Steffan — Scaling soft processor systems** (FCCM 2008).
   *Idea:* MT removes hazard and stall logic, so deeper pipelines are cheaper. *Cost:* MT soft processors are more area-efficient than single-threaded ones; multiprocessors of single-threaded cores scaled better past one MT core. *Relevance:* **M**. These bound how many threads are worth having.

7. **XMOS XS1 (May, "The XMOS architecture and XS1 chips", IEEE Micro 2012).**
   *Idea:* 8 hardware threads, 4-stage pipeline, at most one instruction per thread in flight. Thread scheduling, channels, timers and port events are in the ISA, so peripherals are software. *Cost:* silicon; each thread gets ≤ f/4. *Relevance:* **H**. This is the model for "some threads are software peripherals". The event-wait instruction (a blocked thread is skipped) is the cheap version of triggered control.

8. **Raspberry Pi RP2040 PIO** (RP2040 datasheet §3).
   *Idea:* 4 tiny state machines per block share a 32-instruction memory. The 9 instructions carry side-set pins and a delay field, plus FIFOs to the CPU. *Cost:* silicon. *Relevance:* **H** as an encoding idea. Side-set and delay fields let one instruction both drive pins and time them. That gives a UART bit loop in about 2 instructions.

9. **TI PRU** (Sitara PRU-ICSS docs; app note SPRADE1, 2024).
   *Idea:* a non-pipelined, deterministic 32-bit RISC where registers R30/R31 *are* the GPIO pins (single-cycle pin access). *Relevance:* **M**. Mapping pins into register space costs no I/O decode logic.

10. **FlexPRET / InterPRET (PRET machines).**
    *Idea:* fine-grained MT for time-predictability; hard real-time threads get fixed slots. *Relevance:* **M**. Fixed slot scheduling makes software peripherals cycle-exact.

11. **Hive** (opencores, 2013–2015).
    *Idea:* an 8-thread barrel with a "register/stack hybrid" (operand-select + stack-control fields in a 16-bit opcode). *Relevance:* **M**. It is direct prior art for the barrel + stack combination (finalist F4).

12. **Barrel processors / C-slowing** (CDC 6600 PPUs; Leiserson–Saxe C-slow retiming; Weaver et al., FPGA 2003).
    *Idea:* replacing each register with C registers turns one machine into C interleaved ones. *Relevance:* **M**. It is the formal basis for "each pipeline register is a thread slot". On iCE40 the C copies must not be FFs, which is the J4a lesson.

## B. Operand models and instruction encoding

13. **Mill Computing — the Belt** (Godard, talks 2013–2015; patent US9513921).
    *Idea:* there are no general registers. Results drop onto a fixed-length queue, operands are named by age ("temporal addressing"), and single assignment removes rename and update hazards. The motivating statistic is that ~80% of values are read exactly once. *Cost:* none published for FPGA. *Relevance:* **M**. At single issue, a belt is a BRAM register file whose write address is a counter. The destination field disappears (denser code) for a 4-bit subtractor per operand port. Kept as an encoding trick, not a concept (see shortlist).

14. **Inmos Transputer** (Transputer Databook 1989; TN21).
    *Idea:* a 3-deep register evaluation stack (A, B, C), a workspace pointer to locals in memory, and byte instructions with a 4-bit function and a 4-bit operand. `pfix`/`nfix` extend operands; `opr` extends the opcode space. Context switch = save Iptr/Wptr. *Relevance:* **H** for tricks. Prefix encoding gives dense literals with no variable-length fetch logic, and the workspace pointer makes contexts cheap.

15. **GreenArrays F18A** (DB001 F18A Technology Reference).
    *Idea:* an 18-bit dual-stack core. Each word holds four 5-bit instruction slots (slot 3 restricted), stacks are 8 deep, there are 64 words each of RAM and ROM, and blocking neighbour ports can be executed from. Branch targets are formed from the remaining slot bits. *Relevance:* **H** for encoding. Slot-packing several stack ops per fetch halves fetches and code size for stack code, and is what makes 16-bit stack words competitive.

16. **Koopman — Stack Computers: the new wave** (1989); **Bowman — J1: a small Forth CPU core for FPGAs** (EuroForth 2010). https://www.excamera.com/files/j1.pdf
    *Idea:* J1 is a 16-bit, 3-format dual-stack machine. The ALU instruction has independent fields for T←, N→T, R→PC and stack deltas, so several Forth words fuse into one instruction. *Cost:* measured here: J1a 898 LC, more than half of it stack FFs (Phase 2: 422 LC with the stacks in BRAM). *Relevance:* **H**. This is the baseline to beat, and its weak point (FF stacks) is known.

17. **Schoeberl — Leros: a tiny microcontroller for FPGAs** (FPL 2011); **Schoeberl & Petersen — Leros: the return of the accumulator machine** (ARCS 2019); **Schoeberl — Lipsi** (ARCS 2018).
    *Idea:* a 16-bit pipelined accumulator machine. The "registers" are an on-chip memory, instructions are 16-bit with an 8-bit register/immediate field, and all are single-cycle. *Cost:* measured here: 343 LC, 84 MHz. *Relevance:* **H**. It is the strongest measured baseline and proves the BRAM-register-window idea on small FPGAs.

18. **Xilinx PicoBlaze (KCPSM3/KCPSM6, Chapman).**
    *Idea:* an 8-bit MCU with 16 registers in distributed (LUT) RAM, a ~31-deep hardware call stack, and 2 clocks per instruction. *Cost:* 26 Spartan-6 slices + 1 BRAM. *Relevance:* **M**. A fixed 2-cycle instruction shows the trade between a single-ported register memory and CPI. iCE40 lacks LUT RAM, so the register file must be BRAM.

19. **TMS9900 workspace pointer** (TI, 1976).
    *Idea:* 16 "registers" are a window in RAM at WP, and a context switch (BLWP) swaps WP/PC/ST. *Relevance:* **H**. With BRAM as the register memory, a context switch costs one register update, and this fits a barrel naturally (window base = thread id).

20. **Maxim MAXQ** (app notes 3222, 3960; MAXQ610 user guide).
    *Idea:* a production 16-bit single-cycle **transport-triggered** MCU. Every instruction is `move dst, src` or `move dst, #imm`, and moves to special registers trigger ALU ops, pointer increments, etc. *Relevance:* **M**. It shows single-bus TTA is practical for a 16-bit MCU with 16-bit instructions. Memory-mapped "trigger" registers are a cheap way to add custom units.

21. **Jääskeläinen et al. — Transport-triggered soft cores** (IPDPSW/RAW 2018); OpenASIP/TCE.
    *Idea:* TTA versus VLIW versus MicroBlaze on FPGA. *Cost:* TTA instructions are wider and need extra multiplexing due to RF port sharing; dual-issue TTA with monolithic RF had the best perf/area; program size was +21–49% versus VLIW. *Relevance:* **M**. TTA's decode saving is real, but its program size and source muxes cut against both binding constraints here (LCs, 8 KB code).

22. **Fisher & Dietz — SIMD within a register (SWAR)** (LCPC 1998).
    *Idea:* partitioned adds by masking the carry at lane boundaries. *Relevance:* **M**. On iCE40 the carry chain can be broken at bit 8 with one LUT input (`carry_in & ~split`), which gives 2×8-bit add/sub for ~1–2 LC.

## C. Serial and tiny RISC-V cores (32-bit baselines)

23. **Kindgren — SERV / QERV** (github olofk/serv; QERV press release 2023).
    *Idea:* bit-serial (QERV: 4-bit) RV32I with the register file in RAM. *Cost:* measured here: SERV 336 LC / 113 MHz; QERV 463 LC / 92 MHz. *Relevance:* **M**. They give the floor for "32-bit ISA on this chip". Throughput per cell is poor because of CPI.

24. **Kissich & Baunach — FazyRV** (CF 2024, doi:10.1145/3649153.3649195).
    *Idea:* RV32I with 1/2/4/8-bit chunks chosen at synthesis time; iCE40 is a primary target. *Cost:* measured here: FazyRV-4 594 LC / 50 MHz; FazyRV-8 723 LC / 41 MHz (shared-bus harness). *Relevance:* **M**. The area/CPI curve between serial and parallel is shallow on this chip.

25. **Ewert et al. — SAILOR** (arXiv:2602.24166, 2026).
    *Idea:* RV32I(+crypto) with 1–32-bit datapath widths. *Cost:* ASIC only (FreePDK45): 12.9–13.3 kGE; SERV 12.0, FazyRV-1 9.6, PicoRV32 15.3 kGE. *Relevance:* **L/M**. In ASIC terms the area is nearly flat from 1-bit to 16-bit, which supports a parallel 16-bit datapath.

26. **"Flexibits" (SERV/QERV/HERV for flexible electronics, arXiv:2509.08193, 2025).**
    *Relevance:* **L**. It is more evidence that serial width scales area roughly linearly while cycles scale inversely.

27. **Smecher — Minimax: a compressed-first, microcoded RISC-V CPU** (2022–).
    *Idea:* RVC executes natively at CPI 1, and RV32I is emulated by microcode stored in ordinary program memory. *Cost:* measured here: 1177 LC (92% of the chip), 58 MHz. *Relevance:* **M**. "Microcode in program memory" is a BRAM-microcode variant that costs no extra BRAM. The 16-bit encoding is the right size for an 8 KB program store.

28. **Levy — FemtoRV32-Quark** (learn-fpga).
    *Relevance:* **L/M**. It is a reference for a simple multi-cycle RV32I on the IceStick: measured 879 LC, 56 MHz.

29. **Wolf — PicoRV32 (small config).**
    *Relevance:* **L**. It does not fit the HX1K (1426 LC on HX8K). It is useful only as a sanity check.

30. **Smith — Glacial** (2018 RISC-V SoftCPU contest).
    *Idea:* RV32I on an 8-bit datapath, with microcode, scratchpad and program in one 8-bit RAM. *Relevance:* **M**. It is the extreme of "microcode in BRAM instead of LUTs".

31. **Langhammer, Pasca, Baeckler — Minimum RISC-V: Maximum FPGA Efficiency** (Altera, arXiv:2610.21552, 2026).
    *Idea:* a deeply pipelined RV32I with no forwarding or interlocks (software NOPs), then specialised per application binary. Instructions are re-encoded one-hot, unused fields are tied to 0, and synthesis prunes the dead datapath. Shifts are enumerated as fixed-shift ops instead of a barrel shifter. *Cost:* 170 ALMs / 775 MHz (Agilex 5) for a quicksort-specialised core, versus 447 ALMs unspecialised. *Relevance:* **H** for tricks. Enumerated shifts, no-interlock pipelines and dead-field pruning all transfer. Per-application specialisation conflicts with a general CPU, but it is a legitimate way to measure the cost of each instruction.

32. **VexRiscv smallest configs** (SpinalHDL docs/summary sheet).
    *Cost (published):* RV32I without bypass ≈ 1130 LC at 92 MHz on iCE40. *Relevance:* **L**. It confirms that 32-bit pipelined RISC-V does not leave room on an HX1K.

## D. Dataflow / triggered control

33. **Parashar et al. — Triggered instructions: a control paradigm for spatially-programmed architectures** (ISCA 2013); **Pellauer et al.** (ACM TOCS 2015).
    *Idea:* there is no PC. Each PE holds a small pool of instructions guarded by predicates on internal state and channel status, and a scheduler fires any ready instruction. *Cost:* quoted 8× area-normalised performance versus a general-purpose processor, for spatial accelerators. *Relevance:* **L** as a whole-CPU concept, because trigger resolution scales with the number of resident instructions. **M** as a scheduler idea: a barrel slot whose thread is waiting on a flag is skipped or reassigned.

## E. Networks-on-chip for multicore

34. **Kapre & Gray — Hoplite: building austere overlay NoCs for FPGAs** (FPL 2015; ACM TRETS 2017).
    *Idea:* a bufferless, deflection-routed, unidirectional torus. A router is just output-mux control with no FIFOs and no back-pressure. *Cost:* routers ~3.5× smaller and 2.5× faster than buffered mesh routers. *Relevance:* **L** here. It only matters if a multicore wins, and on 1280 LC a barrel delivers thread parallelism without any network. Shared BRAM mailboxes are the cheaper inter-thread channel.

## F. FPGA-specific design guidance

35. **Yiannacouras, Steffan, Rose — SPREE / application-specific customisation of soft processor microarchitecture** (TCAD 2007).
    *Idea:* automatically remove unused hardware per application. *Cost:* +25% perf/area on average. *Relevance:* **M**. Same lesson as Langhammer et al.: measure each instruction's cost and drop what the benchmarks don't use.

36. **LaForest et al. — Composing multi-ported memories on FPGAs** (TRETS 2014).
    *Idea:* build 2R/1W memories (replication, live-value table, XOR-based). *Relevance:* **H** as the cost menu for register files. On iCE40, replication (2 BRAMs per 2R1W) costs zero LC, while LVT/XOR schemes cost LUTs, so replication wins unless BRAMs run out.

---

### Gaps found
- No published FPGA implementation of a belt machine turned up. Its cost here has to come from our own Phase 2 skeleton.
- No paper measures soft cores on iCE40 with a pinned open toolchain across seeds. The baseline table in `baselines.md` appears to be new data.
- Could not read the full TTA soft-core paper: the Tampere repository blocked automated access. Figures above are from the abstract.
