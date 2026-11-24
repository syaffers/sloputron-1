// Phase 2 skeletons: the ALU every finalist shares, so the four skeletons differ only in how
// they hold operands and threads. x is the destination-side operand (T, A or rd), s the other
// one (N, R[n]/immediate, or rs/immediate).
//   0 add  x + s      2 and  x & s      4 xor  x ^ s      6 shl1  x << 1
//   1 sub  x - s      3 or   x | s      5 pass s          7 shr1  x >> 1 (logical)
// Add and sub share one adder (docs/phase2/primitives.md: 17 LC instead of 46).
`default_nettype none
module skel_alu (
    input  wire  [2:0]  op,
    input  wire  [15:0] x,
    input  wire  [15:0] s,
    output logic [15:0] y
);
    wire        sub = op == 3'd1;
    /* verilator lint_off UNUSEDSIGNAL */          // sum[0] is the carry-in position
    wire [16:0] sum = {x, 1'b1} + {s ^ {16{sub}}, sub};
    /* verilator lint_on UNUSEDSIGNAL */
    always_comb case (op)
        3'd0, 3'd1: y = sum[16:1];
        3'd2:       y = x & s;
        3'd3:       y = x | s;
        3'd4:       y = x ^ s;
        3'd5:       y = s;
        3'd6:       y = {x[14:0], 1'b0};
        default:    y = {1'b0, x[15:1]};
    endcase
endmodule

// Branch/skip condition on a 16-bit value: 0 always, 1 zero, 2 non-zero, 3 negative.
module skel_cond (input wire [15:0] v, input wire [1:0] cc, output wire t);
    assign t = cc == 2'd0 ? 1'b1 : cc == 2'd1 ? v == 16'd0 : cc == 2'd2 ? v != 16'd0 : v[15];
endmodule
