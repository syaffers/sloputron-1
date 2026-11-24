# isa/ — the sloputron-1 instruction set

`isa.toml` is the single source for the instruction set: formats, mnemonics, ALU operations,
skip conditions, the execution model and the data address map. Everything else is
generated from it or reads it:

| File | What it is |
|---|---|
| `isa.toml` | the spec (edit this) |
| `isa.py` | library that loads the spec: encode, decode, a two-pass assembler, a disassembler. The assembly syntax is at the top of the file. |
| `asm.py` | command line: `isa/asm.py prog.s -o prog.hex [--list prog.lst]`, `isa/asm.py --disasm prog.hex` |
| `gen.py` | writes `docs/isa/isa.md` (the written spec) and `rtl/core/isa_pkg.sv` (decode constants for the RTL) |
| `test_isa.py` | checks that every canonical 16-bit encoding disassembles and re-assembles to itself, that the Phase 3 benchmark binaries agree with the spec, and some syntax cases |

After editing `isa.toml`, run `make isa` and commit the generated files with it. `make sim`
(and CI) runs `make isa-test`, which fails if they are out of date.

Programs live in `programs/`. `make` assembles `programs/NAME.s` to `build/programs/NAME.hex`.
