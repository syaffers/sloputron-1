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
    output wire  [15:0]   dwd
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

    logic [TB-1:0] th2;
    logic [15:0]   xd, xs;
    logic [2:0]    op2, cc2;
    logic [1:0]    src2;                            // s = 0 rs, 1 sext(i), 2 {i, rd[7:0]}, 3 PC+1
    logic          we2, ld2, st2, sk2, jal2, jmp2, setc2, sh2, ci2, cf2;
    logic [3:0]    off2;
    logic [3:0]    rd2;
    logic [10:0]   ins2, pc12, pc22;
    always_ff @(posedge clk) begin
        xd    <= rfa[{th1, insn[11:8]}];
        xs    <= rfb[{th1, insn[7:4]}];
        th2   <= th1;
        op2   <= op;
        src2  <= is_alui ? 2'd1 : is_alur ? 2'd0 : is_ldhi ? 2'd2 : 2'd3;
        we2   <= is_alui | (is_alur & !insn[3]) | is_ld | is_ldhi | is_jal;
        setc2 <= is_alu & (op == ALU_ADD || op == ALU_SUB);
        sh2   <= is_alu & (op == ALU_SHL || op == ALU_SHR);
        ci2   <= is_alur & insn[4];                 // rcl / rcr: shift C in
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
    wire        so;
    f1_alu alu (.op(op2), .x(xd), .s, .ci(ci2 & cf2), .y, .co, .so);
    wire c;
    f1_cond cnd (.v(xd), .cf(cf2), .cc(cc2), .t(c));
    wire [10:0] pcn = jmp2 ? ins2 : jal2 ? xs[10:0] : (sk2 & c) ? pc22 : pc12;
    wire        cfn = setc2 ? co : sh2 ? so : cf2;
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
    always_ff @(posedge clk) if (we3 & g3) begin
        rfa[{th3, rd3}] <= wd;
        rfb[{th3, rd3}] <= wd;
    end
endmodule

// ALU: x = rd, s = rs or immediate. co = carry out of add, or 1 = no borrow for sub.
// ci = the bit a shift brings in (C for rcl/rcr, else 0); so = the bit it drops.
module f1_alu
    import isa_pkg::*;
(
    input  wire  [2:0]  op,
    input  wire  [15:0] x,
    input  wire  [15:0] s,
    input  wire         ci,
    output logic [15:0] y,
    output wire         co,
    output wire         so
);
    wire sub = op == ALU_SUB;
    /* verilator lint_off UNUSEDSIGNAL */       // sum[0] is the carry-in position
    wire [17:0] sum = {1'b0, x, 1'b1} + {1'b0, s ^ {16{sub}}, sub};
    /* verilator lint_on UNUSEDSIGNAL */
    assign co = sum[17];
    always_comb case (op)
        ALU_ADD, ALU_SUB: y = sum[16:1];
        ALU_AND:  y = x & s;
        ALU_OR:   y = x | s;
        ALU_XOR:  y = x ^ s;
        ALU_PASS: y = s;
        ALU_SHL:  y = {x[14:0], ci};
        default:  y = {ci, x[15:1]};
    endcase
    assign so = op == ALU_SHL ? x[15] : x[0];
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
