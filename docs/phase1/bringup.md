# Phase 1 — board bring-up (blinky + UART echo)

Goal: prove the whole flow on the real iCEstick: pinned toolchain, Makefile, bitstream,
flashing, and a UART path to the host.

## Designs
| Design | What it does | Cells | Fmax median / worst (nextpnr, 16 seeds) |
|---|---|---:|---|
| `blinky` | red LEDs count in binary (~1.4 Hz LSB), green blinks | 30 | 174.9 / 174.9 MHz |
| `uart_echo` | echoes every byte at 115200 8N1; red LEDs = low nibble of the last byte, green toggles per byte | 86 | 172.8 / 158.3 MHz |

OSS CAD Suite 2026-11-01, `--freq 100`, seeds 1..16. Both designs run at the 12 MHz
oscillator; no PLL yet.

The hardware UART here (`rtl/lib/uart_rx.sv`, `uart_tx.sv`) costs about 80 cells. It is a
flow check, not a commitment: whether the CPU gets a hardware UART or a software-thread
UART is open question Q2.

Divisor: 12 MHz / 104 = 115,385 baud, +0.16% from nominal. The FT2232H's own 115200 setting
is 3 MHz / 26 = 115,385 baud, so the two ends match exactly.

Simulation (`make sim`): a 64-byte back-to-back stream at nominal baud and at a 2% slow
host, plus a 2% fast host with a 1-bit gap, all echoed correctly. A faster sender cannot
be echoed back-to-back indefinitely at the same baud. That is arithmetic, not a bug.

## Steps on the Debian machine (or a Mac: see below)
```
git clone https://github.com/syaffers/sloputron-1 && cd sloputron-1
scripts/setup_debian.sh          # apt, udev rule, groups, pinned toolchain; then log out/in
make bits
make prog D=blinky               # expect: red LEDs count, green blinks
make prog D=uart_echo
make uart-test                   # expect: PASS (4096 bytes)
picocom -b 115200 /dev/ttyUSB1   # interactive: typed characters come back; C-a C-x quits
```

### On a Mac (Apple Silicon or Intel)
```
git clone https://github.com/syaffers/sloputron-1 && cd sloputron-1
scripts/setup_macos.sh           # Xcode CLT, pyserial, pinned darwin toolchain (+ picocom via brew)
make bits && make prog D=blinky
make prog D=uart_echo && make uart-test     # port auto-detected: last /dev/cu.usbserial-*
```
CI runs the full flow on Apple Silicon with macOS's GNU make 3.81. If `iceprog` can't
claim the FTDI device, use `sudo make prog D=...`; as root, libusb can detach the macOS FTDI
driver. Also unload any third-party FTDI VCP driver installed in the past.

## Checklist (fill in on the board)
- [ ] `iceprog` sees the board without sudo (`iceprog -t`)
- [ ] blinky: LEDs count
- [ ] uart_echo: `make uart-test` PASS
- [ ] UART device is `/dev/ttyUSB1` on Linux or `/dev/cu.usbserial-…` on a Mac (record which)
- [ ] note `iceprog` time for a full flash: ______ s
- [ ] `icebram` round trip, to be done with the first design that has a program BRAM
      (Phase 2/3)

## Troubleshooting
- `Can't find iCE FTDI USB device`: udev rule not applied or not in `plugdev`. Re-plug
  the board and log out/in. `lsusb` should show `0403:6010`.
- No `/dev/ttyUSB1`: `dmesg | tail` after plugging in. Channel A is `ttyUSB0`; iceprog
  detaches it while flashing.
- Garbage on the UART: check 115200 8N1 with no flow control
  (`picocom -b 115200 -f n`).
