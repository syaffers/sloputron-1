// sloputron-1 CPU core (D-006): F1, a barrel processor running the sloputron-1 ISA
// (docs/isa/isa.md; decode constants from isa_pkg, generated from isa/isa.toml).
//
// N threads take turns one clock each. Each thread's PC and carry flag and its 16
// registers live in BRAM. Nothing per thread is kept in flip-flops.
//   pcm  N x 12      {C, PC} per thread, read one cycle ahead (1 BRAM)
//   rfa  N*16 x 16   register file, read port for rd (1 BRAM)
//   rfb  N*16 x 16   the same registers again, read port for rs (1 BRAM, writes duplicated)
// At configuration every thread starts at PC 0 with C = 0, and r15 = its thread number.
//
// Pipeline, thread t (one stage per clock; the 4 threads occupy the 4 stages):
//   S0  {C, PC} arrives from pcm -> program ROM read; PC+1 and PC+2 computed
//   S1  instruction arrives -> register reads, decode; bcc/bcs resolved (C came with the PC)
//       (rfb reads rd instead of rs for shl, which the ALU does as rd + rd)
//   S2  operands arrive -> ALU, carry flag, skip condition, data access at rs + k; the
//       next {C, PC} is written back to pcm
//   S3  register write (ALU result, or the loaded word)
// The PC is written at the end of S2 and read for the thread's next turn N-1 cycles after
// S0, so N >= 4. A thread's next instruction starts after its previous one has finished:
// no forwarding, interlocks or branch penalty.
//
// Start-up hold: iCE40 block RAMs read back wrong for a short time after configuration
// (seen on the board 2026-11-24: every thread read r15 as 0). The core therefore commits
// nothing (no PC, register or memory writes) until `run` has been high for STARTUP clocks.
// Only instructions fetched after that are executed, so every thread starts cleanly at
// PC 0. `run` is the PLL's lock signal when the clock comes from the PLL, else 1.
//
// Retirement port (rvfi_*, after RISC-V's RVFI): in S3 every instruction that finishes
// reports its thread, PC, word, next PC and carry, its register write and its data access.
// sim/lockstep_tb.sv checks it against the C ISS (iss/). Nothing on the board reads it,
// so synthesis removes it.
//
// ISA 1.0 (D-008) is 0.3 plus branch on C, carry shifts and a load/store offset. This is
// bench/rtl/r_f1.sv with X = 7 (all three), with the decode taken from isa_pkg, a load
// strobe (dre) for I/O reads that have side effects, and the start-up hold.
`default_nettype none
module f1_core
    import isa_pkg::*;
#(
    parameter int  N  = THREADS,
    parameter int  DA = DATA_BITS,
    parameter int  STARTUP = 1024,              // clocks before the first instruction (a power of 2)
    localparam int TB = $clog2(N)
) (
    input  wire           clk,
    input  wire           run,                  // 0 holds the start-up count at zero
    output wire  [10:0]   iaddr,
    input  wire  [15:0]   insn,                 // rom[iaddr], one cycle later
    output wire  [DA-1:0] daddr,
    output wire           dre,                  // a load reads daddr this cycle
    input  wire  [15:0]   drd,                  // D[daddr], one cycle later
    output wire           dwe,
    output wire  [DA-1:0] dwa,
    output wire  [15:0]   dwd,
    // retirement port: one instruction per clock once the start-up hold is over
    output wire           rvfi_valid,
    output wire  [TB-1:0] rvfi_thread,
    output wire  [10:0]   rvfi_pc,
    output wire  [15:0]   rvfi_insn,
    output wire  [10:0]   rvfi_pc_next,
    output wire           rvfi_c,               // carry flag after the instruction
    output wire           rvfi_rd_we,
    output wire  [3:0]    rvfi_rd,
    output wire  [15:0]   rvfi_rd_wdata,
    output wire           rvfi_mem_re,
    output wire           rvfi_mem_we,
    output wire  [DA-1:0] rvfi_mem_addr,
    output wire  [15:0]   rvfi_mem_rdata,
    output wire  [15:0]   rvfi_mem_wdata
);
    (* ram_style = "block", no_rw_check *) logic [11:0] pcm [N];      // {C, PC}
    (* ram_style = "block", no_rw_check *) logic [15:0] rfa [N * 16];
    (* ram_style = "block", no_rw_check *) logic [15:0] rfb [N * 16];
    initial for (int k = 0; k < N; k++) begin
        pcm[k] = '0;
        rfa[k * 16 + 15] = 16'(k);
        rfb[k * 16 + 15] = 16'(k);
    end

    // ---- start-up hold: g0..g3 mark instructions fetched after it, per stage ----------
    logic [$clog2(STARTUP)-1:0] wait_n = '0;
    logic go = 1'b0, g0 = 1'b0, g1 = 1'b0, g2 = 1'b0, g3 = 1'b0;
    always_ff @(posedge clk) begin
        if (!run)    wait_n <= '0;
        else if (!go) wait_n <= wait_n + 1'b1;
        if (&wait_n) go <= 1'b1;
        g0 <= go;
        g1 <= g0;
        g2 <= g1;
        g3 <= g2;
    end

    logic [TB-1:0] th = '0;
    wire  [TB-1:0] thn = th + 1'b1;
    logic [11:0]   q;                               // pcm[th] (BRAM output register)

    // ---- S0 ---------------------------------------------------------------------------
    logic [TB-1:0] th1;
    logic [10:0]   pc1, pc2;                        // PC+1, PC+2
    logic          cf1;
    always_ff @(posedge clk) begin
        q   <= pcm[thn];
        th  <= thn;
        th1 <= th;
        pc1 <= q[10:0] + 11'd1;
        pc2 <= q[10:0] + 11'd2;
        cf1 <= q[11];
    end
    assign iaddr = q[10:0];

    // ---- S1: decode, register reads -----------------------------------------------------
    wire is_alui = (insn & FMT_ALU_IMM_MASK) == FMT_ALU_IMM_MATCH;
    wire is_alur = (insn & FMT_ALU_REG_MASK) == FMT_ALU_REG_MATCH;
    wire is_ld   = (insn & FMT_LOAD_MASK)    == FMT_LOAD_MATCH;
    wire is_st   = (insn & FMT_STORE_MASK)   == FMT_STORE_MATCH;
    wire is_ldhi = (insn & FMT_LDHI_MASK)    == FMT_LDHI_MATCH;
    wire is_sk   = (insn & FMT_SKIP_MASK)    == FMT_SKIP_MATCH;
    wire is_jal  = (insn & FMT_JAL_MASK)     == FMT_JAL_MATCH;
    wire is_jmp  = (insn & FMT_JMP_MASK)     == FMT_JMP_MATCH;
    wire [2:0] op = is_alui ? insn[14:12] : is_alur ? insn[2:0] : ALU_PASS;
    wire       is_alu = is_alui | is_alur;
    // jump bits 12..11: 0 always (jmp), 1 if C (bcs), 2 if not C (bcc); 3 is reserved (jumps)
    wire       jump = is_jmp & (insn[12:11] == 2'd0 | (insn[11] & cf1) | (insn[12] & !cf1));
    wire       shl  = op == ALU_SHL;               // op is PASS outside the ALU formats
    // rs port: rd for shl (both forms); the immediate form reads no rs, so it may read rd too
    wire [3:0] ra_s = (insn[15] && !(is_alur && shl)) ? insn[7:4] : insn[11:8];

    logic [TB-1:0] th2;
    logic [15:0]   xd, xs;
    logic [2:0]    cc2;
    logic [1:0]    src2;                            // s = 0 rs, 1 sext(i), 2 {i, rd[7:0]}, 3 PC+1
    logic          m2, inv2, cin2, shr2;            // ALU controls, see f1_alu
    logic [1:0]    k2;
    logic          we2, ld2, st2, sk2, jal2, jmp2, setc2, cf2;
    logic [3:0]    off2;
    logic [3:0]    rd2;
    logic [10:0]   ins2, pc12, pc22;
    always_ff @(posedge clk) begin
        xd    <= rfa[{th1, insn[11:8]}];
        xs    <= rfb[{th1, ra_s}];
        th2   <= th1;
        src2  <= (is_alui & !shl) ? 2'd1 : is_alu ? 2'd0 : is_ldhi ? 2'd2 : 2'd3;
        we2   <= is_alui | (is_alur & !insn[3]) | is_ld | is_ldhi | is_jal;
        m2    <= !(op == ALU_ADD || op == ALU_SUB || op == ALU_SHL);
        k2    <= op == ALU_AND ? 2'd1 : op == ALU_OR ? 2'd2 : op == ALU_XOR ? 2'd3 : 2'd0;
        inv2  <= op == ALU_SUB;
        // carry in: 1 for sub; C for rcl and rcr (rs bit 0), which rcr shifts into bit 15
        cin2  <= op == ALU_SUB || (op[2:1] == 2'b11 && is_alur && insn[4] && cf1);
        shr2  <= op == ALU_SHR;
        setc2 <= op == ALU_ADD || op == ALU_SUB || op == ALU_SHL;
        off2  <= insn[3:0];                         // ld / st offset
        ld2   <= is_ld;
        st2   <= is_st;
        sk2   <= is_sk;
        jal2  <= is_jal;
        jmp2  <= jump;
        cc2   <= insn[2:0];
        rd2   <= insn[11:8];
        ins2  <= insn[10:0];
        pc12  <= pc1;
        pc22  <= pc2;
        cf2   <= cf1;
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
    f1_alu alu (.m(m2), .k(k2), .inv(inv2), .cin(cin2), .shr(shr2), .x(xd), .s, .y, .co);
    wire c;
    f1_cond cnd (.v(xd), .cf(cf2), .cc(cc2), .t(c));
    wire [10:0] pcn = jmp2 ? ins2 : jal2 ? xs[10:0] : (sk2 & c) ? pc22 : pc12;
    wire        cfn = setc2 ? co : shr2 ? xd[0] : cf2;
    always_ff @(posedge clk) if (g2) pcm[th2] <= {cfn, pcn};

    wire [DA-1:0] ea = xs[DA-1:0] + DA'(off2);       // rs + k
    assign daddr = ea;
    assign dre   = ld2 & g2;
    assign dwe   = st2 & g2;
    assign dwa   = ea;
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

    // ---- retirement port (verification only) --------------------------------------------
    logic [10:0]   pcx1, pcx2, pcx3, pcn3;
    logic [15:0]   insn2, insn3, xd3;
    logic          c3, st3;
    logic [DA-1:0] ea3;
    always_ff @(posedge clk) begin
        pcx1  <= q[10:0];
        pcx2  <= pcx1;
        insn2 <= insn;
        pcx3  <= pcx2;
        insn3 <= insn2;
        pcn3  <= pcn;
        c3    <= cfn;
        st3   <= st2;
        ea3   <= ea;
        xd3   <= xd;
    end
    assign rvfi_valid     = g3;
    assign rvfi_thread    = th3;
    assign rvfi_pc        = pcx3;
    assign rvfi_insn      = insn3;
    assign rvfi_pc_next   = pcn3;
    assign rvfi_c         = c3;
    assign rvfi_rd_we     = we3;
    assign rvfi_rd        = rd3;
    assign rvfi_rd_wdata  = wd;
    assign rvfi_mem_re    = ld3;
    assign rvfi_mem_we    = st3;
    assign rvfi_mem_addr  = ea3;
    assign rvfi_mem_rdata = drd;
    assign rvfi_mem_wdata = xd3;
    always_ff @(posedge clk) if (we3 & g3) begin
        rfa[{th3, rd3}] <= wd;
        rfb[{th3, rd3}] <= wd;
    end
endmodule

// ALU (Phase 4 step 2a, docs/phase4/alu.md). x = rd, s = rs, the immediate, or rd again
// for shl. Each bit is 3 logic cells:
//   adder cell  a = m ? s' : x + s' + carry (bit i), s' = s ^ inv. The sum's LUT has one
//               input spare, so the choice between the sum and s' costs nothing.
//   logic LUT   t = a, x & a, x | a or x ^ a, by k
//   shift LUT   y = shr ? x >> 1 (bit 15 = cin) : t
//     op     m  k  inv cin      result
//     add    0  0  0   0        x + s, co = carry out
//     sub    0  0  1   1        x - s, co = 1 if no borrow
//     shl    0  0  0   C (rcl)  rd + rd = {x[14:0], cin}, co = x[15]
//     and    1  1  -   -        x & s
//     or     1  2  -   -        x | s
//     xor    1  3  -   -        x ^ s
//     pass   1  0  -   -        s
//     shr    -  -  -   C (rcr)  {cin, x[15:1]} (shr = 1; C takes x[0] outside the ALU)
module f1_alu (
    input  wire         m,
    input  wire  [1:0]  k,
    input  wire         inv,
    input  wire         cin,
    input  wire         shr,
    input  wire  [15:0] x,
    input  wire  [15:0] s,
    output wire  [15:0] y,
    output wire         co
);
    wire [15:0] sp = s ^ {16{inv}};
    wire [16:0] c;
    wire [15:0] a;
    assign c[0] = cin;
    for (genvar i = 0; i < 16; i++) begin : g_bit
        f1_addcell u (.m, .x(x[i]), .s(sp[i]), .ci(c[i]), .a(a[i]), .co(c[i + 1]));
    end
    assign co = c[16];
    wire [15:0] xr = {cin, x[15:1]};
    wire [15:0] t;
    for (genvar i = 0; i < 16; i++) begin : g_out
        // t = k 0: a, 1: x & a, 2: x | a, 3: x ^ a      index {I3 a, I2 x, I1 k[1], I0 k[0]}
        f1_lut4 #(.INIT(16'h7DC0)) lt (.i0(k[0]), .i1(k[1]), .i2(x[i]), .i3(a[i]), .o(t[i]));
        // y = shr ? xr : t                               index {I3 -, I2 t, I1 xr, I0 shr}
        f1_lut4 #(.INIT(16'hD8D8)) ly (.i0(shr), .i1(xr[i]), .i2(t[i]), .i3(1'b0), .o(y[i]));
    end
endmodule

// One iCE40 LUT with its truth table given, for logic Yosys maps less tightly.
module f1_lut4 #(
    parameter logic [15:0] INIT = 16'h0000
) (
    input  wire i0,
    input  wire i1,
    input  wire i2,
    input  wire i3,
    output wire o
);
`ifdef VERILATOR
    assign o = INIT[{i3, i2, i1, i0}];
`else
    SB_LUT4 #(.LUT_INIT(INIT)) lut (.I0(i0), .I1(i1), .I2(i2), .I3(i3), .O(o));
`endif
endmodule

// One adder bit as one iCE40 logic cell: SB_LUT4 (a = m ? s : x ^ s ^ ci) and SB_CARRY
// (co = majority of x, s, ci). nextpnr packs the pair into one cell because the LUT reads
// the carry's inputs (I1, I2) and its carry in (I3). Yosys cannot put m into the sum's LUT
// itself, so the cells are instantiated; Verilator runs the same truth table.
module f1_addcell (
    input  wire m,
    input  wire x,
    input  wire s,
    input  wire ci,
    output wire a,
    output wire co
);
    localparam logic [15:0] INIT = 16'hE1B4;    // index {I3 ci, I2 s, I1 x, I0 m}
`ifdef VERILATOR
    assign a  = INIT[{ci, s, x, m}];
    assign co = (x & s) | ((x | s) & ci);
`else
    SB_LUT4 #(.LUT_INIT(INIT)) lut (.I0(m), .I1(x), .I2(s), .I3(ci), .O(a));
    SB_CARRY cy (.I0(x), .I1(s), .CI(ci), .CO(co));
`endif
endmodule

// Skip conditions (isa.toml [[cond]]).
module f1_cond
    import isa_pkg::*;
(
    input  wire  [15:0] v,
    input  wire         cf,
    input  wire  [2:0]  cc,
    output logic        t
);
    always_comb case (cc)
        CC_AL:   t = 1'b1;
        CC_Z:    t = v == 16'd0;
        CC_NZ:   t = v != 16'd0;
        CC_NEG:  t = v[15];
        CC_NNEG: t = !v[15];
        CC_CC:   t = !cf;
        CC_CS:   t = cf;
        default: t = v[0];
    endcase
endmodule

// The two iCE40 primitives f1_addcell uses, declared as black boxes so the slang front end
// accepts them (as rtl/lib/sb_pll40_core.sv does for the PLL). synth_ice40 maps them to
// its own cells.
`ifndef VERILATOR
(* blackbox *)
module SB_LUT4 #(
    parameter logic [15:0] LUT_INIT = 16'h0000
) (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    output wire O
);
endmodule

(* blackbox *)
module SB_CARRY (
    input  wire I0,
    input  wire I1,
    input  wire CI,
    output wire CO
);
endmodule
`endif
