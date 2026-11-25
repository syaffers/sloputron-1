# sloputron-1 instruction set, version 0.3 (draft)

*Generated from `isa/isa.toml` by `isa/gen.py`. Edit the TOML, then run `make isa`.*

A 16-bit, two-operand register instruction set for a 4-thread barrel processor (D-006).
Every instruction is one 16-bit word. Each thread has its own 16 registers, PC and carry
flag. Instructions are fetched from a word-addressed program ROM, and data is accessed
with word loads and stores to a separate data space (a Harvard layout).

0.3 is the instruction set measured in Phase 3 as "v3" (`docs/phase3/benchmarks.md`). It is
the two-operand set from the Phase 2 skeletons plus a carry flag, `cmp`, 8 skip
conditions, wide data addresses and a thread number in r15. Nothing is final: changes are
proposed with measurements and recorded as decisions.

Word: 16 bits. Registers: r0–r15 per thread. Threads: 4. PC: 11 bits (4 KB of program). Data addresses: 12 bits (4096 words).

## Execution model

- **Threads.** 4 threads issue in strict rotation, one instruction per clock each. A
  thread's next instruction starts only after its previous one has finished, so there are
  no hazards, no delay slots and no branch penalty. One thread runs at a quarter of the
  clock.
- **Start-up.** At configuration every thread starts at address 0 with C = 0 and r15 =
  its thread number (0–3). The other registers start undefined, and software must set them
  before use. A thread separates itself from the others by testing r15.
- **Data accesses** are 16-bit words at the address in rs (the low `data_bits` bits).
  There are no byte loads.
- **Carry flag C.** `add` and `sub` set it, in both the register and immediate forms, and
  so does `cmp`. After `add`, C = carry out. After `sub` or `cmp`, C = 1 when rd ≥ rs or
  imm, unsigned (no borrow). Every other instruction leaves C unchanged. `skip cc` and
  `skip cs` test it.
- **Immediates** are 8 bits, sign-extended in the ALU form: `li` loads −128..127. The
  assembler also accepts 128..255 and stores the low 8 bits, so `li r1, 200` loads
  0xFFC8. `ldhi` sets the high byte, so any 16-bit constant is `li` then `ldhi`.
- **Calls.** `jal rd, rs` jumps to the address in rs and saves the return address (PC+1)
  in rd. A return is `jal r0, rN`, which writes the address after the return into r0, so
  r0 is a scratch register by convention.
- **Skips** discard the next instruction when their condition holds. With a `jmp` after
  them they make any conditional branch.

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
| Load | `1001 dddd ssss ----` | rd [11:8], rs [7:4] |
| Store | `1010 dddd ssss ----` | rd [11:8], rs [7:4] |
| Load high byte | `1011 dddd iiii iiii` | rd [11:8], imm8 [7:0] |
| Skip | `1100 dddd ---- -ccc` | rd [11:8], cond [2:0] |
| Jump and link | `1101 dddd ssss ----` | rd [11:8], rs [7:4] |
| Jump | `111- -ttt tttt tttt` | target [10:0] |

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
| `shl` | `rd` | ALU, register | op = 6, rs = 0, w = 0 | rd ← rd << 1 |
| `shr` | `rd` | ALU, register | op = 7, rs = 0, w = 0 | rd ← rd >> 1 (logical) |
| `nop` | `—` | ALU, immediate | op = 3, rd = 0, imm8 = 0 | no effect (or r0, 0) |
| `ld` | `rd, [rs]` | Load | — | rd ← D[rs] |
| `st` | `rd, [rs]` | Store | — | D[rs] ← rd |
| `ldhi` | `rd, imm` | Load high byte | — | rd ← {imm, rd[7:0]} |
| `skip` | `cond, rd` | Skip | — | skip the next instruction if cond (rd is needed only by z, nz, neg, nneg, odd) |
| `skip` | `cond` | Skip | rd = 0 | ″ |
| `jal` | `rd, rs` | Jump and link | — | rd ← PC + 1; PC ← rs |
| `jmp` | `target` | Jump | — | PC ← target |

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
| 6 | `shl` | x << 1 | unchanged |
| 7 | `shr` | x >> 1 (logical) | unchanged |

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

Measured proposals for later versions, not part of 0.3:
- A 12-bit PC. The 11-bit PC limits programs to 4 KB, while F1 leaves up to 6 KB of BRAM
  for code.
- Unrolled kernels against code size (D-002's secondary metric).
- A multiply step or shift-by-N, if mul16 or crc16 pay for its cells.
- Load/store with an offset, if sort or memcpy pay for the adder.
- Generated customasm rules and C decode tables (planned in CLAUDE.md). customasm is not in
  the pinned toolchain, so the assembler is `isa/asm.py`, driven by this file.
