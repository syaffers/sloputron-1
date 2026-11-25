# Phase 3 — First light: the F1 CPU on the iCEstick

Design `sloputron` (`rtl/board/sloputron.sv`): the F1 core (D-006) with its program ROM,
data RAM, a hardware UART and the LEDs (D-007). It runs `programs/demo.s` from the 12 MHz
oscillator.

## Result

| | |
|---|---|
| Cells | **461** of 1,280 (36%) |
| BRAMs | **15** of 16: 8 program ROM (4 KB), 4 data RAM (1K words), 3 core (PCs, two register-file ports) |
| Fmax, 16 seeds | **96.1 MHz median, 89.4 MHz worst** (`results.csv`, linux-aarch64). The board runs at 12 MHz until the PLL sweep. |
| On the board, 2026-11-24 | prints `sloputron-1 crc16=29B1`; echoes 4,096 random bytes with 0 errors (`make uart-test`) |

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

## How to run it
```
make sim-sloputron                  # simulation: banner + echo at ±2% baud
make prog D=sloputron               # flash (board on this machine)
make uart-test                      # 4096-byte echo through thread 0
isa/asm.py programs/demo.s -o build/programs/demo.hex --list build/programs/demo.lst
```
On Linux the port is /dev/ttyUSB1. Until the `dialout` and `plugdev` groups are active
in your session, run the commands through `sg dialout -c "..."` or `sg plugdev -c "..."`.

## Next
- **PLL clock sweep:** confirm Fmax on the board, the CLAUDE.md rule.
- **The C99 ISS and Verilator lockstep** (D-006).
- **The real ISA** for F1 alone (`docs/isa/isa.md`, "Open items").
