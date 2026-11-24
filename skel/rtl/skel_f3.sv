// F3 skeleton: single-thread accumulator machine, Leros lineage. A (accumulator), AR (data
// address register) and the PC are flip-flops; the 256 registers are one BRAM.
//
// Instruction set (provisional, Phase 3 designs the real one):
//   0000 0 ooo nnnnnnnn   A <- A op R[n]            (op: skel_alu, x = A)
//   0000 1 ooo iiiiiiii   A <- A op sext(i)         (op 5 = load immediate)
//   0001 x xxx nnnnnnnn   R[n] <- A
//   0010 x xxx iiiiiiii   A <- {i, A[7:0]}          (load high byte)
//   0011 ...              AR <- A[7:0]
//   0100 ...              A <- D[AR]
//   0101 ...              D[AR] <- A
//   0110 x xxx nnnnnnnn   jal: R[n] <- PC+1; PC <- A
//   1 cc xx ttttttttttt   branch to t if cond(A, cc): 00 always, 01 A==0, 10 A!=0, 11 A<0
// Pipeline: F (ROM read at PC) -> D (instruction arrives; register-file and data reads) ->
// E (ALU, A and register writes, branch). The two BRAM reads in series need the D stage.
// Hazard choices, made for the smallest datapath (tricks.md T8):
//   - no forwarding: an instruction must not read R[n] right after one that writes R[n],
//     and `A <- D[AR]` must not directly follow `AR <- A`;
//   - taken branches and jal discard the two instructions behind them (2 cycles).
`default_nettype none
module skel_f3 (
    input  wire         clk,
    output wire  [10:0] iaddr,
    input  wire  [15:0] insn,
    output wire  [7:0]  daddr,
    input  wire  [15:0] drd,
    output wire         dwe,
    output wire  [7:0]  dwa,
    output wire  [15:0] dwd
);
    (* ram_style = "block", no_rw_check *) logic [15:0] rf [256];

    logic [10:0] pc   = '0;              // fetch address
    logic        kill = 1'b1;            // instruction in D was fetched behind a taken branch
    logic [15:0] A    = '0;
    logic [7:0]  AR   = '0;

    // ---- E-stage control, decoded in D ---------------------------------------------------
    logic [2:0]  e_op  = '0;
    logic [1:0]  e_src = '0;             // s = 0 R[n], 1 sext(i), 2 {i, A[7:0]}, 3 D[AR]
    logic        e_wa = 0, e_wr = 0, e_war = 0, e_wd = 0, e_jal = 0, e_br = 0;
    logic [1:0]  e_cc  = '0;
    logic [7:0]  e_n   = '0;             // register number / immediate
    logic [10:0] e_tgt = '0, e_pc1 = '0;
    logic [15:0] rq;                     // R[n] (register-file output register)

    // ---- E ----------------------------------------------------------------------------
    logic [15:0] s;
    always_comb case (e_src)
        2'd0: s = rq;
        2'd1: s = {{8{e_n[7]}}, e_n};
        2'd2: s = {e_n, A[7:0]};
        default: s = drd;
    endcase
    wire [15:0] y;
    skel_alu alu (.op(e_op), .x(A), .s, .y);
    wire c;
    skel_cond cnd (.v(A), .cc(e_cc), .t(c));
    wire taken = e_jal | (e_br & c);

    // ---- D: decode --------------------------------------------------------------------
    wire       v   = !kill && !taken;
    wire [3:0] cls = insn[15:12];
    always_ff @(posedge clk) begin
        e_op  <= cls == 4'd0 ? insn[10:8] : 3'd5;
        e_src <= cls == 4'd0 ? {1'b0, insn[11]} : cls == 4'd2 ? 2'd2 : 2'd3;
        e_wa  <= v & (cls == 4'd0 | cls == 4'd2 | cls == 4'd4);
        e_wr  <= v & (cls == 4'd1 | cls == 4'd6);
        e_war <= v & cls == 4'd3;
        e_wd  <= v & cls == 4'd5;
        e_jal <= v & cls == 4'd6;
        e_br  <= v & insn[15];
        e_cc  <= insn[14:13];
        e_n   <= insn[7:0];
        e_tgt <= insn[10:0];
        e_pc1 <= pc;                     // the fetch address is already this insn's PC+1
    end

    always_ff @(posedge clk) begin
        if (e_wr) rf[e_n] <= e_jal ? {5'd0, e_pc1} : A;
        rq <= rf[insn[7:0]];
    end

    always_ff @(posedge clk) begin
        if (e_wa)  A  <= y;
        if (e_war) AR <= A[7:0];
        pc   <= taken ? (e_jal ? A[10:0] : e_tgt) : pc + 1'b1;
        kill <= taken;
    end

    assign iaddr = pc;
    assign daddr = AR;
    assign dwe   = e_wd;
    assign dwa   = AR;
    assign dwd   = A;
endmodule
