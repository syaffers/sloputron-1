// J1a baseline harness: j1 core (unmodified) + 4 KB code/data RAM (2048 x 16,
// code port reads, data port writes, as in swapforth j1a) + 5-bit LED port on io_wr.
`default_nettype none
module top(input wire clk, input wire rst, output reg [4:0] led);
  wire io_rd, io_wr, mem_wr;
  wire [15:0] mem_addr, dout;
  wire [12:0] code_addr;
  reg  [15:0] insn;

  reg [15:0] ram [0:2047];
  initial $readmemh("rand16.hex", ram);
  always @(posedge clk) begin
    if (mem_wr) ram[mem_addr[11:1]] <= dout;
    insn <= ram[code_addr[10:0]];
  end

  always @(posedge clk) if (io_wr) led <= dout[4:0];

  j1 cpu(.clk(clk), .resetq(~rst), .io_rd(io_rd), .io_wr(io_wr),
         .mem_addr(mem_addr), .mem_wr(mem_wr), .dout(dout),
         .io_din({11'b0, led}), .code_addr(code_addr), .insn(insn));
endmodule
