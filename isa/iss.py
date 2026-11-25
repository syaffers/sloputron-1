#!/usr/bin/env python3
"""Instruction-set simulator for the sloputron-1 board (ISA 1.0 from isa/isa.toml).

It models the four-thread barrel exactly: on each clock one thread finishes one
instruction, threads in turn 0, 1, 2, 3, 0, ... So thread t's k-th instruction (from 0)
finishes on clock 4k + t, and memory sees the threads' accesses in that order, as the RTL
does. The data address space is the board's: RAM 0x000-0x3FF (address bits 9..0) and I/O at
0x800-0xFFF (isa.toml [memory]). The UART is instantaneous: the transmitter is never busy,
and a byte in `rx` is waiting until a load from UART_RX takes it.

Library use:
    from iss import Board
    b = Board(words)                     # words: list or {address: word}
    b.rx += b"r"                         # bytes for the program to read
    b.run(1_000_000)                     # clocks
    b.tx                                 # bytes the program sent
    b.on_store = lambda b, thread, addr, value: ...

usage: isa/iss.py IMAGE.hex [--clocks N] [--rx TEXT]    runs and prints the UART output
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from isa import Spec  # noqa: E402

RAM_WORDS = 1024


class Board:
    def __init__(self, words, spec=None):
        self.spec = spec or Spec()
        i = self.spec.isa
        self.n, self.pc_mask = i["threads"], (1 << i["pc_bits"]) - 1
        self.da_mask = (1 << i["data_bits"]) - 1
        self.rom = [0] * (1 << i["pc_bits"])
        for a, w in (words.items() if isinstance(words, dict) else enumerate(words)):
            self.rom[a] = w
        self.ram = [0] * RAM_WORDS
        self.pc, self.c = [0] * self.n, [0] * self.n
        self.r = [[0] * 15 + [t] for t in range(self.n)]     # r15 = thread number
        self.clock, self.tx, self.rx, self.led = 0, bytearray(), bytearray(), 0
        self.on_store = None
        f = self.spec.formats
        self._fmt = [(f[k].mask, f[k].match, k) for k in f]
        a, io = self.spec.alu, self.spec.io
        self._sub, self._add, self._shl, self._shr = a["sub"], a["add"], a["shl"], a["shr"]
        self._io = {k: v & 3 for k, v in io.items()}

    # ---- data memory ------------------------------------------------------------------
    def load(self, addr):
        addr &= self.da_mask
        if not addr & 0x800:
            return self.ram[addr & (RAM_WORDS - 1)]
        k = addr & 3
        if k == self._io["UART_STATUS"]:
            return 2 if self.rx else 0
        if k == self._io["UART_RX"]:
            if not self.rx:
                return 0
            b = self.rx[0]
            del self.rx[0]
            return b
        return 0

    def store(self, thread, addr, v):
        addr &= self.da_mask
        if self.on_store:
            self.on_store(self, thread, addr, v)
        if not addr & 0x800:
            self.ram[addr & (RAM_WORDS - 1)] = v
        elif addr & 3 == self._io["UART_TX"]:
            self.tx.append(v & 0xFF)
        elif addr & 3 == self._io["LED"]:
            self.led = v & 0x1F

    # ---- execution --------------------------------------------------------------------
    @staticmethod
    def alu(op, x, s):
        return [x + s, x - s, x & s, x | s, x ^ s, s, x << 1, x >> 1][op] & 0xFFFF

    def step(self):
        """One clock: the thread whose turn it is finishes one instruction."""
        t = self.clock % self.n
        self.clock += 1
        R, pc = self.r[t], self.pc[t]
        w = self.rom[pc]
        fmt = next(name for mask, match, name in self._fmt if w & mask == match)
        d, s, nxt = (w >> 8) & 15, (w >> 4) & 15, (pc + 1) & self.pc_mask
        if fmt in ("alu_imm", "alu_reg"):
            if fmt == "alu_imm":
                op, y, write = (w >> 12) & 7, (w & 0xFF) - (256 if w & 0x80 else 0), True
                y &= 0xFFFF
            else:
                op, y, write = w & 7, R[s], not w & 8
            x = R[d]
            if op in (self._shl, self._shr):            # carry shifts: rs = 1 brings C in
                ci = self.c[t] if fmt == "alu_reg" and s & 1 else 0
                y = ((x << 1) | ci) & 0xFFFF if op == self._shl else (x >> 1) | (ci << 15)
                self.c[t] = (x >> 15) & 1 if op == self._shl else x & 1
                if write:
                    R[d] = y
                self.pc[t] = nxt
                return
            if op == self._add:
                self.c[t] = int(x + y > 0xFFFF)
            elif op == self._sub:
                self.c[t] = int(x >= y)
            if write:
                R[d] = self.alu(op, x, y)
        elif fmt == "load":
            R[d] = self.load(R[s] + (w & 15))
        elif fmt == "store":
            self.store(t, R[s] + (w & 15), R[d])
        elif fmt == "ldhi":
            R[d] = ((w & 0xFF) << 8) | (R[d] & 0xFF)
        elif fmt == "skip":
            v, c = R[d], self.c[t]
            if [True, v == 0, v != 0, v >= 0x8000, v < 0x8000, not c, c, v & 1][w & 7]:
                nxt = (nxt + 1) & self.pc_mask
        elif fmt == "jal":
            nxt, R[d] = R[s] & self.pc_mask, pc + 1
        else:                                           # jmp / bcs / bcc (b = 3: reserved, jumps)
            b = (w >> 11) & 3
            if b == 0 or b == 3 or (b == 1) == bool(self.c[t]):
                nxt = w & self.pc_mask
        self.pc[t] = nxt

    def run(self, clocks):
        for _ in range(clocks):
            self.step()


def read_hex(path):
    return [int(x, 16) for x in open(path).read().split()]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("image")
    p.add_argument("--clocks", type=int, default=200_000)
    p.add_argument("--rx", default="")
    a = p.parse_args()
    b = Board(read_hex(a.image))
    b.rx += a.rx.encode()
    b.run(a.clocks)
    sys.stdout.write(b.tx.decode(errors="replace"))


if __name__ == "__main__":
    main()
