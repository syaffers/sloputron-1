"""sloputron-1 instruction set, driven by isa/isa.toml: encode, decode, assemble, disassemble.

Library use:
    from isa import Spec
    spec = Spec()                              # loads isa/isa.toml
    words, labels = spec.assemble(source_text)
    spec.disassemble(0x8104)                   # -> "add r1, r0"

Assembly syntax (one instruction per line):
    label:                       a label is the address of the next word
    add  r1, r2                  register form;  add r1, -1   immediate form
    ld   r1, [r2]                st r1, [r2+3]       offset 0..15
    bcc  loop                    bcs done            branch on the carry flag
    skip z, r3                   skip cs
    jmp  loop                    jal r5, r8
    li   r1, lo(msg)             ldhi r1, hi(msg)
    .org  0x100                  continue assembling at this address
    .word 1, 2, 'A'              literal words
    .equ  UART_TX, 0xFFC         a named constant
    .ascii "text"                one word per character
Comments start with ';'. Numbers: 123, -5, 0x7f, 0b101, 'c'. Expressions may use
+ - * / % << >> & | ^ ~ ( ), labels, .equ names, and lo(x) = x & 0xff, hi(x) = (x >> 8) & 0xff.
The I/O register names from the spec (UART_TX, ...) are predefined.
"""
import os, re, tomllib

SPEC_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "isa.toml")
# syntax token -> the field letters it fills ("[rs+k]" fills two)
FIELD_FOR = {"rd": "d", "rs": "s", "[rs+k]": "sk", "imm": "i", "cond": "c", "target": "t"}


def fields_of(tokens):
    return set().union(*(FIELD_FOR[t] for t in tokens)) if tokens else set()


class AsmError(Exception):
    pass


class Format:
    def __init__(self, name, d):
        self.name, self.title = name, d["title"]
        bits = d["pattern"].replace(" ", "")
        assert len(bits) == 16, name
        self.pattern = d["pattern"]
        self.match = self.mask = self.ignored = 0
        self.fields = {}                                    # letter -> (lsb, width)
        for i, ch in enumerate(bits):
            pos = 15 - i
            if ch in "01":
                self.mask |= 1 << pos
                self.match |= int(ch) << pos
            elif ch == "-":
                self.ignored |= 1 << pos
            else:
                lsb, width = self.fields.get(ch, (pos + 1, 0))
                assert lsb == pos + 1, f"{name}: field {ch} is not contiguous"
                self.fields[ch] = (pos, width + 1)

    def width(self, f):
        return self.fields[f][1]

    def encode(self, vals):
        w = self.match
        for f, (lsb, width) in self.fields.items():
            v = vals.get(f, 0)
            assert 0 <= v < 1 << width, (self.name, f, v)
            w |= v << lsb
        return w

    def decode(self, w):
        return {f: (w >> lsb) & ((1 << width) - 1) for f, (lsb, width) in self.fields.items()}


class Spec:
    def __init__(self, path=SPEC_PATH):
        with open(path, "rb") as fh:
            self.raw = tomllib.load(fh)
        self.isa = self.raw["isa"]
        self.formats = {n: Format(n, d) for n, d in self.raw["formats"].items()}
        self.alu = {a["name"]: a["code"] for a in self.raw["alu"]}
        self.cond = {c["name"]: c["code"] for c in self.raw["cond"]}
        self.cond_name = {v: k for k, v in self.cond.items()}
        self.io = {m["name"]: m["addr"] for m in self.raw["memory"]["io"]}
        self.insns = self.raw["insn"]
        for a in self.formats.values():                    # every word decodes one way
            for b in self.formats.values():
                if a is not b:
                    common = a.mask & b.mask
                    assert (a.match & common) != (b.match & common), (a.name, b.name)

    # ---- decoding --------------------------------------------------------------------------
    def format_of(self, w):
        for f in self.formats.values():
            if w & f.mask == f.match:
                return f
        raise ValueError(f"{w:#06x} matches no format")

    def disassemble(self, w, labels=None):
        """Canonical text for w, or '.word 0x....' when no mnemonic encodes it exactly."""
        f = self.format_of(w)
        vals = f.decode(w)
        if w & f.ignored:
            return f".word {w:#06x}"
        for ins in self.insns:
            for form in ins["forms"]:
                if form["format"] != f.name:
                    continue
                toks = self._syntax(form["syntax"])
                free = fields_of(toks)
                fixed = form.get("set", {})
                if all(vals[k] == fixed.get(k, vals[k] if k in free else 0) for k in vals):
                    ops = [self._operand_text(t, vals, f, labels) for t in toks]
                    return f"{ins['name']} {', '.join(ops)}".rstrip()
        return f".word {w:#06x}"

    def _operand_text(self, tok, vals, f, labels):
        if tok == "[rs+k]":
            return f"[r{vals['s']}+{vals['k']}]" if vals["k"] else f"[r{vals['s']}]"
        v = vals[FIELD_FOR[tok]]
        if tok == "rd" or tok == "rs":
            return f"r{v}"
        if tok == "cond":
            return self.cond_name[v]
        if tok == "target":
            names = [k for k, a in (labels or {}).items() if a == v]
            return names[0] if names else f"{v:#05x}"
        if f.name == "alu_imm":                            # sign-extended immediate
            return str(v - 256 if v & 0x80 else v)
        return f"{v:#04x}"

    @staticmethod
    def _syntax(s):
        return [t.strip() for t in s.split(",")] if s.strip() else []

    # ---- assembling ----------------------------------------------------------------------
    def assemble(self, text, origin=0):
        """Two passes. Returns (words, labels); words is a dict address -> word."""
        lines = self._lines(text)
        consts = dict(self.io)
        labels = {}
        for pass_no in (1, 2):
            pc, words = origin, {}
            for lineno, label, op, args in lines:
                try:
                    if label is not None:
                        if pass_no == 1:
                            if label in labels or label in consts:
                                raise AsmError(f"'{label}' defined twice")
                            labels[label] = pc
                    if op is None:
                        continue
                    env = {**consts, **labels}
                    if op == ".org":
                        pc = self._eval(args, env, pass_no)
                    elif op == ".equ":
                        name, expr = [a.strip() for a in args.split(",", 1)]
                        if pass_no == 1:
                            consts[name] = self._eval(expr, env, 2)
                    elif op == ".word":
                        for a in self._split(args):
                            words[pc] = self._eval(a, env, pass_no) & 0xFFFF
                            pc += 1
                    elif op == ".ascii":
                        m = re.fullmatch(r'"(.*)"', args.strip())
                        if not m:
                            raise AsmError(".ascii needs a quoted string")
                        for ch in bytes(m.group(1), "utf-8").decode("unicode_escape"):
                            words[pc] = ord(ch)
                            pc += 1
                    else:
                        words[pc] = self._encode(op, self._split(args), env, pass_no)
                        pc += 1
                except AsmError as e:
                    raise AsmError(f"line {lineno}: {e}") from None
        return words, labels

    def _lines(self, text):
        out = []
        for n, raw in enumerate(text.splitlines(), 1):
            line = re.sub(r";.*", "", raw).strip()
            label = None
            m = re.match(r"([A-Za-z_.][\w.]*):\s*(.*)", line)
            if m:
                label, line = m.group(1), m.group(2)
            if not line:
                if label is not None:
                    out.append((n, label, None, ""))
                continue
            op, _, args = line.partition(" ")
            out.append((n, label, op.lower(), args.strip()))
        return out

    @staticmethod
    def _split(args):
        parts, depth, cur, quote = [], 0, "", False
        for ch in args:
            if ch == "'" :
                quote = not quote
            if ch in "([" and not quote:
                depth += 1
            if ch in ")]" and not quote:
                depth -= 1
            if ch == "," and depth == 0 and not quote:
                parts.append(cur.strip())
                cur = ""
            else:
                cur += ch
        if cur.strip():
            parts.append(cur.strip())
        return parts

    def _eval(self, expr, env, pass_no):
        expr = expr.strip()
        expr = re.sub(r"'(\\?.)'", lambda m: str(ord(bytes(m.group(1), "utf-8").decode("unicode_escape"))), expr)
        if not re.fullmatch(r"[\w\s+\-*/%<>&|^~()]*", expr) or not expr:
            raise AsmError(f"bad expression '{expr}'")
        names = set(re.findall(r"\b[A-Za-z_][\w]*\b", expr)) - {"lo", "hi"}
        unknown = names - env.keys()
        if unknown:
            if pass_no == 1:
                return 0
            raise AsmError(f"undefined: {', '.join(sorted(unknown))}")
        scope = dict(env, lo=lambda x: x & 0xFF, hi=lambda x: (x >> 8) & 0xFF)
        try:
            return int(eval(expr.replace("/", "//"), {"__builtins__": {}}, scope))
        except Exception as e:                              # noqa: BLE001
            raise AsmError(f"cannot evaluate '{expr}': {e}") from None

    def _encode(self, op, args, env, pass_no):
        ins = next((i for i in self.insns if i["name"] == op), None)
        if ins is None:
            raise AsmError(f"unknown instruction '{op}'")
        errors = []
        for form in ins["forms"]:
            toks = self._syntax(form["syntax"])
            if len(toks) != len(args):
                continue
            try:
                f = self.formats[form["format"]]
                vals = dict(form.get("set", {}))
                for tok, arg in zip(toks, args):
                    v = self._operand(tok, arg, f, env, pass_no)
                    vals.update(zip(FIELD_FOR[tok], v if isinstance(v, tuple) else (v,)))
                return f.encode(vals)
            except AsmError as e:
                errors.append(str(e))
        raise AsmError(f"'{op} {', '.join(args)}': " + ("; ".join(errors) or "wrong number of operands"))

    def _operand(self, tok, arg, f, env, pass_no):
        reg = re.fullmatch(r"r(\d+)", arg.lower())
        if tok in ("rd", "rs"):
            if not reg or int(reg.group(1)) >= self.isa["registers"]:
                raise AsmError(f"'{arg}' is not a register")
            return int(reg.group(1))
        if tok == "[rs+k]":                                 # [rN] or [rN + offset]
            m = re.fullmatch(r"\[\s*r(\d+)\s*(?:\+(.+))?\]", arg.strip(), re.I)
            if not m or int(m.group(1)) >= self.isa["registers"]:
                raise AsmError(f"'{arg}' is not [register] or [register+offset]")
            k = self._eval(m.group(2), env, pass_no) if m.group(2) else 0
            if not 0 <= k < 1 << f.width("k"):
                raise AsmError(f"offset {k} out of range 0..{(1 << f.width('k')) - 1}")
            return int(m.group(1)), k
        if tok == "cond":
            if arg.lower() not in self.cond:
                raise AsmError(f"'{arg}' is not a condition")
            return self.cond[arg.lower()]
        if reg:
            raise AsmError(f"'{arg}' is a register, expected a value")
        v = self._eval(arg, env, pass_no)
        if tok == "target":
            if not 0 <= v < 1 << f.width("t"):
                raise AsmError(f"jump target {v} out of range")
            return v
        if not -128 <= v <= 255:                            # imm: 8 bits, signed or unsigned
            raise AsmError(f"immediate {v} does not fit 8 bits")
        return v & 0xFF


def write_hex(path, words, size):
    """Write a $readmemh / icebram image of `size` words (unused words are 0)."""
    top = max(words, default=-1)
    if top >= size:
        raise AsmError(f"program needs {top + 1} words, ROM has {size}")
    with open(path, "w") as fh:
        for a in range(size):
            fh.write(f"{words.get(a, 0):04x}\n")
