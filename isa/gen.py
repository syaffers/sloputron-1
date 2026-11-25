#!/usr/bin/env python3
"""Generate the written spec and the SystemVerilog constants from isa/isa.toml.

usage: isa/gen.py            writes docs/isa/isa.md and rtl/core/isa_pkg.sv
       isa/gen.py --check    exits 1 if either file is out of date (used by `make isa-test`)
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from isa import Spec, fields_of  # noqa: E402

FIELD_NAME = {"d": "rd", "s": "rs", "o": "op", "w": "w (1 = no write)", "i": "imm8",
              "c": "cond", "t": "target", "k": "offset", "b": "branch (0 always, 1 C set, 2 C clear)"}


def esc(s):
    return str(s).replace("|", "\\|")


def markdown(spec):
    i, out = spec.isa, []
    w = out.append
    w(f"# {i['name']} instruction set, version {i['version']} ({i['status']})")
    w("")
    w("*Generated from `isa/isa.toml` by `isa/gen.py`. Edit the TOML, then run `make isa`.*")
    w("")
    w(i["summary"].strip())
    w("")
    w(i["history"].strip())
    w("")
    w(f"Word: {i['word_bits']} bits. Registers: r0–r{i['registers'] - 1} per thread. "
      f"Threads: {i['threads']}. PC: {i['pc_bits']} bits ({(1 << i['pc_bits']) * 2 // 1024} KB "
      f"of program). Data addresses: {i['data_bits']} bits ({1 << i['data_bits']} words).")
    w("")
    w("## Execution model")
    w("")
    w(i["execution"].strip())
    w("")
    w("## Register conventions")
    w("")
    w(i["conventions"].strip())
    w("")
    w("## Instruction formats")
    w("")
    w("Bit 15 is on the left. Letters are fields, `-` bits are ignored and written as 0.")
    w("")
    w("| Format | Bits 15..0 | Fields |")
    w("|---|---|---|")
    for f in spec.formats.values():
        fields = ", ".join(f"{FIELD_NAME[k]} [{lsb + width - 1}:{lsb}]" if width > 1 else
                           f"{FIELD_NAME[k]} [{lsb}]" for k, (lsb, width) in f.fields.items())
        w(f"| {f.title} | `{f.pattern}` | {fields} |")
    w("")
    w("## Instructions")
    w("")
    w("| Mnemonic | Operands | Format | Fixed fields | Operation |")
    w("|---|---|---|---|---|")
    for ins in spec.insns:
        for k, form in enumerate(ins["forms"]):
            fixed = ", ".join(f"{FIELD_NAME[f].split(' ')[0]} = {v}" for f, v in form.get("set", {}).items())
            f = spec.formats[form["format"]]
            unused = [x for x in f.fields if x not in form.get("set", {}) and
                      x not in fields_of(spec._syntax(form["syntax"]))]
            if unused:
                fixed = ", ".join(filter(None, [fixed, ", ".join(f"{FIELD_NAME[x].split(' ')[0]} = 0" for x in unused)]))
            desc = esc(ins["desc"]) if k == 0 else "″"
            w(f"| `{ins['name']}` | `{form['syntax'] or '—'}` | {f.title} | {fixed or '—'} | {desc} |")
    w("")
    w("## ALU operations (field op)")
    w("")
    w("x is rd. s is rs (register form) or the sign-extended imm8 (immediate form).")
    w("")
    w("| op | Name | Result | Carry flag C |")
    w("|---:|---|---|---|")
    for a in spec.raw["alu"]:
        w(f"| {a['code']} | `{a['name']}` | {esc(a['op'])} | {a.get('carry', 'unchanged')} |")
    w("")
    w("## Skip conditions (field cond)")
    w("")
    w("| cond | Name | Skips the next instruction when |")
    w("|---:|---|---|")
    for c in spec.raw["cond"]:
        w(f"| {c['code']} | `{c['name']}` | {c['test']} |")
    w("")
    w("## Data address space")
    w("")
    w(spec.raw["memory"]["description"].strip())
    w("")
    w("| Address | Name | Access | Meaning |")
    w("|---|---|---|---|")
    for m in spec.raw["memory"]["io"]:
        w(f"| {m['addr']:#05x} | `{m['name']}` | {m['access']} | {m['desc']} |")
    w("")
    w("## Assembler")
    w("")
    w("`isa/asm.py SOURCE.s -o OUT.hex` assembles, and `isa/asm.py --disasm OUT.hex` "
      "disassembles. Both read this spec. The syntax is described at the top of `isa/isa.py`:")
    w("- labels end in `:`;")
    w("- comments start with `;`;")
    w("- directives: `.org`, `.word`, `.equ`, `.ascii`;")
    w("- expressions may use `lo()`, `hi()` and the I/O names above.")
    w("")
    w("A mnemonic with both a register and an immediate form picks the form from its "
      "operand: `add r1, r2` or `add r1, -1`.")
    w("")
    w("## Open items")
    w("")
    w(i["open_items"].strip())
    w("")
    return "\n".join(out)


def systemverilog(spec):
    i, out = spec.isa, []
    w = out.append
    w(f"// {i['name']} ISA {i['version']} constants. Generated from isa/isa.toml by isa/gen.py;")
    w("// do not edit. Decode an instruction class with (insn & FMT_x_MASK) == FMT_x_MATCH.")
    w("`default_nettype none")
    w("/* verilator lint_off UNUSEDPARAM */           // a design uses only some constants")
    w("package isa_pkg;")
    w(f"    localparam int PC_BITS   = {i['pc_bits']};")
    w(f"    localparam int DATA_BITS = {i['data_bits']};")
    w(f"    localparam int THREADS   = {i['threads']};")
    w("")
    for f in spec.formats.values():
        n = f.name.upper()
        w(f"    localparam logic [15:0] FMT_{n}_MASK  = 16'h{f.mask:04x};")
        w(f"    localparam logic [15:0] FMT_{n}_MATCH = 16'h{f.match:04x};")
    w("")
    for a in spec.raw["alu"]:
        w(f"    localparam logic [2:0] ALU_{a['name'].upper()} = 3'd{a['code']};")
    w("")
    for c in spec.raw["cond"]:
        w(f"    localparam logic [2:0] CC_{c['name'].upper()} = 3'd{c['code']};")
    w("")
    for m in spec.raw["memory"]["io"]:
        w(f"    localparam logic [{i['data_bits'] - 1}:0] IO_{m['name']} = {i['data_bits']}'h{m['addr']:03x};")
    w("endpackage")
    w("/* verilator lint_on UNUSEDPARAM */")
    w("")
    return "\n".join(out)


def main():
    spec = Spec()
    targets = {os.path.join(ROOT, "docs", "isa", "isa.md"): markdown(spec),
               os.path.join(ROOT, "rtl", "core", "isa_pkg.sv"): systemverilog(spec)}
    stale = []
    for path, text in targets.items():
        old = open(path).read() if os.path.exists(path) else None
        if old != text:
            stale.append(os.path.relpath(path, ROOT))
            if "--check" not in sys.argv:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "w").write(text)
    if "--check" in sys.argv and stale:
        sys.exit(f"out of date (run `make isa`): {', '.join(stale)}")
    print(("updated: " + ", ".join(stale)) if stale else "isa: generated files up to date")


if __name__ == "__main__":
    main()
