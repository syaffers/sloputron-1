// sloputron-1 ISA 1.0 constants. Generated from isa/isa.toml by isa/gen.py;
// do not edit. Decode an instruction class with (insn & FMT_x_MASK) == FMT_x_MATCH.
`default_nettype none
/* verilator lint_off UNUSEDPARAM */           // a design uses only some constants
package isa_pkg;
    localparam int PC_BITS   = 11;
    localparam int DATA_BITS = 12;
    localparam int THREADS   = 4;

    localparam logic [15:0] FMT_ALU_IMM_MASK  = 16'h8000;
    localparam logic [15:0] FMT_ALU_IMM_MATCH = 16'h0000;
    localparam logic [15:0] FMT_ALU_REG_MASK  = 16'hf000;
    localparam logic [15:0] FMT_ALU_REG_MATCH = 16'h8000;
    localparam logic [15:0] FMT_LOAD_MASK  = 16'hf000;
    localparam logic [15:0] FMT_LOAD_MATCH = 16'h9000;
    localparam logic [15:0] FMT_STORE_MASK  = 16'hf000;
    localparam logic [15:0] FMT_STORE_MATCH = 16'ha000;
    localparam logic [15:0] FMT_LDHI_MASK  = 16'hf000;
    localparam logic [15:0] FMT_LDHI_MATCH = 16'hb000;
    localparam logic [15:0] FMT_SKIP_MASK  = 16'hf000;
    localparam logic [15:0] FMT_SKIP_MATCH = 16'hc000;
    localparam logic [15:0] FMT_JAL_MASK  = 16'hf000;
    localparam logic [15:0] FMT_JAL_MATCH = 16'hd000;
    localparam logic [15:0] FMT_JMP_MASK  = 16'he000;
    localparam logic [15:0] FMT_JMP_MATCH = 16'he000;

    localparam logic [2:0] ALU_ADD = 3'd0;
    localparam logic [2:0] ALU_SUB = 3'd1;
    localparam logic [2:0] ALU_AND = 3'd2;
    localparam logic [2:0] ALU_OR = 3'd3;
    localparam logic [2:0] ALU_XOR = 3'd4;
    localparam logic [2:0] ALU_PASS = 3'd5;
    localparam logic [2:0] ALU_SHL = 3'd6;
    localparam logic [2:0] ALU_SHR = 3'd7;

    localparam logic [2:0] CC_AL = 3'd0;
    localparam logic [2:0] CC_Z = 3'd1;
    localparam logic [2:0] CC_NZ = 3'd2;
    localparam logic [2:0] CC_NEG = 3'd3;
    localparam logic [2:0] CC_NNEG = 3'd4;
    localparam logic [2:0] CC_CC = 3'd5;
    localparam logic [2:0] CC_CS = 3'd6;
    localparam logic [2:0] CC_ODD = 3'd7;

    localparam logic [11:0] IO_UART_TX = 12'hffc;
    localparam logic [11:0] IO_UART_STATUS = 12'hffd;
    localparam logic [11:0] IO_UART_RX = 12'hffe;
    localparam logic [11:0] IO_LED = 12'hfff;
endpackage
/* verilator lint_on UNUSEDPARAM */
