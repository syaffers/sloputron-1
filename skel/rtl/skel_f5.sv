// F5 skeleton: single-thread two-operand register machine. It runs F1's instruction set
// (see skel_f1.sv) and the same binary, without threads, to separate F1's
// instruction-set advantage from its threading (decision D-003).
//   rfa  16 x 16   register file, read port for rd (1 BRAM)
//   rfb  16 x 16   the same registers again, read port for rs (1 BRAM, writes duplicated)
//
// Pipeline, one instruction per cycle:
//   D  instruction arrives -> register reads, decode, hazard check; a jmp is taken here
//   E  operands arrive -> ALU, data-memory read/write at rs, skip, jal
//   W  register write (ALU result, or the loaded word) on the FALLING clock edge
// The next fetch address is computed in the same cycle from the D and E stages and sent
// straight to the ROM, as in J1, so there is no separate fetch stage.
//
// Hazards. Because W writes at mid-cycle, the instruction two behind a writer already reads
// the new value. The only case left is an instruction that reads a register written by
// the instruction directly before it:
//   FWD = 1  the ALU result is forwarded from W into E (a 2:1 mux on each operand). A load
//            followed directly by a use of its result stalls one cycle.
//   FWD = 0  every such pair stalls one cycle (no forwarding mux).
// Branch costs: jmp none; a taken skip or a jal discards the instruction in D (1 cycle).
`default_nettype none
module skel_f5 #(parameter bit FWD = 1) (
    input  wire         clk,
    output wire  [10:0] iaddr,
    input  wire  [15:0] insn,
    output wire  [7:0]  daddr,
    input  wire  [15:0] drd,
    output wire         dwe,
    output wire  [7:0]  dwa,
    output wire  [15:0] dwd
);
    (* ram_style = "block", no_rw_check *) logic [15:0] rfa [16];
    (* ram_style = "block", no_rw_check *) logic [15:0] rfb [16];

    logic        dv = 1'b0;                         // D holds a real instruction (not at reset)
    logic [10:0] pc = 11'h7ff;                      // address of the instruction in D
    wire  [10:0] pc1 = pc + 1'b1;

    // ---- E-stage state, written by D ---------------------------------------------------
    logic [15:0] xd, xs;                            // register-file output registers
    logic [2:0]  e_op  = '0;
    logic [1:0]  e_src = '0;                        // s = 0 rs, 1 sext(i), 2 {i, rd[7:0]}, 3 PC+1
    logic        e_we = 0, e_ld = 0, e_st = 0, e_sk = 0, e_jal = 0;
    logic        fwd_d = 0, fwd_s = 0;              // take rd / rs from W instead of the RF
    logic [1:0]  e_cc  = '0;
    logic [3:0]  e_rd  = '0;
    logic [7:0]  e_imm = '0;
    logic [10:0] e_pc1 = '0;

    // ---- W-stage state ----------------------------------------------------------------
    logic [15:0] y3  = '0;
    logic        we3 = 0, ld3 = 0;
    logic [3:0]  rd3 = '0;

    // ---- E: execute -------------------------------------------------------------------
    wire [15:0] xdf = fwd_d ? y3 : xd;
    wire [15:0] xsf = fwd_s ? y3 : xs;
    logic [15:0] s;
    always_comb case (e_src)
        2'd0: s = xsf;
        2'd1: s = {{8{e_imm[7]}}, e_imm};
        2'd2: s = {e_imm, xdf[7:0]};
        default: s = {5'd0, e_pc1};
    endcase
    wire [15:0] y;
    skel_alu alu (.op(e_op), .x(xdf), .s, .y);
    wire c;
    skel_cond cnd (.v(xdf), .cc(e_cc), .t(c));
    wire kill = e_jal | (e_sk & c);                 // discard the instruction in D

    assign daddr = xsf[7:0];
    assign dwe   = e_st;
    assign dwa   = xsf[7:0];
    assign dwd   = xdf;

    // ---- D: decode, hazard check, next fetch address ----------------------------------
    wire [3:0] cls   = insn[15:12];
    wire       jmp   = insn[15:13] == 3'b111;
    wire       use_d = !(cls == 4'd9 || cls == 4'd13 || jmp);            // all but ld, jal, jmp
    wire       use_s = insn[15] && !(cls == 4'd11 || cls == 4'd12 || jmp); // alu-reg, ld, st, jal
    wire       hit_d = use_d && e_rd == insn[11:8];
    wire       hit_s = use_s && e_rd == insn[7:4];
    wire       stall = dv && !kill && e_we && (FWD ? e_ld : 1'b1) && (hit_d || hit_s);
    wire       v     = dv && !kill && !stall;

    assign iaddr = e_jal ? xsf[10:0] : stall ? pc : (v && jmp) ? insn[10:0] : pc1;

    always_ff @(posedge clk) begin
        dv    <= 1'b1;
        pc    <= iaddr;
        xd    <= rfa[insn[11:8]];
        xs    <= rfb[insn[7:4]];
        e_op  <= !insn[15] ? insn[14:12] : cls == 4'd8 ? insn[2:0] : 3'd5;
        e_src <= !insn[15] ? 2'd1 : cls == 4'd8 ? 2'd0 : cls == 4'd11 ? 2'd2 : 2'd3;
        e_we  <= v & (!insn[15] | cls == 4'd8 | cls == 4'd9 | cls == 4'd11 | cls == 4'd13);
        e_ld  <= v & cls == 4'd9;
        e_st  <= v & cls == 4'd10;
        e_sk  <= v & cls == 4'd12;
        e_jal <= v & cls == 4'd13;
        fwd_d <= FWD && e_we && !e_ld && hit_d;
        fwd_s <= FWD && e_we && !e_ld && hit_s;
        e_cc  <= insn[1:0];
        e_rd  <= insn[11:8];
        e_imm <= insn[7:0];
        e_pc1 <= pc1;
        y3    <= y;
        we3   <= e_we;
        ld3   <= e_ld;
        rd3   <= e_rd;
    end

    // ---- W: register write, falling edge ----------------------------------------------
    wire [15:0] wd = ld3 ? drd : y3;
    always_ff @(negedge clk) if (we3) begin
        rfa[rd3] <= wd;
        rfb[rd3] <= wd;
    end
endmodule
