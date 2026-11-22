// FemtoRV32-Quark baseline harness: core (unmodified, IceStick config: 24-bit cycle
// counter, ADDR_WIDTH=24) + 4 KB RAM + 5-bit LED port at addr[22]=1.
`default_nettype none
`define NRV_COUNTER_WIDTH 24
module top(input wire clk, input wire rst, output reg [4:0] led);
  wire [31:0] addr, wdata, rdata_mem;
  wire [3:0]  wmask;
  wire        rstrb;
  wire        is_io = addr[22];
  reg         io_sel;

  mem32 #(.AW(10)) ram(.clk(clk), .addr(addr[11:2]), .we(wmask & {4{~is_io}}),
                       .wdata(wdata), .rdata(rdata_mem));
  always @(posedge clk) begin
    io_sel <= is_io;
    if (is_io & wmask[0]) led <= wdata[4:0];
  end

  FemtoRV32 cpu(.clk(clk), .mem_addr(addr), .mem_wdata(wdata), .mem_wmask(wmask),
                .mem_rdata(io_sel ? {27'b0, led} : rdata_mem), .mem_rstrb(rstrb),
                .mem_rbusy(1'b0), .mem_wbusy(1'b0), .reset(~rst));
endmodule
