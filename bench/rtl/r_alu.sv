// ALU and skip conditions for the two-operand register ISA, v2 (F1 and F5; D-005).
// The ALU is skel_alu plus a carry out: co = 1 when x - s does not borrow (x >= s unsigned),
// so a skip can compare two registers with the existing adder.
`default_nettype none
module r_alu (
    input  wire  [2:0]  op,                     // add sub and or xor pass shl shr
    input  wire  [15:0] x,
    input  wire  [15:0] s,
    output logic [15:0] y,
    output wire         co
);
    wire sub = op == 3'd1;
    /* verilator lint_off UNUSEDSIGNAL */       // sum[0] is the carry-in position
    wire [17:0] sum = {1'b0, x, 1'b1} + {1'b0, s ^ {16{sub}}, sub};
    /* verilator lint_on UNUSEDSIGNAL */
    assign co = sum[17];
    always_comb case (op)
        3'd0, 3'd1: y = sum[16:1];
        3'd2: y = x & s;
        3'd3: y = x | s;
        3'd4: y = x ^ s;
        3'd5: y = s;
        3'd6: y = {x[14:0], 1'b0};
        default: y = {1'b0, x[15:1]};
    endcase
endmodule

// cc: 0 always, 1 rd == 0, 2 rd != 0, 3 rd < 0, 4 rd >= 0, 5 rd < rs (unsigned),
//     6 rd >= rs (unsigned), 7 rd odd. co must come from r_alu computing rd - rs.
module r_cond (input wire [15:0] v, input wire co, input wire [2:0] cc, output logic t);
    always_comb case (cc)
        3'd0: t = 1'b1;
        3'd1: t = v == 16'd0;
        3'd2: t = v != 16'd0;
        3'd3: t = v[15];
        3'd4: t = !v[15];
        3'd5: t = !co;
        3'd6: t = co;
        default: t = v[0];
    endcase
endmodule
