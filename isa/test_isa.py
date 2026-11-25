#!/usr/bin/env python3
"""Self-test for isa/isa.toml and isa/isa.py (run by `make isa-test`).

1. Every 16-bit word either disassembles to text that assembles back to the same word,
   or is not canonical (prints as .word): an ignored bit set, or a field combination no
   mnemonic uses.
2. The Phase 3 kernels (bench/kernels.py, built by a separate hand-written encoder)
   disassemble to canonical text and assemble back to the same words.
3. Small syntax checks: labels, .equ, .org, .word, .ascii, lo/hi, I/O names, errors.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "bench"))
from isa import AsmError, Spec  # noqa: E402


def main():
    spec = Spec()
    canonical = 0
    for w in range(1 << 16):
        text = spec.disassemble(w)
        if text.startswith(".word"):
            continue
        words, _ = spec.assemble(text)
        assert words == {0: w}, (hex(w), text, words)
        canonical += 1

    import kernels
    n = 0
    for name, gen in kernels.KERNELS.items():     # (the random hazard test uses shl/shr
                                                  # with a non-zero rs field, not canonical)
        for w in gen():
            text = spec.disassemble(w)
            assert not text.startswith(".word"), (name, hex(w))
            assert spec.assemble(text)[0] == {0: w}, (name, hex(w), text)
            n += 1

    src = """
        .equ  K, 3
    start:
        li    r1, lo(table)
        ldhi  r1, hi(table)
        add   r1, K - 4          ; immediate form
        add   r1, r2             ; register form
        cmp   r1, r2
        skip  cs
        skip  z, r3
        ld    r4, [r1]
        st    r4, [ r2 ]
        li    r5, UART_TX & 0xff
        jal   r0, r5
        jmp   start
        nop
        .org  0x20
    table:
        .word 1, 'A', -1
        .ascii "hi\\n"
    """
    words, labels = spec.assemble(src)
    assert labels == {"start": 0, "table": 0x20}, labels
    assert words[0] == 0x5120 and words[1] == 0xB100, (hex(words[0]), hex(words[1]))
    assert words[2] == 0x01FF and words[3] == 0x8120, (hex(words[2]), hex(words[3]))
    assert words[4] == 0x8129 and words[5] == 0xC006 and words[6] == 0xC301
    assert words[9] == 0x55FC and words[11] == 0xE000 and words[12] == 0x3000
    assert [words[a] for a in range(0x20, 0x26)] == [1, 0x41, 0xFFFF, 0x68, 0x69, 0x0A]
    for bad in ("add r1", "add r1, 300", "ld r1, r2", "skip zz, r1", "jmp nowhere",
                "foo r1", "add r16, r1", "jmp 0x800"):
        try:
            spec.assemble(bad)
        except AsmError:
            continue
        raise AssertionError(f"accepted: {bad}")
    print(f"isa: {canonical} canonical encodings round-trip; {n} kernel words match; syntax OK")


if __name__ == "__main__":
    main()
