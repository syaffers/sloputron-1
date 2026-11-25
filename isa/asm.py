#!/usr/bin/env python3
"""sloputron-1 assembler (spec: isa/isa.toml; syntax: isa/isa.py).

usage: isa/asm.py SOURCE.s -o OUT.hex [--size 2048] [--list OUT.lst]
       isa/asm.py --disasm IMAGE.hex          print a disassembly
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from isa import AsmError, Spec, write_hex  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("source", nargs="?")
    p.add_argument("-o", "--out")
    p.add_argument("--size", type=int, default=None, help="ROM words (default: 2^pc_bits)")
    p.add_argument("--list")
    p.add_argument("--disasm")
    a = p.parse_args()
    spec = Spec()
    if a.disasm:
        words = [int(x, 16) for x in open(a.disasm).read().split()]
        last = max((i for i, w in enumerate(words) if w), default=-1)
        for i, w in enumerate(words[:last + 1]):
            print(f"{i:03x}: {w:04x}  {spec.disassemble(w)}")
        return
    if not a.source or not a.out:
        p.error("SOURCE and -o are required")
    try:
        words, labels = spec.assemble(open(a.source).read())
        write_hex(a.out, words, a.size or 1 << spec.isa["pc_bits"])
    except AsmError as e:
        sys.exit(f"{a.source}: {e}")
    if a.list:
        by_addr = {}
        for k, v in labels.items():
            by_addr.setdefault(v, []).append(k)
        with open(a.list, "w") as fh:
            for addr in sorted(words):
                for name in by_addr.get(addr, []):
                    fh.write(f"{name}:\n")
                fh.write(f"  {addr:03x}: {words[addr]:04x}  {spec.disassemble(words[addr], labels)}\n")
    print(f"{a.source}: {len(words)} words")


if __name__ == "__main__":
    main()
