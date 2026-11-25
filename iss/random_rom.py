#!/usr/bin/env python3
"""Random program ROMs for the lockstep test (sim/lockstep_tb.sv).

usage: iss/random_rom.py OUTDIR [--n 4]

  randK.hex  uniformly random words. Every 16-bit word is some instruction, so this covers
             every encoding, including the ones the spec reserves.
  mixK.hex   random canonical instructions, weighted so that the threads do useful-looking
             work:
             - ALU operations on r1-r8 (and r15, the thread number, so threads differ);
             - loads and stores through base registers r9-r11, which are reset to RAM
               addresses now and then, with random offsets;
             - shifts in and out of C, compares, and carry branches and skips.
Both then get the same control-flow fix, or a random program falls into a 2-word loop
within a few instructions:
- every jump or branch targets 1-8 words ahead;
- every jal goes through r14, which the two words before it set to an address 1-8 words
  after it; no other instruction writes r14, and no skip or jump can enter those three
  words half-way.
Every other bit stays random, so PC runs through the whole ROM again and again (it wraps
at 2048) with new register values each pass.
Fixed seeds, so the files only change when this script does.
"""
import argparse, os, random

ROM_WORDS = 2048


def rand_rom(rng):
    return [rng.getrandbits(16) for _ in range(ROM_WORDS)]


def mix_rom(rng):
    out = []
    reg = lambda: rng.choice((1, 2, 3, 4, 5, 6, 7, 8, 15))
    for pc in range(ROM_WORDS):
        k = rng.random()
        d = rng.randrange(1, 9)
        if k < 0.22:                                             # ALU, immediate
            w = (rng.randrange(8) << 12) | (d << 8) | rng.getrandbits(8)
        elif k < 0.44:                                           # ALU, register (incl. cmp)
            op = rng.randrange(8)
            s = rng.randrange(2) if op >= 6 else reg()           # shl/shr, rcl/rcr
            wbit = 1 if op < 6 and rng.random() < 0.2 else 0
            w = 0x8000 | (d << 8) | (s << 4) | (wbit << 3) | op
        elif k < 0.50:                                           # a base register -> RAM
            w = (5 << 12) | (rng.randrange(9, 12) << 8) | rng.randrange(0, 128)
        elif k < 0.64:                                           # ld / st via a base
            base, off = rng.randrange(9, 12), rng.randrange(16)
            src = d if rng.random() < 0.5 else rng.randrange(9, 12)
            w = (0x9000 if rng.random() < 0.5 else 0xA000) | (src << 8) | (base << 4) | off
        elif k < 0.69:                                           # ldhi
            w = 0xB000 | (d << 8) | rng.getrandbits(8)
        elif k < 0.80:                                           # skip
            w = 0xC000 | (reg() << 8) | rng.randrange(8)
        elif k < 0.95:                                           # jmp / bcs / bcc
            w = 0xE000 | (rng.randrange(3) << 11)
        else:                                                    # jal (forward() sets it up)
            w = 0xD000 | (rng.choice((0, 13)) << 8)
        out.append(w)
    return out


def forward(words, rng):
    """Make every jump, branch and jal go 1-8 words forward (see the module doc)."""
    w, n = list(words), len(words)
    for pc in range(n):
        cls = w[pc] >> 12
        if cls != 0xD and cls < 0xE and (w[pc] >> 8) & 15 == 14:   # only setups write r14
            w[pc] ^= 0x0300                                         # r14 -> r13
    # keep a jal only where its two setup words fit, clear of other setups
    jals, taken = [], set()
    for pc in range(2, n):
        if w[pc] >> 12 == 0xD:
            if {pc - 2, pc - 1, pc} & taken:
                w[pc] = 0x3000                                      # nop
            else:
                jals.append(pc)
                taken |= {pc - 2, pc - 1, pc}
    for pc in (0, 1):
        if w[pc] >> 12 == 0xD:
            w[pc] = 0x3000
    inside = {pc - k for pc in jals for k in (0, 1)}              # ldhi and jal of a setup

    def target(pc):
        t = (pc + 1 + rng.randrange(8)) % n
        while t in inside:
            t = (t + 1) % n
        return t

    for pc in range(n):
        if w[pc] >> 12 in (0xE, 0xF):                               # keep bits 12..11
            w[pc] = (w[pc] & 0xF800) | target(pc)
    for pc in jals:
        t = target(pc)
        w[pc - 2] = 0x5E00 | (t & 0xFF)                             # li   r14, lo(t)
        w[pc - 1] = 0xBE00 | (t >> 8)                               # ldhi r14, hi(t)
        w[pc] = (w[pc] & 0xFF0F) | (14 << 4)                        # jal  rd, r14
        if (w[pc] >> 8) & 15 == 14:
            w[pc] ^= 0x0300
        if w[(pc - 3) % n] >> 12 == 0xC:                            # no skip over the li
            w[(pc - 3) % n] = 0x3000
    return w


def main():
    p = argparse.ArgumentParser()
    p.add_argument("outdir")
    p.add_argument("--n", type=int, default=4)
    a = p.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    for kind, gen in (("rand", rand_rom), ("mix", mix_rom)):
        for k in range(a.n):
            rng = random.Random(f"{kind}{k}")
            with open(os.path.join(a.outdir, f"{kind}{k}.hex"), "w") as f:
                f.writelines(f"{w:04x}\n" for w in forward(gen(rng), rng))


if __name__ == "__main__":
    main()
