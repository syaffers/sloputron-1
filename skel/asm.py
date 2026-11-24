#!/usr/bin/env python3
"""Assemble the Phase 2 skeleton test programs (CRC-16/CCITT-FALSE of "123456789" = 0x29B1)
for the three provisional instruction sets: stack (F2 and F4), accumulator (F3) and
two-operand registers (F1). The encodings are documented in skel/rtl/skel_f{1,2,3}.sv.

usage: skel/asm.py OUTDIR   -> prog_stack.hex, prog_acc.hex, prog_reg.hex, data.hex

Each program reads the nine bytes from data words 0..8 (one byte per word, already shifted
into the high byte, so `crc ^= word` is the CCITT byte step), runs the bitwise CRC through a
subroutine (call/return is exercised) and stores the result to data address 0xFF.
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


def write_hex(path, words, n):
    with open(path, "w") as f:
        for i in range(n):
            f.write(f"{words[i] if i < len(words) else 0:04x}\n")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/skel"
    os.makedirs(out, exist_ok=True)
    assert crc_ref(MSG) == CHECK
    for name, words in (("stack", prog_stack()), ("acc", prog_acc()), ("reg", prog_reg())):
        assert len(words) < 128, (name, len(words))     # labels must fit 8-bit immediates
        write_hex(os.path.join(out, f"prog_{name}.hex"), words, ROM_WORDS)
        print(f"prog_{name}.hex: {len(words)} words")
    write_hex(os.path.join(out, "data.hex"), [b << 8 for b in MSG], 256)


if __name__ == "__main__":
    main()
