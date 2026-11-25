# sloputron-1 instruction set, version 1.0 (final for F1, D-008)

*Generated from `isa/isa.toml` by `isa/gen.py`. Edit the TOML, then run `make isa`.*

A 16-bit, two-operand register instruction set for a 4-thread barrel processor (D-006).
Every instruction is one 16-bit word. Each thread has its own 16 registers, PC and carry
flag. Instructions are fetched from a word-addressed program ROM, and data is accessed
with word loads and stores to a separate data space (a Harvard layout).

0.3 was the set measured in Phase 3 as "v3" (`docs/phase3/benchmarks.md`): the two-operand
set from the Phase 2 skeletons plus a carry flag, `cmp`, 8 skip conditions, wide data
addresses and a thread number in r15. 1.0 (D-008) is the set for F1 alone. It adds three
measured extensions, each in encoding space that 0.3 left unused:
- branch on C (`bcc`, `bcs`) in the jump's spare bits;
- carry shifts: `shl`/`shr` set C to the bit shifted out, and `rcl`/`rcr` shift C in;
- a 4-bit offset on `ld` and `st`.

Together they give 1.23× the work per clock per cell on the D-002 kernels. 0.3 programs
assemble unchanged; only code that kept C across a shift behaves differently.

Word: 16 bits. Registers: r0–r15 per thread. Threads: 4. PC: 11 bits (4 KB of program). Data addresses: 12 bits (4096 words).

## Execution model

- **Threads.** 4 threads issue in strict rotation, one instruction per clock each. A
  thread's next instruction starts only after its previous one has finished, so there are
  no hazards, no delay slots and no branch penalty. One thread runs at a quarter of the
  clock.
- **Start-up.** At configuration every thread starts at address 0 with C = 0 and r15 =
  its thread number (0–3). The other registers start undefined, and software must set them
  before use. A thread separates itself from the others by testing r15.
- **Data accesses** are 16-bit words at the address rs + k, where k is a 4-bit unsigned
  offset (0–15, default 0). The low `data_bits` bits of the sum are used. There are no
  byte loads.
- **Carry flag C.** `add` and `sub` set it, in both the register and immediate forms, and
  so does `cmp`. After `add`, C = carry out. After `sub` or `cmp`, C = 1 when rd ≥ rs or
  imm, unsigned (no borrow). The shifts (`shl`, `shr`, `rcl`, `rcr`) set C to the bit
  shifted out. Every other instruction leaves C unchanged. `skip cc`, `skip cs`, `bcc` and
  `bcs` test it.
- **Shifts through C.** `rcl` and `rcr` shift C in where `shl` and `shr` shift in 0. So
  `shl lo` then `rcl hi` shifts a 32-bit value left, and `shr x` then `skip cc` tests the
  bit that left x.
- **Immediates** are 8 bits, sign-extended in the ALU form: `li` loads −128..127. The
  assembler also accepts 128..255 and stores the low 8 bits, so `li r1, 200` loads
  0xFFC8. `ldhi` sets the high byte, so any 16-bit constant is `li` then `ldhi`.
- **Calls.** `jal rd, rs` jumps to the address in rs and saves the return address (PC+1)
  in rd. A return is `jal r0, rN`, which writes the address after the return into r0, so
  r0 is a scratch register by convention.
- **Branches.** `jmp`, `bcs` and `bcc` take an absolute 11-bit target. `bcs` jumps when C
  is set and `bcc` when it is clear, so `cmp` then `bcc` is a compare-and-branch.
- **Skips** discard the next instruction when their condition holds, at no cost: a skipped
  instruction takes no cycle. A skip and a `jmp` make a branch on any condition.
- **Counted loops.** Count up from −n to 0: `add rN, 1` sets C on the step that reaches 0,
  so `add rN, 1` then `bcc loop` closes a loop in 2 instructions.

## Register conventions

- r15: thread number at start-up. Software may overwrite it.
- r0: scratch. `jal` returns write it, and `nop` is `or r0, 0`.
- Everything else is free. The Phase 3 kernels use r14 for a thread's data-region base.

## Instruction formats

Bit 15 is on the left. Letters are fields, `-` bits are ignored and written as 0.

| Format | Bits 15..0 | Fields |
|---|---|---|
| ALU, immediate | `0ooo dddd iiii iiii` | op [14:12], rd [11:8], imm8 [7:0] |
| ALU, register | `1000 dddd ssss wooo` | rd [11:8], rs [7:4], w (1 = no write) [3], op [2:0] |
| Load | `1001 dddd ssss kkkk` | rd [11:8], rs [7:4], offset [3:0] |
| Store | `1010 dddd ssss kkkk` | rd [11:8], rs [7:4], offset [3:0] |
| Load high byte | `1011 dddd iiii iiii` | rd [11:8], imm8 [7:0] |
| Skip | `1100 dddd ---- -ccc` | rd [11:8], cond [2:0] |
| Jump and link | `1101 dddd ssss ----` | rd [11:8], rs [7:4] |
| Jump / branch | `111b bttt tttt tttt` | branch (0 always, 1 C set, 2 C clear) [12:11], target [10:0] |

## Instructions

| Mnemonic | Operands | Format | Fixed fields | Operation |
|---|---|---|---|---|
| `add` | `rd, rs` | ALU, register | op = 0, w = 0 | rd ← rd + rs / sext(imm); C ← carry |
| `add` | `rd, imm` | ALU, immediate | op = 0 | ″ |
| `sub` | `rd, rs` | ALU, register | op = 1, w = 0 | rd ← rd − rs / sext(imm); C ← no borrow |
| `sub` | `rd, imm` | ALU, immediate | op = 1 | ″ |
| `cmp` | `rd, rs` | ALU, register | op = 1, w = 1 | C ← rd ≥ rs (unsigned); rd unchanged |
| `and` | `rd, rs` | ALU, register | op = 2, w = 0 | rd ← rd & rs / sext(imm) |
| `and` | `rd, imm` | ALU, immediate | op = 2 | ″ |
| `or` | `rd, rs` | ALU, register | op = 3, w = 0 | rd ← rd \| rs / sext(imm) |
| `or` | `rd, imm` | ALU, immediate | op = 3 | ″ |
| `xor` | `rd, rs` | ALU, register | op = 4, w = 0 | rd ← rd ^ rs / sext(imm) |
| `xor` | `rd, imm` | ALU, immediate | op = 4 | ″ |
| `mov` | `rd, rs` | ALU, register | op = 5, w = 0 | rd ← rs |
| `li` | `rd, imm` | ALU, immediate | op = 5 | rd ← sext(imm) |
| `shl` | `rd` | ALU, register | op = 6, rs = 0, w = 0 | rd ← rd << 1; C ← old bit 15 |
| `shr` | `rd` | ALU, register | op = 7, rs = 0, w = 0 | rd ← rd >> 1 (logical); C ← old bit 0 |
| `rcl` | `rd` | ALU, register | op = 6, rs = 1, w = 0 | rd ← {rd[14:0], C}; C ← old bit 15 |
| `rcr` | `rd` | ALU, register | op = 7, rs = 1, w = 0 | rd ← {C, rd[15:1]}; C ← old bit 0 |
| `nop` | `—` | ALU, immediate | op = 3, rd = 0, imm8 = 0 | no effect (or r0, 0) |
| `ld` | `rd, [rs+k]` | Load | — | rd ← D[rs + k]; k = 0–15, written [rs] or [rs+k] |
| `st` | `rd, [rs+k]` | Store | — | D[rs + k] ← rd |
| `ldhi` | `rd, imm` | Load high byte | — | rd ← {imm, rd[7:0]} |
| `skip` | `cond, rd` | Skip | — | skip the next instruction if cond (rd is needed only by z, nz, neg, nneg, odd) |
| `skip` | `cond` | Skip | rd = 0 | ″ |
| `jal` | `rd, rs` | Jump and link | — | rd ← PC + 1; PC ← rs |
| `jmp` | `target` | Jump / branch | branch = 0 | PC ← target |
| `bcs` | `target` | Jump / branch | branch = 1 | if C: PC ← target |
| `bcc` | `target` | Jump / branch | branch = 2 | if not C: PC ← target |

## ALU operations (field op)

x is rd. s is rs (register form) or the sign-extended imm8 (immediate form).

| op | Name | Result | Carry flag C |
|---:|---|---|---|
| 0 | `add` | x + s | carry out |
| 1 | `sub` | x − s | 1 if x ≥ s (unsigned) |
| 2 | `and` | x & s | unchanged |
| 3 | `or` | x \| s | unchanged |
| 4 | `xor` | x ^ s | unchanged |
| 5 | `pass` | s | unchanged |
| 6 | `shl` | x << 1, bit 0 = 0 (shl) or C (rcl) | old bit 15 |
| 7 | `shr` | x >> 1, bit 15 = 0 (shr) or C (rcr) | old bit 0 |

## Skip conditions (field cond)

| cond | Name | Skips the next instruction when |
|---:|---|---|
| 0 | `al` | always |
| 1 | `z` | rd = 0 |
| 2 | `nz` | rd ≠ 0 |
| 3 | `neg` | rd < 0 (bit 15 set) |
| 4 | `nneg` | rd ≥ 0 (bit 15 clear) |
| 5 | `cc` | C clear (after cmp: rd < rs, unsigned) |
| 6 | `cs` | C set (after cmp: rd ≥ rs, unsigned) |
| 7 | `odd` | rd bit 0 set |

## Data address space

Data addresses are 12 bits (4096 words). RAM starts at 0 and its size is set by the board
design. The I/O region is 0x800–0xFFF and is decoded from address bit 11 and bits 1..0
(D-007), so its other addresses repeat the four registers below and are reserved.

| Address | Name | Access | Meaning |
|---|---|---|---|
| 0xffc | `UART_TX` | W | send the low byte; ignored while the transmitter is busy |
| 0xffd | `UART_STATUS` | R | bit 0: transmitter busy; bit 1: received byte waiting |
| 0xffe | `UART_RX` | R | the received byte (bits 7..0); reading clears 'byte waiting' |
| 0xfff | `LED` | W | the 5 LEDs from bits 4..0 |

## Assembler

`isa/asm.py SOURCE.s -o OUT.hex` assembles, and `isa/asm.py --disasm OUT.hex` disassembles. Both read this spec. The syntax is described at the top of `isa/isa.py`:
- labels end in `:`;
- comments start with `;`;
- directives: `.org`, `.word`, `.equ`, `.ascii`;
- expressions may use `lo()`, `hi()` and the I/O names above.

A mnemonic with both a register and an immediate form picks the form from its operand: `add r1, r2` or `add r1, -1`.

## Open items

Settled in D-008 (measurements in `docs/phase3/benchmarks.md`):
- **12-bit PC: no.** The jump's spare bits now hold the branch condition. The board's ROM is
  4 KB (8 BRAMs), and only one BRAM is spare.
- **Multiply step: no.** It writes two registers, and the register file has one write
  port. `rcr` gives mul16 1.52× without it.
- **Shift-by-N: no.** A barrel shifter is 134 cells (`docs/phase2/primitives.md`), +40%.
- **Load/store offset: yes**, in the 4 bits that 0.3 ignored. Rolled loops gain little
  (sort 1.14×); unrolled loops gain most (memcpy 2.4×).
- **Unrolling** is a programming choice, not an ISA feature. The scored kernels stay rolled;
  unrolled versions are reported beside them with their code size.
- **customasm rules: dropped.** customasm is not in the pinned toolchain, and `isa/asm.py`
  reads this file directly. C decode tables come with the C ISS.

Encodings left for later: jump condition 3, the immediate forms of the shifts (op 6 and 7),
and rs values 2–15 in the shift forms.
