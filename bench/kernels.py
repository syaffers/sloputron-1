#!/usr/bin/env python3
"""The four D-002 benchmark kernels for the two-operand register ISA v3 (F1 and F5; D-005).

usage: bench/kernels.py [OUTDIR]     (default build/bench)

ISA study (D-008): X selects candidate extensions for F1, one bit each (bench/rtl/r_f1.sv):
  1  B  branch on C: bcs/bcc target (jump bits 12..11 = 01 / 10)
  2  S  carry shifts: shl/shr set C to the bit shifted out; rcl/rcr shift C in (rs = 1)
  4  O  load/store offset: address = rs + bits 3..0
  8  U  not hardware: the kernels' inner loops are unrolled (crc16 8 bits, mul16 16 bits,
        memcpy 8 words; sort has no fixed-count inner loop)
The kernels use what X provides. Files go to OUTDIR/xX/, for X in XS.

For each X, kernel K and thread count N in {1, 4, 8} (X = 0) or {4} (X > 0) this writes:
  K.hex             program (2048 words; the same for every N)
  K_nN_data.hex     initial data memory (4096 words)
  K_nN_expect.hex   data memory after every thread has finished, from the reference
                    interpreter below
plus the same three files for "hazard", a pseudo-random test of the pipeline hazards
(not a benchmark).
The testbench (bench/sim/bench_tb.sv) runs the program on the RTL and compares the whole data
memory with the expected image. This script first checks the interpreter's results against
the D-002 check values, which come from a separate Python model.

The ISA encoding is documented in bench/rtl/r_f1.sv. Conventions used by the programs:
  r15   thread number (set at configuration: 0..N-1; F5 has thread 0 only)
  r14   base of this thread's region, (thread + 1) * 256
  C     carry flag: add sets it on carry out, sub/cmp when rd >= rs unsigned; skip cc/cs
Data memory (D-005): words 0x000-0x0FF hold the shared read-only input. Thread t owns
0x100*(t+1) .. +0xFF. A store to 0xFFF (all ones) signals that the thread has finished.
Code is straightforward loops, not unrolled. Loads are scheduled at least two
instructions before their use, which costs F1 nothing and saves F5 its load stall.
"""
import os, sys

ALU = dict(add=0, sub=1, and_=2, or_=3, xor=4, pass_=5, shl=6, shr=7)
CC = dict(al=0, z=1, nz=2, neg=3, nneg=4, cc=5, cs=6, odd=7)     # cc/cs: carry flag clear/set
DA, DEPTH, ROM_WORDS = 12, 4096, 2048
DONE = DEPTH - 1
THREADS = (1, 4, 8)
XS = (0, 1, 2, 3, 7, 11, 15)                             # ISA study variants that are simulated
B, S, O, U = 1, 2, 4, 8
JCOND = dict(al=0, cs=1, cc=2)                           # branch on C (B): jump bits 12..11


# ---- D-002 inputs and check values -------------------------------------------------------
def lfsr(n):
    x, out = 0xACE1, []
    for _ in range(n):
        lsb = x & 1
        x >>= 1
        if lsb:
            x ^= 0xB400
        out.append(x)
    return out


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


# ---- assembler ---------------------------------------------------------------------------
class Asm:
    """Two-pass: jump targets are lambdas of the label table, so forward references work."""
    def __init__(self, x=0):
        self.code, self.labels, self.x = [], {}, x

    def label(self, name):
        assert name not in self.labels, name
        self.labels[name] = len(self.code)

    def words(self):
        out = [f(self.labels) if callable(f) else f for f in self.code]
        assert all(0 <= w <= 0xFFFF for w in out)
        return out

    def alui(self, op, d, i):
        assert -128 <= i <= 255, i
        self.code.append((ALU[op] << 12) | (d << 8) | (i & 0xFF))

    def alur(self, op, d, s=0):    self.code.append(0x8000 | (d << 8) | (s << 4) | ALU[op])
    def cmp(self, d, s):           self.code.append(0x8008 | (d << 8) | (s << 4) | ALU["sub"])  # C = rd >= rs
    def li(self, d, i):            self.alui("pass_", d, i)
    def mov(self, d, s):           self.alur("pass_", d, s)
    def ld(self, d, s, k=0):       self.code.append(0x9000 | (d << 8) | (s << 4) | self._k(k))  # rd <- D[rs+k]
    def st(self, d, s, k=0):       self.code.append(0xA000 | (d << 8) | (s << 4) | self._k(k))  # D[rs+k] <- rd
    def ldhi(self, d, i):          self.code.append(0xB000 | (d << 8) | (i & 0xFF))
    def skip(self, cc, d=0):       self.code.append(0xC000 | (d << 8) | CC[cc])
    def jmp(self, l):              self.code.append(lambda L: 0xE000 | L[l])

    def _k(self, k):
        assert 0 <= k < 16 and (k == 0 or self.x & O), k
        return k

    def br(self, cond, l):                                # B: bcs / bcc
        assert self.x & B
        self.code.append(lambda L: 0xE000 | (JCOND[cond] << 11) | L[l])

    def rcl(self, d):              assert self.x & S; self.code.append(0x8016 | (d << 8))
    def rcr(self, d):              assert self.x & S; self.code.append(0x8017 | (d << 8))

    def skip_jmp(self, cc, l):     # jump to l unless cc holds: one bcc/bcs with B (C tests only)
        if self.x & B and cc in ("cc", "cs"):
            self.br("cs" if cc == "cc" else "cc", l)
        else:
            self.skip(cc)
            self.jmp(l)

    def counter(self, r, n):       # loop counter for loop(): n, or -n with B
        v = (-n if self.x & B else n) & 0xFFFF
        if -128 <= (v if v < 0x8000 else v - 0x10000) <= 127:
            self.li(r, v if v < 0x8000 else v - 0x10000)
        else:
            self.li(r, v & 0xFF if v & 0x80 == 0 else (v & 0xFF) - 256)
            self.ldhi(r, v >> 8)

    def loop(self, r, l):          # count r down to 0 (or up to 0 with B: the carry ends it)
        if self.x & B:
            self.alui("add", r, 1)
            self.br("cc", l)
        else:
            self.alui("add", r, -1)
            self.skip("z", r)
            self.jmp(l)

    def prologue(self):            # r14 = (r15 + 1) * 256
        self.mov(14, 15)
        self.alui("add", 14, 1)
        for _ in range(8):
            self.alur("shl", 14)

    def finish(self, r):           # signal done with the value of r, then halt
        self.li(8, -1)             # all ones = 0xFFF within DA bits
        self.st(r, 8)
        self.label("halt")
        self.jmp("halt")


# ---- kernels -----------------------------------------------------------------------------
def k_crc16(x=0):
    """CRC-16/CCITT-FALSE over the 256 input bytes, one byte per word in the high half
    (D-002 leaves the packing to the ISA). The result goes to D[base]."""
    a = Asm(x)
    a.prologue()
    a.li(1, -1)                                  # crc
    a.li(2, 0)                                   # input pointer
    a.li(4, 0x21); a.ldhi(4, 0x10)               # poly 0x1021
    a.counter(6, 256)                            # bytes
    a.label("byte")
    a.ld(7, 2)
    a.alui("add", 2, 1)
    if not x & U:
        a.counter(3, 8)
    a.alur("xor", 1, 7)
    for k in range(8 if x & U else 1):
        if not x & U:
            a.label("bit")
        if x & S:
            a.alur("shl", 1)                     # C = old top bit
            a.skip("cc")
        else:
            a.mov(5, 1)                          # old top bit decides the xor
            a.alur("shl", 1)
            a.skip("nneg", 5)
        a.alur("xor", 1, 4)
    if not x & U:
        a.loop(3, "bit")
    a.loop(6, "byte")
    a.st(1, 14)
    a.finish(1)
    return a.words()


def k_sort(x=0):
    """Insertion sort of the 64 words at D[base], ascending, unsigned, in place.
    With offsets (O) the hole is always j + 1, so it needs no register of its own."""
    a = Asm(x)
    hole = (lambda: (4, 1)) if x & O else (lambda: (3, 0))
    a.prologue()
    a.mov(13, 14); a.alui("add", 13, 64)         # end
    a.mov(1, 14); a.alui("add", 1, 1)            # p = &a[1]
    a.label("outer")
    a.ld(2, 1)                                   # key = *p
    if not x & O:
        a.mov(3, 1)                              # q = hole
    a.mov(4, 1); a.alui("add", 4, -1)            # r4 = j = hole - 1
    a.label("inner")
    a.ld(5, 4)                                   # a[j] (read even when j < 0; then unused)
    a.cmp(4, 14)
    a.skip_jmp("cs", "place")                    # j >= 0: keep going
    a.cmp(2, 5)
    a.skip_jmp("cc", "place")                    # key < a[j]: shift a[j] up
    a.st(5, *hole())
    if not x & O:
        a.mov(3, 4)
    a.alui("add", 4, -1)
    a.jmp("inner")
    a.label("place")
    a.st(2, *hole())
    a.alui("add", 1, 1)
    a.cmp(1, 13)
    a.skip_jmp("cs", "outer")                    # p == end: done
    a.finish(1)
    return a.words()


def k_mul16(x=0):
    """64 unsigned 16x16 -> 32 multiplies, shift-and-add. Pair k is at input words 2k (a)
    and 2k+1 (b); the product goes to D[base+2k] (low) and D[base+2k+1] (high).
    v3: most significant bit of b first. With carry shifts (S): least significant bit
    first, shifting (C:hi:lo) right through the carry, one add per set bit."""
    a = Asm(x)
    a.prologue()
    a.li(1, 0)                                   # input pointer
    a.mov(7, 14)                                 # output pointer
    a.counter(8, 64)
    a.label("pair")
    a.ld(2, 1)                                   # a
    if x & O:
        a.li(4, 0)                               # hi
        a.ld(3, 1, 1)                            # b
        a.alui("add", 1, 2)
    else:
        a.alui("add", 1, 1)
        a.li(4, 0)                               # hi
        a.ld(3, 1)                               # b
        a.alui("add", 1, 1)
    if not x & S:
        a.li(5, 0)                               # lo
    if x & U:
        assert x & S
        for _ in range(16):
            a.alur("shr", 3); a.skip("cc"); a.alur("add", 4, 2); a.rcr(4); a.rcr(5)
    else:
        a.counter(6, 16)
        a.label("mbit")
    if x & U:
        pass
    elif x & S:
        a.alur("shr", 3)                         # C = next bit of b
        a.skip("cc")
        a.alur("add", 4, 2)                      # hi += a; C = carry
        a.rcr(4)                                 # (C:hi:lo) >>= 1
        a.rcr(5)
    else:
        a.alur("shl", 4)                         # (hi:lo) <<= 1
        a.skip("nneg", 5)
        a.alui("add", 4, 1)
        a.alur("shl", 5)
        a.skip("neg", 3)                         # top bit of b set: add a
        a.jmp("noadd")
        a.alur("add", 5, 2)                      # sets C on carry out of lo
        a.skip("cc")
        a.alui("add", 4, 1)
        a.label("noadd")
        a.alur("shl", 3)
    if not x & U:
        a.loop(6, "mbit")
    a.st(5, 7)
    if x & O:
        a.st(4, 7, 1)
        a.alui("add", 7, 2)
    else:
        a.alui("add", 7, 1)
        a.st(4, 7)
        a.alui("add", 7, 1)
    a.loop(8, "pair")
    a.finish(8)
    return a.words()


def k_memcpy(x=0):
    """Copy the 256 input words to D[base]."""
    a = Asm(x)
    a.prologue()
    a.li(1, 0)                                   # source
    a.mov(2, 14)                                 # destination
    k = 8 if x & U else 1                        # words per pass
    a.counter(3, 256 // k)
    a.label("loop")
    if x & O and k > 1:
        for j in range(k):
            a.ld(4 + j % 2, 1, j)                # two registers: no load-use dependence
            a.st(4 + j % 2, 2, j)
        a.alui("add", 1, k)
        a.alui("add", 2, k)
    else:
        for _ in range(k):
            a.ld(4, 1)
            a.alui("add", 1, 1)
            a.st(4, 2)
            a.alui("add", 2, 1)
    a.loop(3, "loop")
    a.finish(3)
    return a.words()


def k_hazard(x=0):
    """Not a benchmark: a fixed pseudo-random sequence that packs back-to-back register
    dependencies (both operands, compares), carry-flag skips, loads used at once, address
    changes right before a load or store, and skips. Every result is folded into r5, and
    stores go to the thread's own region, so the final memory shows any stale operand."""
    import random
    rng = random.Random(11)
    a = Asm(x)
    a.prologue()
    V, ACC = (1, 2, 3, 4), 5
    extra = [c for c, bit in (("br", B), ("shift", S), ("ofs", O)) if x & bit]
    ops = list(ALU)
    fold = lambda r: a.alur(rng.choice(("add", "xor")), ACC, r)
    a.mov(6, 15)                                 # r6 = thread * 0x0909: values differ per thread
    for _ in range(3):
        a.alur("shl", 6)
    a.alur("add", 6, 15)
    a.mov(7, 6); a.ldhi(7, 0); a.alur("shl", 7); a.alur("add", 6, 7)
    for r in V:
        a.li(r, rng.randrange(256)); a.ldhi(r, rng.randrange(256))
        a.alur(rng.choice(("add", "xor", "sub")), r, 6)
    a.li(ACC, 0)
    for k in range(8):                           # distinct words at base .. base+7
        a.mov(8, 14); a.alui("add", 8, k)
        a.li(6, rng.randrange(256)); a.ldhi(6, 0x10 * k + 1)
        a.st(6, 8)
    a.mov(9, 14)
    for step in range(150):
        k, d, s = rng.randrange(11 + len(extra)), rng.choice(V), rng.choice(V)
        if k >= 11:
            kind = extra[k - 11]
            if kind == "br":                     # branch on C right after it is set
                a.alur(rng.choice(("add", "sub", "xor")), d, s); fold(d)
                if rng.randrange(2):
                    a.cmp(s, d)
                a.br(rng.choice(("cc", "cs")), f"h{step}")
                a.alui("xor", ACC, 1 + rng.randrange(100))
                a.label(f"h{step}")
            elif kind == "shift":                # shift out to C, maybe shift C in
                a.alur(rng.choice(("add", "sub")), d, s)
                for _ in range(1 + rng.randrange(2)):
                    getattr(a, rng.choice(("rcl", "rcr")))(d) if rng.randrange(2) else \
                        a.alur(rng.choice(("shl", "shr")), d)
                fold(d)
                a.skip(rng.choice(("cc", "cs"))); a.alui("add", ACC, 1 + rng.randrange(100))
            else:                                # offset load/store, the base just written
                r = rng.choice((8, 9)); a.mov(r, 14); a.alui("add", r, rng.randrange(8))
                if rng.randrange(2):
                    a.ld(d, r, rng.randrange(8)); fold(d)
                else:
                    a.st(d, r, rng.randrange(8))
            continue
        if k <= 1:   a.alur(rng.choice(ops), d, s); fold(d)
        elif k == 2: a.alui(rng.choice(ops), d, rng.randrange(256)); fold(d)
        elif k == 3:                             # new address, used at once
            r = rng.choice((8, 9)); a.mov(r, 14); a.alui("add", r, rng.randrange(8))
            (a.ld(d, r), fold(d)) if rng.randrange(2) else a.st(d, r)
        elif k == 4: a.st(d, rng.choice((8, 9)))
        elif k == 5: a.ld(d, rng.choice((8, 9))); fold(d)                       # load-use, rs
        elif k == 6: a.ld(d, rng.choice((8, 9))); a.alur(rng.choice(ops), d, s); fold(d)
        elif k == 7:                             # the skipped add must not set C
            a.skip(rng.choice(("z", "nz", "neg", "nneg", "odd")), d); a.alui("add", ACC, 1 + rng.randrange(100))
            a.skip(rng.choice(("cc", "cs"))); a.alui("xor", ACC, 1 + rng.randrange(100))
        elif k <= 9:                             # compare right after a write, then skip on C
            a.alur(rng.choice(ops), s if k == 8 else d, rng.choice(V))
            a.cmp(d, s); a.skip(rng.choice(("cc", "cs"))); a.alui("add", ACC, 1 + rng.randrange(100))
        else:                                    # add/sub sets C, other ops keep it
            a.alur(rng.choice(("add", "sub")), d, s); fold(d)
            a.alur(rng.choice(("and_", "or_", "xor", "shl")), s, d)
            a.skip(rng.choice(("cc", "cs"))); a.alui("xor", ACC, 1 + rng.randrange(100))
    a.st(ACC, 14)
    a.finish(ACC)
    return a.words()


KERNELS = dict(crc16=k_crc16, sort=k_sort, mul16=k_mul16, memcpy=k_memcpy)
TESTS = dict(KERNELS, hazard=k_hazard)


def data_image(kernel, n):
    m = [0] * DEPTH
    if kernel == "crc16":
        m[0:256] = [(v & 0xFF) << 8 for v in lfsr(256)]
    elif kernel == "sort":
        for t in range(n):
            m[256 * (t + 1):256 * (t + 1) + 64] = lfsr(64)
    elif kernel == "mul16":
        m[0:128] = lfsr(128)
    elif kernel == "memcpy":
        m[0:256] = lfsr(256)
    return m


# ---- reference interpreter ---------------------------------------------------------------
def alu(op, x, s):
    return [x + s, x - s, x & s, x | s, x ^ s, s, x << 1, x >> 1][op] & 0xFFFF


def carry(op, x, s, c):
    """C after an ALU operation: add -> carry out, sub -> no borrow (x >= s), else unchanged."""
    return (x + s > 0xFFFF) if op == 0 else (x >= s) if op == 1 else c


def run(words, mem, thread, x=0, max_steps=2_000_000):
    """Run one thread to its store at DONE. Returns (instructions, taken skips)."""
    R, pc, skips, C = [0] * 16, 0, 0, 0
    R[15] = thread
    sext = lambda i: (i - 256 if i & 0x80 else i) & 0xFFFF
    ofs = (lambda w: w & 15) if x & O else (lambda w: 0)
    for n in range(1, max_steps + 1):
        w = words[pc]
        cls, d, s, nxt = w >> 12, (w >> 8) & 15, (w >> 4) & 15, (pc + 1) & 0x7FF
        if cls <= 8:
            reg = cls == 8
            op, xv = (w & 7, R[d]) if reg else (cls & 7, R[d])
            y = R[s] if reg else sext(w & 0xFF)
            if op >= 6 and x & S:                # carry shifts: C = bit out, rs = 1: C in
                ci = C if reg and s & 1 else 0
                out = (((xv << 1) | ci) if op == 6 else ((xv >> 1) | (ci << 15))) & 0xFFFF
                C = (xv >> 15) & 1 if op == 6 else xv & 1
            else:
                out = alu(op, xv, y)
                C = carry(op, xv, y, C)
            if not (reg and w & 8):
                R[d] = out
        elif cls == 9:
            R[d] = mem[(R[s] + ofs(w)) % DEPTH]
        elif cls == 10:
            a = (R[s] + ofs(w)) % DEPTH
            mem[a] = R[d]
            if a == DONE:
                return n, skips
        elif cls == 11:
            R[d] = ((w & 0xFF) << 8) | (R[d] & 0xFF)
        elif cls == 12:
            v = R[d]
            if [True, v == 0, v != 0, v >= 0x8000, v < 0x8000, not C, C, v & 1][w & 7]:
                nxt, skips = (nxt + 1) & 0x7FF, skips + 1
        elif cls == 13:
            nxt, R[d] = R[s] & 0x7FF, pc + 1
        else:
            jc = (w >> 11) & 3 if x & B else 0
            if jc != 1 and jc != 2 or (jc == 1) == bool(C):
                nxt = w & 0x7FF
        pc = nxt
    raise RuntimeError("no store to DONE")


def check(kernel, mem, n):
    """Each thread's region against D-002's check values."""
    for t in range(n):
        b = 256 * (t + 1)
        if kernel == "crc16":
            assert mem[b] == 0x2865 == crc16([v & 0xFF for v in lfsr(256)]), hex(mem[b])
        elif kernel == "sort":
            s = mem[b:b + 64]
            assert s == sorted(lfsr(64))
            assert (s[0], s[-1]) == (0x0E27, 0xFBB0)
            assert sum((i + 1) * v for i, v in enumerate(s)) & 0xFFFF == 0xE0FB
        elif kernel == "mul16":
            p = [mem[b + 2 * k] | mem[b + 2 * k + 1] << 16 for k in range(64)]
            x = lfsr(128)
            assert p == [x[2 * k] * x[2 * k + 1] for k in range(64)]
            acc = 0
            for v in p:
                acc ^= v
            assert (p[0], acc) == (0x6424F880, 0x755EA6D0), (hex(p[0]), hex(acc))
        else:
            assert mem[b:b + 256] == lfsr(256)


def write_hex(path, words, n):
    with open(path, "w") as f:
        for i in range(n):
            f.write(f"{words[i] if i < len(words) else 0:04x}\n")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/bench"
    for x in XS:
        d = os.path.join(out, f"x{x}")
        os.makedirs(d, exist_ok=True)
        for name, gen in TESTS.items():
            words = gen(x)
            write_hex(os.path.join(d, f"{name}.hex"), words, ROM_WORDS)
            for n in (THREADS if x == 0 else (4,)):
                mem = data_image(name, n)
                write_hex(os.path.join(d, f"{name}_n{n}_data.hex"), mem, DEPTH)
                stats = [run(words, mem, t, x) for t in range(n)]
                if name in KERNELS:
                    check(name, mem, n)
                write_hex(os.path.join(d, f"{name}_n{n}_expect.hex"), mem, DEPTH)
            print(f"x{x} {name:7s} {len(words):3d} words, {stats[0][0]:6d} instructions, "
                  f"{stats[0][1]:5d} taken skips per copy")


if __name__ == "__main__":
    main()
