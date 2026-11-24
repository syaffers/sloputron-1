// F4 skeleton: barrel stack machine. F2's instruction set, N threads taking turns one cycle
// each. Everything a thread owns is in BRAM, so a thread costs no logic cells:
//   ctx    N x 35  {T, rsp, dsp, pc}, read one cycle ahead (3 BRAMs)
//   dstack 16 entries per thread, address {thread, dsp}; N = dstack[dsp]   (1 BRAM)
//   rstack 16 entries per thread, address {thread, rsp}; R = rstack[rsp]   (1 BRAM)
// Pipeline, thread t:
//   S0  ctx[t] arrives -> ROM read at pc, dstack/rstack reads at dsp/rsp
//   S1  insn, N, R arrive -> execute; stack and data-memory writes; data read at T
//   S2  ctx[t] <- {T', rsp', dsp', pc'}; a `[T]` load takes T' from the data memory here
// ctx is written at the end of S2 and read for thread t's next turn N-1 cycles after S0, so
// N >= 4. No forwarding, interlocks or branch penalties exist: each thread sees one
// instruction finish before its next one starts.
`default_nettype none
module skel_f4 #(
    parameter int  N  = 4,
    localparam int TB = $clog2(N)
) (
    input  wire         clk,
    output wire  [10:0] iaddr,
    input  wire  [15:0] insn,
    output wire  [7:0]  daddr,
    input  wire  [15:0] drd,
    output wire         dwe,
    output wire  [7:0]  dwa,
    output wire  [15:0] dwd
);
    (* ram_style = "block", no_rw_check *) logic [34:0] ctx    [N];
    (* ram_style = "block", no_rw_check *) logic [15:0] dstack [N * 16];
    (* ram_style = "block", no_rw_check *) logic [15:0] rstack [N * 16];
    initial for (int k = 0; k < N; k++) ctx[k] = '0;

    logic [TB-1:0] th = '0;
    wire  [TB-1:0] thn = th + 1'b1;
    logic [34:0]   q;                               // ctx[th] (BRAM output register)
    wire  [15:0]   q_T   = q[34:19];
    wire  [3:0]    q_rsp = q[18:15], q_dsp = q[14:11];
    wire  [10:0]   q_pc  = q[10:0];

    // ---- S0 ---------------------------------------------------------------------------
    logic [TB-1:0] th1;
    logic [10:0]   pc1;
    logic [3:0]    dsp, rsp;
    logic [15:0]   T, Nq, R;
    always_ff @(posedge clk) begin
        q   <= ctx[thn];
        th  <= thn;
        th1 <= th;
        pc1 <= q_pc + 1'b1;
        dsp <= q_dsp;
        rsp <= q_rsp;
        T   <= q_T;
        Nq  <= dstack[{th, q_dsp}];
        R   <= rstack[{th, q_rsp}];
    end
    assign iaddr = q_pc;

    // ---- S1: execute (same decode as skel_f2) -------------------------------------------
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
    skel_alu alu (.op(is_jz ? 3'd5 : src[2:0]), .x(T), .s(Nq), .y);

    logic [15:0] Tn;
    always_comb
        if (is_lit)                 Tn = {1'b0, insn[14:0]};
        else if (is_alu & src[3])   Tn = src[1] ? T : R;        // 9 ([T]) is resolved in S2
        else if (is_alu | is_jz)    Tn = y;
        else                        Tn = T;

    wire [10:0] pcn  = (is_jmp | is_call | (is_jz & T == 16'd0)) ? insn[10:0]
                     : ret ? R[10:0] : pc1;
    wire [3:0]  dspn = dsp + {{2{ddel[1]}}, ddel};
    wire [3:0]  rspn = rsp + {{2{rdel[1]}}, rdel};

    always_ff @(posedge clk) begin
        if (is_lit | t2n)   dstack[{th1, dspn}] <= T;
        if (is_call | t2r)  rstack[{th1, rspn}] <= is_call ? {5'd0, pc1} : T;
    end
    assign daddr = T[7:0];
    assign dwe   = is_alu & insn[5];
    assign dwa   = T[7:0];
    assign dwd   = Nq;

    // ---- S2: write the thread's state back --------------------------------------------
    logic [TB-1:0] th2;
    logic          ld2;
    logic [15:0]   T2;
    logic [3:0]    dsp2, rsp2;
    logic [10:0]   pc2;
    always_ff @(posedge clk) begin
        th2 <= th1;
        ld2  <= is_alu & src == 4'd9;
        T2   <= Tn;
        dsp2 <= dspn;
        rsp2 <= rspn;
        pc2  <= pcn;
        ctx[th2] <= {ld2 ? drd : T2, rsp2, dsp2, pc2};
    end
endmodule
