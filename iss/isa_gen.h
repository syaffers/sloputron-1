/* sloputron-1 ISA 1.0 constants. Generated from isa/isa.toml by isa/gen.py;
   do not edit. Decode an instruction class with (insn & FMT_x_MASK) == FMT_x_MATCH. */
#ifndef SLP_ISA_GEN_H
#define SLP_ISA_GEN_H

#define ISA_VERSION "1.0"
#define PC_BITS   11
#define DATA_BITS 12
#define THREADS   4
#define REGISTERS 16

#define FMT_ALU_IMM_MASK  0x8000u
#define FMT_ALU_IMM_MATCH 0x0000u
#define FMT_ALU_REG_MASK  0xf000u
#define FMT_ALU_REG_MATCH 0x8000u
#define FMT_LOAD_MASK  0xf000u
#define FMT_LOAD_MATCH 0x9000u
#define FMT_STORE_MASK  0xf000u
#define FMT_STORE_MATCH 0xa000u
#define FMT_LDHI_MASK  0xf000u
#define FMT_LDHI_MATCH 0xb000u
#define FMT_SKIP_MASK  0xf000u
#define FMT_SKIP_MATCH 0xc000u
#define FMT_JAL_MASK  0xf000u
#define FMT_JAL_MATCH 0xd000u
#define FMT_JMP_MASK  0xe000u
#define FMT_JMP_MATCH 0xe000u

#define ALU_ADD 0
#define ALU_SUB 1
#define ALU_AND 2
#define ALU_OR 3
#define ALU_XOR 4
#define ALU_PASS 5
#define ALU_SHL 6
#define ALU_SHR 7

#define CC_AL 0
#define CC_Z 1
#define CC_NZ 2
#define CC_NEG 3
#define CC_NNEG 4
#define CC_CC 5
#define CC_CS 6
#define CC_ODD 7

#define IO_UART_TX 0xffcu
#define IO_UART_STATUS 0xffdu
#define IO_UART_RX 0xffeu
#define IO_LED 0xfffu

#endif
