// Phase 2 primitive cost table: the building blocks being priced.
// Every module has the same ports: `i` (all inputs, packed), `o` (all outputs), and `clk` for
// blocks with state. prims/run.py wraps each one in the measurement harness (see there).
`default_nettype none

// ---- harness baseline: no logic ---------------------------------------------------------
module p_wire #(parameter int NIN = 16, parameter int NOUT = 16) (
    input wire clk, input wire [NIN-1:0] i, output wire [NOUT-1:0] o);
    assign o = i[NOUT-1:0];
endmodule

// ---- arithmetic and compare -------------------------------------------------------------
module p_add #(parameter int W = 16) (input wire clk, input wire [2*W-1:0] i, output wire [W-1:0] o);
    assign o = i[2*W-1:W] + i[W-1:0];
endmodule

module p_addsub #(parameter int W = 16) (input wire clk, input wire [2*W:0] i, output wire [W-1:0] o);
    wire [W-1:0] a = i[2*W-1:W], b = i[W-1:0];
    assign o = i[2*W] ? a - b : a + b;
endmodule

// add/sub on one adder: a + (b ^ sub) + sub, with the +sub as an extra LSB (carry-in)
module p_addsub_x #(parameter int W = 16) (input wire clk, input wire [2*W:0] i, output wire [W-1:0] o);
    wire         sub = i[2*W];
    wire [W-1:0] a = i[2*W-1:W], b = i[W-1:0] ^ {W{sub}};
    wire [W:0]   s = {a, 1'b1} + {b, sub};
    assign o = s[W:1];
endmodule

module p_inc #(parameter int W = 13) (input wire clk, input wire [W-1:0] i, output wire [W-1:0] o);
    assign o = i + 1'b1;
endmodule

module p_eq #(parameter int W = 16) (input wire clk, input wire [2*W-1:0] i, output wire [0:0] o);
    assign o = i[2*W-1:W] == i[W-1:0];
endmodule

module p_ltu #(parameter int W = 16) (input wire clk, input wire [2*W-1:0] i, output wire [0:0] o);
    assign o = i[2*W-1:W] < i[W-1:0];
endmodule

// and / or / xor / not, as a 4-way logic unit
module p_logic #(parameter int W = 16) (input wire clk, input wire [2*W+1:0] i, output logic [W-1:0] o);
    wire [W-1:0] a = i[2*W-1:W], b = i[W-1:0];
    always_comb case (i[2*W+1:2*W])
        2'd0: o = a & b;
        2'd1: o = a | b;
        2'd2: o = a ^ b;
        default: o = ~a;
    endcase
endmodule

// ---- multiplexers -----------------------------------------------------------------------
// N:1, binary select
module p_mux #(parameter int N = 4, parameter int W = 16, localparam int S = $clog2(N)) (
    input wire clk, input wire [S+N*W-1:0] i, output wire [W-1:0] o);
    wire [S-1:0] sel = i[S+N*W-1:N*W];
    wire [W-1:0] d [N];
    for (genvar k = 0; k < N; k++) assign d[k] = i[k*W +: W];
    assign o = d[sel];
endmodule

// N:1, one-hot select (AND-OR); the select decode is assumed to come for free upstream
module p_mux1h #(parameter int N = 4, parameter int W = 16) (
    input wire clk, input wire [N+N*W-1:0] i, output logic [W-1:0] o);
    always_comb begin
        o = '0;
        for (int k = 0; k < N; k++) o |= i[k*W +: W] & {W{i[N*W + k]}};
    end
endmodule

// ---- shifters ---------------------------------------------------------------------------
// shift by one: 0 shl, 1 shr, 2 sar, 3 pass
module p_shift1 #(parameter int W = 16) (input wire clk, input wire [W+1:0] i, output logic [W-1:0] o);
    wire [W-1:0] a = i[W-1:0];
    always_comb case (i[W+1:W])
        2'd0: o = {a[W-2:0], 1'b0};
        2'd1: o = {1'b0, a[W-1:1]};
        2'd2: o = {a[W-1], a[W-1:1]};
        default: o = a;
    endcase
endmodule

// barrel shifter, left only, amount 0..W-1
module p_bshl #(parameter int W = 16, localparam int A = $clog2(W)) (
    input wire clk, input wire [A+W-1:0] i, output wire [W-1:0] o);
    assign o = i[W-1:0] << i[A+W-1:W];
endmodule

// barrel shifter: 0 shl, 1 shr, 2 sar, 3 rotate left
module p_bshift #(parameter int W = 16, localparam int A = $clog2(W)) (
    input wire clk, input wire [2+A+W-1:0] i, output logic [W-1:0] o);
    wire [W-1:0] a = i[W-1:0];
    wire [A-1:0] n = i[A+W-1:W];
    always_comb case (i[2+A+W-1:A+W])
        2'd0: o = a << n;
        2'd1: o = a >> n;
        2'd2: o = $signed(a) >>> n;
        default: o = (a << n) | (a >> (W - n));
    endcase
endmodule

// same four operations on one left funnel shifter: right shifts reverse the bits on the way
// in and out; the low half of the funnel supplies zeros, sign bits or (rotate) the input
module p_bshift_f #(parameter int W = 16, localparam int A = $clog2(W)) (
    input wire clk, input wire [2+A+W-1:0] i, output wire [W-1:0] o);
    wire [W-1:0] a = i[W-1:0];
    wire [A-1:0] n = i[A+W-1:W];
    wire [1:0]  op = i[2+A+W-1:A+W];
    wire right = op == 2'd1 || op == 2'd2;
    function automatic logic [W-1:0] rev(input logic [W-1:0] x);
        for (int k = 0; k < W; k++) rev[k] = x[W-1-k];
    endfunction
    wire [W-1:0]   hi = right ? rev(a) : a;
    wire [W-1:0]   lo = op == 2'd3 ? a : {W{op == 2'd2 && a[W-1]}};
    wire [2*W-1:0] f  = {hi, lo} << n;
    assign o = right ? rev(f[2*W-1:W]) : f[2*W-1:W];
endmodule

// ---- register files ---------------------------------------------------------------------
// 256 x W in BRAM, R read ports (R BRAMs with duplicated writes), registered reads.
// i = {we, waddr, wdata, raddr[R-1], ..., raddr[0]}, o = {rdata[R-1], ..., rdata[0]}
module p_rf_bram #(parameter int R = 1, parameter int W = 16) (
    input wire clk, input wire [1+8+W+8*R-1:0] i, output logic [W*R-1:0] o);
    wire         we    = i[8*R+W+8];
    wire [7:0]   waddr = i[8*R+W +: 8];
    wire [W-1:0] wdata = i[8*R +: W];
    for (genvar r = 0; r < R; r++) begin : port
        // no_rw_check: a read of the address being written may return either value. Without
        // it, Yosys builds the old-value guarantee from ~40 FFs + ~30 LUTs per read port.
        (* ram_style = "block", no_rw_check *) logic [W-1:0] mem [256];
        always_ff @(posedge clk) begin
            if (we) mem[waddr] <= wdata;
            o[r*W +: W] <= mem[i[r*8 +: 8]];
        end
    end
endmodule

// D x W in flip-flops, R combinational read ports, one write port
module p_rf_ff #(parameter int R = 2, parameter int D = 8, parameter int W = 16,
                 localparam int A = $clog2(D)) (
    input wire clk, input wire [1+A+W+A*R-1:0] i, output logic [W*R-1:0] o);
    wire         we    = i[A*R+W+A];
    wire [A-1:0] waddr = i[A*R+W +: A];
    wire [W-1:0] wdata = i[A*R +: W];
    (* ram_style = "logic" *) logic [W-1:0] rf [D];   // else Yosys moves it into BRAM
    always_ff @(posedge clk) if (we) rf[waddr] <= wdata;
    for (genvar r = 0; r < R; r++) assign o[r*W +: W] = rf[i[r*A +: A]];
endmodule

// ---- barrel thread program counters ----------------------------------------------------
// N threads take turns, one per cycle. Each cycle the active thread's PC goes out to fetch,
// and its next PC (PC+1, or a taken branch's target) is written back. i = {take, target}.
module p_tpc_ff #(parameter int N = 4, parameter int W = 13, localparam int T = $clog2(N)) (
    input wire clk, input wire [W:0] i, output wire [W-1:0] o);
    logic [W-1:0] pc [N];
    logic [T-1:0] t = '0;
    initial for (int k = 0; k < N; k++) pc[k] = '0;
    always_ff @(posedge clk) begin
        pc[t] <= i[W] ? i[W-1:0] : pc[t] + 1'b1;
        t     <= t + 1'b1;
    end
    assign o = pc[t];
endmodule

// Same, PCs in BRAM. q (the BRAM output register) holds the active thread's PC; the write
// goes to the active thread while the read fetches the next one, so the addresses differ.
module p_tpc_bram #(parameter int N = 4, parameter int W = 13, localparam int T = $clog2(N)) (
    input wire clk, input wire [W:0] i, output wire [W-1:0] o);
    (* ram_style = "block" *) logic [W-1:0] pc [N];
    logic [W-1:0] q;
    logic [T-1:0] t = '0;
    always_ff @(posedge clk) begin
        pc[t] <= i[W] ? i[W-1:0] : q + 1'b1;
        q     <= pc[t + 1'b1];
        t     <= t + 1'b1;
    end
    assign o = q;
endmodule
