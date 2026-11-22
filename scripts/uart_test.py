#!/usr/bin/env python3
"""Loopback test against rtl/board/uart_echo.sv running on the iCEstick.

usage: uart_test.py [--port /dev/ttyUSB1] [--baud 115200] [--bytes 4096] [--chunk 32]

Sends random bytes in chunks and checks every echoed byte. Chunking leaves idle time
between bursts, so a host clock slightly faster than the FPGA's cannot overrun the echo.
Needs pyserial (Debian: python3-serial).
"""
import argparse, os, sys, time

try:
    import serial
except ImportError:
    sys.exit("pyserial missing: sudo apt install python3-serial")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB1")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--bytes", type=int, default=4096)
    p.add_argument("--chunk", type=int, default=32)
    a = p.parse_args()

    with serial.Serial(a.port, a.baud, timeout=1.0) as s:
        s.reset_input_buffer()
        data = os.urandom(a.bytes)
        errors, t0 = 0, time.time()
        for i in range(0, len(data), a.chunk):
            out = data[i:i + a.chunk]
            s.write(out)
            back = s.read(len(out))
            if back != out:
                errors += 1
                print(f"chunk @{i}: sent {out.hex()} got {back.hex()} ({len(back)} bytes)")
                if errors >= 5:
                    break
        dt = time.time() - t0
    n = min(i + a.chunk, len(data))
    print(f"{n} bytes in {dt:.2f} s ({n * 10 / dt:.0f} baud effective), {errors} bad chunks")
    print("PASS" if errors == 0 else "FAIL")
    sys.exit(0 if errors == 0 else 1)

if __name__ == "__main__":
    main()
