# D-007 — A dedicated hardware UART, memory-mapped beside the barrel

**Status:** accepted, 2026-11-24 (owner). **Settles:** the UART option left open by D-006.

## Context
The chip needs a UART for the host link (FT2232H channel B). D-004 keeps the UART out of
the score, so this is an engineering choice. There are two options:
- **A software UART in one thread** (trick T10). It costs no UART cells. That thread must
  run a bit-timing loop: at 115200 baud it has to sample the pin at a fixed rate, which
  ties up one of the 4 threads and constrains the clock.
- **A hardware UART.** The Phase 1 `uart_echo` design measured 86 LC for a receiver, a
  transmitter and echo glue. It runs beside the pipeline, and every thread stays free.

## Decision
A **hardware UART** (`rtl/lib/uart_rx.sv`, `uart_tx.sv`), 115200 8N1, with registers in
the data address space. Any thread can reach it with ordinary loads and stores.

| Data address | Register | Access |
|---|---|---|
| 0xFFC | UART TX: a store sends the low byte. It is ignored while the transmitter is busy. | write |
| 0xFFD | UART status: bit 0 = transmitter busy, bit 1 = received byte waiting | read |
| 0xFFE | UART RX: the received byte. Reading it clears "byte waiting". | read |
| 0xFFF | LEDs: a store sets the 5 LEDs from bits 4..0 | write |

The I/O region is 0x800–0xFFF and is decoded from address bit 11 and the two low bits.
The other addresses in the region repeat these four registers and are reserved.

The receiver holds one byte. If software has not read it before the next byte completes,
the older byte is lost. A thread that polls the status register keeps up easily: at
12 MHz each thread runs 3 M instructions/s, against one byte per 87 µs.

## Consequences
- The core gets a load strobe (`dre`), so reading UART RX clears it only on a real load.
- The UART's cells count against the chip budget but not the score (D-004).
- The four threads stay free for programs. By convention, one thread owns the UART at a
  time.
- **Measured** (`docs/phase3/board.md`):
  - The whole chip (core, ROM, RAM, UART, LEDs) is 461 LC and 15 BRAMs, at 96.1 MHz
    median over 16 seeds.
  - On the board it echoes 4,096 bytes through a software loop in thread 0 with no
    errors.
