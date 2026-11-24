// F1 for the benchmarks: barrel register machine, two-operand register ISA v2 (D-005).
// The datapath is skel/rtl/skel_f1.sv. Changes from it:
//   - skip compares two registers (unsigned < and >=, through the ALU's carry) and has
//     8 conditions;
//   - data addresses are DA bits wide;
//   - r15 of thread t starts as t (BRAM initial contents), so each thread can find its
//     own data region;
//   - PC+2 is computed a stage early, so a taken skip only selects it.
//   pcm  N x 11      thread PCs, read one cycle ahead (1 BRAM)
//   rfa  N*16 x 16   register file, read port for rd (1 BRAM)
//   rfb  N*16 x 16   the same registers again, read port for rs (1 BRAM, writes duplicated)
//
// Instruction set v2 (provisional), two-operand:
//   0 ooo dddd iiiiiiii   rd <- rd op sext(i)       (op: r_alu, x = rd; op 5 = load immediate)
//   1000 dddd ssss xooo   rd <- rd op rs
//   1001 dddd ssss xxxx   rd <- D[rs]
//   1010 dddd ssss xxxx   D[rs] <- rd
//   1011 dddd iiiiiiii    rd <- {i, rd[7:0]}        (load high byte)
//   1100 dddd ssss xccc   skip the next instruction if cond(rd, rs): 0 always, 1 rd == 0,
//                         2 rd != 0, 3 rd < 0, 4 rd >= 0, 5 rd < rs unsigned,
//                         6 rd >= rs unsigned, 7 rd odd
//   1101 dddd ssss xxxx   jal: rd <- PC+1; PC <- rs
//   111x x ttttttttttt    jump to t
// Pipeline, thread t: S0 PC -> ROM read; S1 register reads, decode; S2 ALU, data access at
// rs, next PC written back; S3 register write. N >= 4; no hazards or branch penalty.
`default_nettype none
module r_f1 #(
    parameter int  N  = 4,
    parameter int  DA = 8,                          // data address bits
    localparam int TB = $clog2(N)
) (
    input  wire          clk,
    output wire  [10:0]  iaddr,
    input  wire  [15:0]  insn,
    output wire  [DA-1:0] daddr,
    input  wire  [15:0]  drd,
    output wire          dwe,
    output wire  [DA-1:0] dwa,
    output wire  [15:0]  dwd
);
    (* ram_style = "block", no_rw_check *) logic [10:0] pcm [N];
    (* ram_style = "block", no_rw_check *) logic [15:0] rfa [N * 16];
    (* ram_style = "block", no_rw_check *) logic [15:0] rfb [N * 16];
    initial for (int k = 0; k < N; k++) begin
        pcm[k] = '0;
        rfa[k * 16 + 15] = 16'(k);
        rfb[k * 16 + 15] = 16'(k);
    end

    logic [TB-1:0] th = '0;
    wire  [TB-1:0] thn = th + 1'b1;
    logic [10:0]   q;                               // pcm[th] (BRAM output register)

    // ---- S0 ---------------------------------------------------------------------------
    logic [TB-1:0] th1;
    logic [10:0]   pc1, pc2;                        // PC+1, PC+2
    always_ff @(posedge clk) begin
        q   <= pcm[thn];
        th  <= thn;
        th1 <= th;
        pc1 <= q + 11'd1;
        pc2 <= q + 11'd2;
    end
    assign iaddr = q;

    // ---- S1: decode, register reads -----------------------------------------------------
    logic [TB-1:0] th2;
    logic [15:0]   xd, xs;
    logic [2:0]    op2, cc2;
    logic [1:0]    src2;                            // s = 0 rs, 1 sext(i), 2 {i, rd[7:0]}, 3 PC+1
    logic          we2, ld2, st2, sk2, jal2, jmp2;
    logic [3:0]    rd2;
    logic [10:0]   ins2, pc12, pc22;
    wire  [3:0]    cls = insn[15:12];
    always_ff @(posedge clk) begin
        xd   <= rfa[{th1, insn[11:8]}];
        xs   <= rfb[{th1, insn[7:4]}];
        th2  <= th1;
        op2  <= !insn[15] ? insn[14:12] : cls == 4'd8 ? insn[2:0] : cls == 4'd12 ? 3'd1 : 3'd5;
        src2 <= !insn[15] ? 2'd1 : (cls == 4'd8 || cls == 4'd12) ? 2'd0 : cls == 4'd11 ? 2'd2 : 2'd3;
        we2  <= !insn[15] | cls == 4'd8 | cls == 4'd9 | cls == 4'd11 | cls == 4'd13;
        ld2  <= cls == 4'd9;
        st2  <= cls == 4'd10;
        sk2  <= cls == 4'd12;
        jal2 <= cls == 4'd13;
        jmp2 <= insn[15:13] == 3'b111;
        cc2  <= insn[2:0];
        rd2  <= insn[11:8];
        ins2 <= insn[10:0];
        pc12 <= pc1;
        pc22 <= pc2;
    end

    // ---- S2: execute ------------------------------------------------------------------
    logic [15:0] s;
    always_comb case (src2)
        2'd0: s = xs;
        2'd1: s = {{8{ins2[7]}}, ins2[7:0]};
        2'd2: s = {ins2[7:0], xd[7:0]};
        default: s = {5'd0, pc12};
    endcase
    wire [15:0] y;
    wire        co;
    r_alu alu (.op(op2), .x(xd), .s, .y, .co);
    wire c;
    r_cond cnd (.v(xd), .co, .cc(cc2), .t(c));
    wire [10:0] pcn = jmp2 ? ins2 : jal2 ? xs[10:0] : (sk2 & c) ? pc22 : pc12;
    always_ff @(posedge clk) pcm[th2] <= pcn;

    assign daddr = xs[DA-1:0];
    assign dwe   = st2;
    assign dwa   = xs[DA-1:0];
    assign dwd   = xd;

    // ---- S3: register write -----------------------------------------------------------
    logic [TB-1:0] th3;
    logic [15:0]   y3;
    logic          we3, ld3;
    logic [3:0]    rd3;
    always_ff @(posedge clk) begin
        th3 <= th2;
        y3  <= y;
        we3 <= we2;
        ld3 <= ld2;
        rd3 <= rd2;
    end
    wire [15:0] wd = ld3 ? drd : y3;
    always_ff @(posedge clk) if (we3) begin
        rfa[{th3, rd3}] <= wd;
        rfb[{th3, rd3}] <= wd;
    end
endmodule
