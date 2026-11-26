# Phase 3 — The C ISS and lockstep against the RTL

Two pieces, both planned in CLAUDE.md since Phase 0:
- **`iss/`**, a C99 instruction-set simulator of the board, which counts cycles;
- **`sim/lockstep_tb.sv`**, which runs the CPU RTL in Verilator and checks every
  instruction it finishes against the simulator.

## The ISS (`iss/`)

| File | What it is |
|---|---|
| `iss.h`, `iss.c` | the simulator: 4-thread barrel, ROM, RAM, I/O hooks, one call per instruction |
| `isa_gen.h` | decode constants, generated from `isa/isa.toml` by `isa/gen.py` (the C decode tables of the plan) |
| `main.c` | `slp-iss`, the command line (`make iss` → `build/iss/slp-iss`) |
| `dpi.c` | DPI-C glue for the lockstep testbench |
| `random_rom.py` | random ROMs for the lockstep test |
| `test_iss.py` | `make iss-test` |

```
build/iss/slp-iss --rx "hello" build/programs/demo.hex          # board: prints the UART output
build/iss/slp-iss --flat DATA.hex --expect EXP.hex KERNEL.hex   # benchmark harness memory
build/iss/slp-iss --trace ...                                   # every instruction to stderr
```

**What it models:**
- **Clocks.** The barrel finishes one instruction per clock, the threads in turn. A skipped
  instruction is never fetched, so it takes no clock. So the simulator's instruction count
  is the clock count.
- **Board memory map:**
  - RAM is 1024 words, at addresses with bit 11 clear (bits 9..0);
  - I/O is at addresses with bit 11 set.

  The UART on the command line is instantaneous: the transmitter is never busy, and a
  received byte waits until it is read.
- **The flat map** is the benchmark harness: 4,096 words of RAM, and a store to 0xFFF
  marks a thread done.
- **Every 16-bit word decodes exactly as `rtl/core/f1_core.sv` decodes it,** including
  the encodings the spec reserves:
  - jump condition 3 jumps;
  - the immediate-form shifts shift in 0 and set C;
  - in the register-form shifts, rs bit 0 alone selects `rcl`/`rcr`.

**Speed:** about 18 million instructions per second on the aarch64 board host. The Python
ISS (`isa/iss.py`) does about 0.18 million.

**Checks (`make iss-test`):**
- The demo prints its banner and echo, byte for byte like the Python ISS.
- Every benchmark kernel and the hazard test, with the ISA 1.0 extensions (rolled and
  unrolled, 10 runs), leaves exactly the memory image the reference interpreter expects.
- Each takes 4 clocks per instruction of one copy. The RTL benchmark harness counts
  exactly 2 more, its pipeline fill. For example, crc16: ISS 42,892, RTL 42,894.

## The retirement port

`f1_core` has an RVFI-style output, named `rvfi_*` after RISC-V's formal interface. Each
clock it reports the instruction that finished in stage S3:
- its thread, PC and instruction word;
- the next PC, and the carry flag after it;
- its register write;
- its data access: address, read data, write data.

The board design leaves it unconnected, so synthesis removes it. The sweep for this change
measured 482 LC, against 481 before; the netlist holds no new cells, so the 1 LC is
placement packing.

## Lockstep (`make sim-lockstep`)

Each run puts one program into the whole board design (`rtl/board/sloputron.sv`, 12 MHz)
and gives it its own ISS through DPI-C.
- **The host model** sends random bytes to the UART with random gaps, all the time.
- **Every retirement** goes to `iss_retire()`. The ISS executes the same thread's next
  instruction and compares every field.
- **Rotation.** After the start-up hold there must be one retirement per clock, each from
  the next thread in rotation.
- **What the RTL decides:**
  - The first thread to retire sets the ISS's starting turn.
  - The value of an I/O load comes from the RTL, because UART status depends on bit
    timing.
- **RAM loads are not taken from the RTL; they are checked.**

**Programs, about 199,000 instructions each:**

| Program | What it is |
|---|---|
| `demo` | the board demo: banner, LED counter, crc, echo |
| `stress` | the clock-sweep test, with every ISA 1.0 extension |
| `rand0`–`rand3` | uniformly random words: every encoding, the reserved ones too |
| `mix0`–`mix3` | random canonical instructions, weighted towards RAM traffic, carry use and branches |

**Keeping random code moving.** Random code first fell into a 2-word loop within a few
instructions. `random_rom.py` therefore fixes only the control flow:
- every jump and branch goes 1–8 words forward;
- every `jal` goes through r14, which the two words before it set;
- no skip or jump may enter those three words half-way.

Every other bit stays random. Each program then runs through the ROM again and again.
Each one executes 1,100–1,250 distinct instruction words, including loads and stores to
both RAM and I/O.

**Result:** all 10 programs, about 2 million instructions, with 0 mismatches and no idle
clock.

**Do the checks work?** I planted 9 bugs, one at a time, in a copy of `f1_core`. The
lockstep caught every one:

| Planted bug | Caught by |
|---|---|
| reserved jump condition 3 does not jump | rand only |
| immediate-form shifts leave C | rand, mix |
| `rcl`/`rcr` selected by rs bit 1 | rand, mix, stress |
| `jal` saves PC instead of PC + 1 | all 10 |
| `ldhi` keeps rs's low byte instead of rd's | all 10 |
| `cmp` writes rd | all 10 |
| the offset add loses its carry above bit 3 | rand, mix, stress |
| `skip odd` tests bit 1 | rand, mix |
| `sub`'s carry inverted | all 10 |

Three of these bugs are invisible to the board programs and the benchmark kernels, which
never use those encodings. Only the random programs reach them.

## Not covered
- **The UART and I/O registers.** The lockstep takes I/O read data from the RTL. The
  echo tests (`sim/sloputron_tb.sv`, `make uart-test` on the board) cover them instead.
- **The iCE40's block RAM behaviour just after configuration.** Simulation does not model
  it (`board.md`, "The start-up hold").
- **Formal checks.** SymbiYosys is still planned. The retirement port is the interface it
  would use.
