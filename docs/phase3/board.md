# Phase 3 — First light: the F1 CPU on the iCEstick

Design `sloputron` (`rtl/board/sloputron.sv`): the F1 core (D-006) with its program ROM,
data RAM, a hardware UART and the LEDs (D-007). It runs `programs/demo.s` from the 12 MHz
oscillator, or any program from the PLL (see "Clock sweep"). Since D-008 the core runs ISA
1.0.

## Result

| | |
|---|---|
| Cells | **481** of 1,280 (38%), ISA 1.0. It was 461 with ISA 0.3. |
| BRAMs | **15** of 16: 8 program ROM (4 KB), 4 data RAM (1K words), 3 core (PCs, two register-file ports) |
| Fmax, 16 seeds | **89.5 MHz median, 86.7 MHz worst** (`results.csv`, linux-aarch64). It was 96.1 / 89.4 with ISA 0.3. |
| On the board | **runs at least 114 MHz** (clock sweep below) |
| On the board, 2026-11-25 (ISA 1.0, 12 MHz) | prints `sloputron-1 crc16=29B1`; echoes 4,096 random bytes with 0 errors (`make uart-test`) |

The Fmax drop from 0.3 to 1.0 is partly placement noise (the 1.0 core measured level with
0.3 in the benchmark harness, D-008). The rest may be the new offset adder in front of the
RAM address. On the board the 1.0 CPU runs well above either figure.

The demo uses all four threads:
- **Thread 0** prints the banner, then echoes every byte it receives. Each byte goes
  through the UART registers with software polling.
- **Thread 1** counts on the LEDs.
- **Thread 2** computes CRC-16/CCITT-FALSE of "123456789" and hands it to thread 0 through
  RAM: a result word, then a flag word.
- **Thread 3** idles.

The banner therefore checks three things at once: the threads separated correctly,
thread 2 computed the right answer, and the two threads communicated through memory.

## System

- **Core:** `rtl/core/f1_core.sv` is the benchmarked F1 (`bench/rtl/r_f1.sv`, ISA 0.3)
  with three changes:
  - decode constants come from `rtl/core/isa_pkg.sv`, which is generated from
    `isa/isa.toml`;
  - a load strobe `dre`, so that reading UART_RX clears it only on a real load;
  - the start-up hold (below).
- **Memory map** (`docs/isa/isa.md`):
  - RAM at data addresses 0x000–0x3FF;
  - I/O at 0x800–0xFFF: UART_TX 0xFFC, UART_STATUS 0xFFD, UART_RX 0xFFE, LED 0xFFF.

  The I/O registers are read one cycle after the address, like the RAM.
- **UART:** the Phase 1 `uart_rx`/`uart_tx` (115200 8N1), with a one-byte receive buffer.
  A store to UART_TX while the transmitter is busy is ignored, so software polls
  UART_STATUS first.

## The start-up hold: an iCE40 quirk found on the board

The first flash printed only `sloputron-1 crc16=`, cleanly, and then stopped. Simulation
had passed.
- **The cause:** every thread read r15 (its thread number) as 0, so all four ran thread
  0's code in lockstep. Their stores to a busy transmitter were dropped, which kept the
  banner clean. No thread computed the crc, so all four waited for it forever.
- **The diagnosis:**
  - The netlist held the right initial values (`synth.json` BRAM INIT).
  - A program with a delay loop before reading r15 printed the full banner.

  So the iCE40's block RAMs read back wrong for a short time after configuration. Each
  thread reads r15 within the first microsecond.
- **The fix,** in hardware (`f1_core`, parameter `STARTUP`): the core commits nothing (no
  PC, register or memory write) for its first 1,024 clocks. After that it executes only
  instructions fetched after the hold. That is 85 µs at 12 MHz and about 11 µs at 90 MHz.
  It costs **19 cells**: 442 → 461.
- **What was not measured:** how long the RAMs actually need. Reports put it at a few
  microseconds, and the hold is far longer.

The testbench does not model this behaviour, so only the board can check it.

## Clock sweep: the board against nextpnr (2026-11-25)

The project rule: confirm nextpnr's Fmax on hardware with a PLL sweep.
`scripts/board_sweep.py` does this:
- **Build.** For each clock it rebuilds `sloputron` with `programs/stress.s` in ROM:
  - the PLL set from `icepll` (12 MHz means the oscillator, no PLL);
  - the UART divider and the start-up hold scaled to that clock;
  - one nextpnr seed.
- **Flash and query.** It flashes the board and asks the program for its counts about 17
  times over 4 s.
- **Pass.** A clock passes only if:
  - every reply is well formed;
  - no failure is counted;
  - every worker's pass count rises;
  - the clock measured from the pass rate matches the PLL setting within 1%.

**The stress program** keeps three threads busy, and thread 0 reports. Each worker checks
its own answer:
- thread 1: crc16 of 256 LFSR bytes (= 0x2865);
- thread 2: 64 multiplies (xor of products = 0x755EA6D0);
- thread 3: an insertion sort of 64 words (in order, weighted sum = 0xE0FB).

nextpnr's critical path runs from a register-file read through the adder's carry chain
into the carry flag. So the kernels lean on add, sub and cmp with carry tests. The 1.0
version also uses every D-008 extension.

**Measuring the clock.** The ISS (`isa/iss.py`) gives the clocks per pass of each worker,
for example 52,644 for crc16 in 1.0. Pass rate × clocks per pass = the clock the CPU really
ran at. It came out within 0.3% of the PLL setting at every passing point (the host's timing adds
about +0.1%). So the PLL was where we asked.

Results (`board_sweep.csv`; P = pass, F = fail). Each clock is a separate build, with its
own placement:

| ISA, seed | 12–102 | 108 | 114 | 117 | 120 | 123 | 126 | 129 | 132 MHz |
|---|---|---|---|---|---|---|---|---|---|
| 0.3, 1 | P (12, 48, 60, 72, 84, 90, 96, 102) | P | P | | P | | F | | F |
| 0.3, 2 | | P | P | P | F | P | F | F | |
| 0.3, 3 | | P | P | F | P | F | F | | |
| 1.0, 1 | P (12, 60, 90, 102) | P | P | P | P | P | P | F | |
| 1.0, 2 | | P | P | P | P | P | P | P | |
| 1.0, 3 | | P | P | P | P | P | P | P | |

- **Every build runs correctly up to 114 MHz** (0.3) and 126 MHz (1.0). For these same
  builds nextpnr predicts 75–98 MHz, and its 16-seed median for the design is about
  90 MHz. So nextpnr's figure holds on the board with **at least 25% to spare**.
- **Near the limit the result depends on the build, not on nextpnr's number.**
  - The 0.3 builds pass and fail in turn between 117 and 123 MHz.
  - A 1.0 build that nextpnr put at 77.8 MHz ran at 123 MHz.
- **The two sweeps are not a like-for-like comparison.** The 1.0 stress program has a
  different instruction mix. Read them as two confirmations of the same thing.
- **Failures** were either wrong answers (a counted failure) or a CPU that never answered.
- **Caveats:**
  - this is one board, at room temperature, in a few seconds per point;
  - nextpnr's model is a worst-case guarantee across chips and temperature, and the sweep
    is not;
  - the figure of merit keeps using nextpnr's median, as D-002 says.

Cost of the PLL option:
- The 12 MHz design does not include it.
- With the PLL a build is 20–30 LC larger: 478–493 LC with 0.3 and 500–511 with 1.0. The
  extra cells are wider UART counters, a longer start-up count and the lock synchroniser. The core holds its start-up count at zero until the PLL
  reports lock.

## How to run it
```
make sim-sloputron                  # simulation: banner + echo at ±2% baud
make prog D=sloputron               # flash (board on this machine)
make uart-test                      # 4096-byte echo through thread 0
scripts/board_sweep.py --mhz 12,90,120 --seed 1   # clock sweep (builds, flashes, checks)
isa/asm.py programs/demo.s -o build/programs/demo.hex --list build/programs/demo.lst
```
On Linux the port is /dev/ttyUSB1. Until the `dialout` and `plugdev` groups are active
in your session, run the commands through `sg dialout -c "..."` or `sg plugdev -c "..."`.

## Next
- **The C99 ISS and Verilator lockstep** (D-006). `isa/iss.py` is a Python start: it
  models the barrel, RAM, UART and LEDs, and it runs the demo and the stress program.
