#!/usr/bin/env python3
"""Assemble the Phase 2 skeleton test programs (CRC-16/CCITT-FALSE of "123456789" = 0x29B1)
for the three provisional instruction sets: stack (F2 and F4), accumulator (F3) and
two-operand registers (F1 and F5). The encodings are documented in skel/rtl/skel_f{1,2,3}.sv.

usage: skel/asm.py OUTDIR   -> prog_stack.hex, prog_acc.hex, prog_reg.hex, prog_reg_hz.hex, data.hex

Each program reads the nine bytes from data words 0..8 (one byte per word, already shifted
into the high byte, so `crc ^= word` is the CCITT byte step), runs the bitwise CRC through a
subroutine (call/return is exercised) and stores the result to data address 0xFF.

prog_reg_hz.hex is a hazard test for the register ISA: a fixed pseudo-random straight-line
sequence that packs back-to-back register dependencies, load-use pairs, address changes
right before loads and stores, and skips. Every result is folded into a checksum register
at once, so a stale operand anywhere changes the final value. A reference interpreter (run_reg) computes its
result, and a final correction makes a correct core store 0x29B1, like the crc programs.
"""
import os, sys

ROM_WORDS = 2048
MSG = b"123456789"
CHECK = 0x29B1
ALU = dict(add=0, sub=1, and_=2, or_=3, xor=4, pass_=5, shl=6, shr=7)


def crc_ref(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


class Asm:
    """Two-pass: instructions are lambdas of the label table, so forward references work."""
    def __init__(self):
        self.code, self.labels = [], {}

    def label(self, name):
        self.labels[name] = len(self.code)

    def emit(self, f):
        self.code.append(f)

    def words(self):
        out = []
        for f in self.code:
            w = f(self.labels) if callable(f) else f
            assert 0 <= w <= 0xFFFF, hex(w)
            out.append(w)
        return out


# ---- stack ISA (F2, F4) ------------------------------------------------------------------
def stack_alu(src, ret=0, t2n=0, t2r=0, n2m=0, rd=0, dd=0):
    return (0b011 << 13) | (ret << 12) | (src << 8) | (t2n << 7) | (t2r << 6) | (n2m << 5) \
        | ((rd & 3) << 2) | (dd & 3)

S_R, S_MEM, S_T = 8, 9, 10
STACK_WORDS = {
    "nop":  stack_alu(S_T),
    "dup":  stack_alu(S_T, t2n=1, dd=1),
    "drop": stack_alu(ALU["pass_"], dd=-1),
    "swap": stack_alu(ALU["pass_"], t2n=1),
    ">r":   stack_alu(ALU["pass_"], t2r=1, rd=1, dd=-1),
    "r>":   stack_alu(S_R, t2n=1, rd=-1, dd=1),
    "@":    stack_alu(S_MEM),
    "!":    stack_alu(ALU["pass_"], n2m=1, dd=-1),      # store N at T; leaves N as T
    "+":    stack_alu(ALU["add"], dd=-1),
    "-":    stack_alu(ALU["sub"], dd=-1),               # T - N
    "and":  stack_alu(ALU["and_"], dd=-1),
    "xor":  stack_alu(ALU["xor"], dd=-1),
    "2*":   stack_alu(ALU["shl"]),
    "exit": stack_alu(S_T, ret=1, rd=-1),
}

def prog_stack():
    a = Asm()
    def w(*names):
        for n in names:
            a.emit(STACK_WORDS[n])
    def lit(v):
        assert 0 <= v < 0x8000
        a.emit(0x8000 | v)
    def jmp(l):  a.emit(lambda L: 0x0000 | L[l])
    def jz(l):   a.emit(lambda L: 0x2000 | L[l])
    def call(l): a.emit(lambda L: 0x4000 | L[l])

    lit(0x7FFF); w("2*"); lit(1); w("+")          # T = 0xFFFF
    lit(0)                                        # ( crc ptr )
    a.label("byte")
    w("dup", ">r", "@", "xor")                    # ( crc^D[ptr] )  R: ptr
    call("step8")
    w("r>"); lit(1); w("+")                       # ( crc ptr+1 )
    w("dup"); lit(len(MSG)); w("xor")             # ( crc p p^9 )
    jz("done")
    jmp("byte")
    a.label("done")
    w("drop"); lit(0xFF); w("!")                  # D[0xFF] = crc
    a.label("halt"); jmp("halt")

    a.label("step8")                              # ( crc -- crc' ), 8 bit steps
    lit(8); w(">r")
    a.label("bit")
    w("dup", "2*", "swap")                        # ( c<<1 c )
    lit(0x4000); w("2*", "and")                   # ( c<<1 c&0x8000 )
    jz("nopoly")
    lit(0x1021); w("xor")
    a.label("nopoly")
    w("r>"); lit(1); w("swap", "-")               # ( c' n-1 )
    w("dup", ">r")
    jz("done8")
    jmp("bit")
    a.label("done8")
    w("r>", "drop", "exit")
    return a.words()


# ---- accumulator ISA (F3) ----------------------------------------------------------------
def prog_acc():
    a = Asm()
    def alu(op, n):     a.emit((ALU[op] << 8) | (n & 0xFF))
    def alui(op, i):    a.emit(0x0800 | (ALU[op] << 8) | (i & 0xFF))
    def ld(n):          alu("pass_", n)
    def ldi(i):         alui("pass_", i)
    def st(n):          a.emit(0x1000 | n)
    def ldhi(i):        a.emit(0x2000 | (i & 0xFF))
    def ldaddr():       a.emit(0x3000)
    def ldind():        a.emit(0x4000)
    def stind():        a.emit(0x5000)
    def jal(n):         a.emit(0x6000 | n)
    def br(cc, l):      a.emit(lambda L: 0x8000 | (cc << 13) | L[l])
    def ldi_label(l):   a.emit(lambda L: 0x0800 | (ALU["pass_"] << 8) | L[l])
    B, BZ, BNZ, BN = 0, 1, 2, 3

    # r1 crc, r2 ptr, r3 bit count, r4 poly, r5 return address, r6 byte count
    ldi(-1); st(1)
    ldi(0x21); ldhi(0x10); st(4)
    ldi(0); st(2)
    ldi(len(MSG)); st(6)
    a.label("byte")
    ld(2); ldaddr()
    alui("add", 1); st(2)                         # one instruction between ldaddr and ldind
    ldind(); alu("xor", 1); st(1)
    ldi_label("step8"); jal(5)
    ld(6); alui("add", -1); st(6)
    br(BNZ, "byte")
    ldi(-1); ldaddr()
    ld(1); stind()                                # D[0xFF] = crc
    a.label("halt"); br(B, "halt")

    a.label("step8")                              # r1 = r1 after 8 bit steps
    ldi(8); st(3)
    a.label("bit")
    ld(1); br(BN, "neg")
    alu("shl", 0); br(B, "store")
    a.label("neg")
    alu("shl", 0); alu("xor", 4)
    a.label("store")
    st(1)
    ld(3); alui("add", -1); st(3)
    br(BNZ, "bit")
    ld(5); jal(0)                                 # return
    return a.words()


# ---- two-operand register ISA (F1) ----------------------------------------------------------
def prog_reg():
    a = Asm()
    def alui(op, d, i):  a.emit((ALU[op] << 12) | (d << 8) | (i & 0xFF))
    def alur(op, d, s):  a.emit(0x8000 | (d << 8) | (s << 4) | ALU[op])
    def li(d, i):        alui("pass_", d, i)
    def ld(d, s):        a.emit(0x9000 | (d << 8) | (s << 4))
    def st(d, s):        a.emit(0xA000 | (d << 8) | (s << 4))
    def ldhi(d, i):      a.emit(0xB000 | (d << 8) | (i & 0xFF))
    def skip(cc, d):     a.emit(0xC000 | (d << 8) | cc)
    def jal(d, s):       a.emit(0xD000 | (d << 8) | (s << 4))
    def jmp(l):          a.emit(lambda L: 0xE000 | L[l])
    def li_label(d, l):  a.emit(lambda L: (ALU["pass_"] << 12) | (d << 8) | L[l])
    Z, NZ, NEG = 1, 2, 3

    # r1 crc, r2 ptr, r3 bit count, r4 poly, r5 return address, r6 byte count, r7/r8 temp
    li(1, -1)
    li(4, 0x21); ldhi(4, 0x10)
    li(2, 0)
    li(6, len(MSG))
    a.label("byte")
    ld(7, 2); alui("add", 2, 1); alur("xor", 1, 7)
    li_label(8, "step8"); jal(5, 8)
    alui("add", 6, -1); skip(Z, 6); jmp("byte")
    li(8, -1); st(1, 8)                           # D[0xFF] = crc
    a.label("halt"); jmp("halt")

    a.label("step8")
    li(3, 8)
    a.label("bit")
    skip(NEG, 1); jmp("pos")
    alur("shl", 1, 0); alur("xor", 1, 4); jmp("next")
    a.label("pos")
    alur("shl", 1, 0)
    a.label("next")
    alui("add", 3, -1); skip(Z, 3); jmp("bit")
    jal(0, 5)                                     # return
    return a.words()


def alu_ref(op, x, s):
    return [x + s, x - s, x & s, x | s, x ^ s, s, x << 1, x >> 1][op] & 0xFFFF


def run_reg(words, data, max_steps=100_000):
    """Reference interpreter for the two-operand register ISA. Returns (first word stored to
    0xFF, instructions executed up to and including that store)."""
    R, M, pc = [0] * 16, list(data) + [0] * (256 - len(data)), 0
    sext = lambda i: (i - 256 if i & 0x80 else i) & 0xFFFF
    for n in range(1, max_steps + 1):
        w = words[pc]
        cls, d, s, nxt = w >> 12, (w >> 8) & 15, (w >> 4) & 15, (pc + 1) & 0x7FF
        if not w & 0x8000:
            R[d] = alu_ref(cls & 7, R[d], sext(w & 0xFF))
        elif cls == 8:
            R[d] = alu_ref(w & 7, R[d], R[s])
        elif cls == 9:
            R[d] = M[R[s] & 0xFF]
        elif cls == 10:
            M[R[s] & 0xFF] = R[d]
            if R[s] & 0xFF == 0xFF:
                return R[d], n
        elif cls == 11:
            R[d] = ((w & 0xFF) << 8) | (R[d] & 0xFF)
        elif cls == 12:
            v = R[d]
            if [True, v == 0, v != 0, bool(v & 0x8000)][w & 3]:
                nxt = (nxt + 1) & 0x7FF
        elif cls == 13:
            nxt, R[d] = R[s] & 0x7FF, pc + 1
        else:
            nxt = w & 0x7FF
        pc = nxt
    raise RuntimeError("no store to 0xFF")


def prog_reg_hz(fix=0):
    import random
    rng = random.Random(7)
    ops = list(ALU)
    a = []
    alui = lambda op, d, i: a.append((ALU[op] << 12) | (d << 8) | (i & 0xFF))
    alur = lambda op, d, s: a.append(0x8000 | (d << 8) | (s << 4) | ALU[op])
    ld = lambda d, s: a.append(0x9000 | (d << 8) | (s << 4))
    st = lambda d, s: a.append(0xA000 | (d << 8) | (s << 4))
    ldhi = lambda d, i: a.append(0xB000 | (d << 8) | (i & 0xFF))
    skip = lambda cc, d: a.append(0xC000 | (d << 8) | cc)
    V, ACC = (1, 2, 3, 4), 5                      # value registers; r5 checksum; r8, r9 addresses
    fold = lambda r: alur(rng.choice(("add", "xor")), ACC, r)   # every result reaches r5
    for r in V:
        alui("pass_", r, rng.randrange(256)); ldhi(r, rng.randrange(256))
    alui("pass_", ACC, 0)
    for k in range(8):                            # distinct words at 0x20..0x27
        alui("pass_", 8, 0x20 + k); alui("pass_", 6, rng.randrange(256)); ldhi(6, 0x10 * k + 1)
        st(6, 8)
    alui("pass_", 9, 0x21)
    for _ in range(90):
        k, d, s = rng.randrange(8), rng.choice(V), rng.choice(V)
        if k <= 1:   alur(rng.choice(ops), d, s); fold(d)
        elif k == 2: alui(rng.choice(ops), d, rng.randrange(256)); fold(d)
        elif k == 3:                              # new address, used at once
            r = rng.choice((8, 9)); alui("pass_", r, 0x20 + rng.randrange(8))
            (ld(d, r), fold(d)) if rng.randrange(2) else st(d, r)
        elif k == 4: st(d, rng.choice((8, 9)))
        elif k == 5: ld(d, rng.choice((8, 9))); fold(d)          # load-use, rs side
        elif k == 6: ld(d, rng.choice((8, 9))); alur(rng.choice(ops), d, s); fold(d)  # rd side
        else:        skip(rng.randrange(4), d); alui("add", ACC, 1 + rng.randrange(100))
    alur("xor", ACC, 1)
    alui("pass_", 2, fix & 0xFF); ldhi(2, fix >> 8); alur("xor", ACC, 2)
    alui("pass_", 8, 0xFF); st(ACC, 8)
    a.append(0xE000 | len(a))                     # halt
    return a


def write_hex(path, words, n):
    with open(path, "w") as f:
        for i in range(n):
            f.write(f"{words[i] if i < len(words) else 0:04x}\n")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/skel"
    os.makedirs(out, exist_ok=True)
    assert crc_ref(MSG) == CHECK
    data = [b << 8 for b in MSG]
    assert run_reg(prog_reg(), data)[0] == CHECK
    v0, _ = run_reg(prog_reg_hz(), data)
    hz = prog_reg_hz(v0 ^ CHECK)
    assert run_reg(hz, data)[0] == CHECK
    for name, words in (("stack", prog_stack()), ("acc", prog_acc()), ("reg", prog_reg())):
        assert len(words) < 128, (name, len(words))     # labels must fit 8-bit immediates
        write_hex(os.path.join(out, f"prog_{name}.hex"), words, ROM_WORDS)
        print(f"prog_{name}.hex: {len(words)} words")
    write_hex(os.path.join(out, "prog_reg_hz.hex"), hz, ROM_WORDS)
    print(f"prog_reg_hz.hex: {len(hz)} words, {run_reg(hz, data)[1]} instructions")
    print(f"prog_reg: {run_reg(prog_reg(), data)[1]} instructions to the result")
    write_hex(os.path.join(out, "data.hex"), data, 256)


if __name__ == "__main__":
    main()
