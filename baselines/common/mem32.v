// Uniform baseline memory: 1024 x 32 (4 KB), byte write enables, synchronous read.
// Filled with random words so nothing can be constant-folded. Maps to 8 x SB_RAM40_4K.
`default_nettype none
module mem32 #(parameter AW = 10, parameter INIT = "rand32.hex") (
  input  wire          clk,
  input  wire [AW-1:0] addr,
  input  wire [3:0]    we,
  input  wire [31:0]   wdata,
  output reg  [31:0]   rdata
);
  reg [31:0] m [0:(1<<AW)-1];
  initial $readmemh(INIT, m);
  always @(posedge clk) begin
    if (we[0]) m[addr][ 7: 0] <= wdata[ 7: 0];
    if (we[1]) m[addr][15: 8] <= wdata[15: 8];
    if (we[2]) m[addr][23:16] <= wdata[23:16];
    if (we[3]) m[addr][31:24] <= wdata[31:24];
    rdata <= m[addr];
  end
endmodule
