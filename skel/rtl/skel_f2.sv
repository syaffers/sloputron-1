// F2 skeleton: single-thread stack machine, J1 lineage, stacks in BRAM (rtl/lib/stack_bram).
// One instruction per cycle, no pipeline hazards, no branch penalty: as in J1, the next PC is
// computed in the same cycle and sent straight to the ROM.
//
// Instruction set (shared with F4; provisional, Phase 3 designs the real one):
//   1 iiiiiiiiiiiiiii   literal: push zero-extended 15-bit value
//   000 x tttttttttttt  jump to t (11 bits used)
//   001 x tttttttttttt  0branch: pop T; jump to t if it was 0
//   010 x tttttttttttt  call: push PC+1 on the return stack; jump to t
//   011 p ssss a b c x rr dd   ALU:
//       p     R -> PC (return)
//       ssss  new T: 0-7 ALU op with x = T, s = N (skel_alu), 8 R, 9 [T], 10-15 T
//       a     T -> N   (write T into the data stack: with dd = +1 a push, with dd = 0 an overwrite)
//       b     T -> R   (write T into the return stack, normally with rr = +1)
//       c     N -> [T] (store N at data address T)
//       rr dd return / data stack pointer change: 00 none, 01 +1, 11 -1
// Data memory reads are speculative: the read address is next cycle's T, so `[T]` is ready
// in one cycle (as J1 does). Rule: no `[T]` load in the instruction right after a store to
// the same address (the BRAM read and write collide).
`default_nettype none
module skel_f2 (
    input  wire         clk,
    output wire  [10:0] iaddr,
    input  wire  [15:0] insn,
    output wire  [7:0]  daddr,
    input  wire  [15:0] drd,
    output wire         dwe,
    output wire  [7:0]  dwa,
    output wire  [15:0] dwd
);
    logic [10:0] pc = '0;            // address of `insn`
    logic [15:0] T  = '0;
    wire  [15:0] N, R;

    wire       is_lit  = insn[15];
    wire       is_jmp  = insn[15:13] == 3'b000;
    wire       is_jz   = insn[15:13] == 3'b001;
    wire       is_call = insn[15:13] == 3'b010;
    wire       is_alu  = insn[15:13] == 3'b011;
    wire [3:0] src     = insn[11:8];
    wire       ret = is_alu & insn[12], t2n = is_alu & insn[7], t2r = is_alu & insn[6];
    wire [1:0] rdel = is_alu ? insn[3:2] : {1'b0, is_call};
    wire [1:0] ddel = is_lit ? 2'b01 : is_jz ? 2'b11 : is_alu ? insn[1:0] : 2'b00;

    wire [15:0] y;
    skel_alu alu (.op(is_jz ? 3'd5 : src[2:0]), .x(T), .s(N), .y);

    logic [15:0] Tn;
    always_comb
        if (is_lit)                 Tn = {1'b0, insn[14:0]};
        else if (is_alu & src[3])   Tn = src[1] ? T : src[0] ? drd : R;
        else if (is_alu | is_jz)    Tn = y;                     // 0branch: T <- N (pass s)
        else                        Tn = T;

    wire [10:0] pc1 = pc + 1'b1;
    wire [10:0] pcn = (is_jmp | is_call | (is_jz & T == 16'd0)) ? insn[10:0]
                    : ret ? R[10:0] : pc1;

    stack_bram #(.W(16), .DEPTH(15)) dstack (.clk, .rd(N), .we(is_lit | t2n), .delta(ddel), .wd(T));
    stack_bram #(.W(16), .DEPTH(15)) rstack (.clk, .rd(R), .we(is_call | t2r), .delta(rdel),
                                             .wd(is_call ? {5'd0, pc1} : T));

    always_ff @(posedge clk) begin
        pc <= pcn;
        T  <= Tn;
    end

    assign iaddr = pcn;
    assign daddr = Tn[7:0];
    assign dwe   = is_alu & insn[5];
    assign dwa   = T[7:0];
    assign dwd   = N;
endmodule
