// Phase 2 experiment: J1a with its stacks in BRAM. This replaces swapforth's stack2 with
// rtl/lib/stack_bram.sv (same ports and parameter); j1.v and the j1a harness are unchanged.
`default_nettype none
module stack2 (
  input  wire        clk,
  output wire [15:0] rd,
  input  wire        we,
  input  wire [1:0]  delta,
  input  wire [15:0] wd);
  parameter DEPTH = 18;
  stack_bram #(.W(16), .DEPTH(DEPTH)) s (.clk(clk), .rd(rd), .we(we), .delta(delta), .wd(wd));
endmodule
