// PicoRV32 baseline harness: picorv32 with the repo's "small" configuration
// (scripts/vivado/synth_area_top.v: no counters, latched rdata, 1-stage shift,
// no misalign/illegal-insn traps) + 4 KB RAM + 5-bit LED port at addr[22]=1.
// RV32E variant: set ENABLE_REGS_16_31 = 0.
`default_nettype none
module top #(parameter REGS_16_31 = 1) (input wire clk, input wire rst, output reg [4:0] led);
  wire        valid, instr;
  reg         ready;
  wire [31:0] addr, wdata, rdata_mem;
  wire [3:0]  wstrb;
  wire        is_io = addr[22];
  reg         io_sel;

  mem32 #(.AW(10)) ram(.clk(clk), .addr(addr[11:2]),
                       .we(wstrb & {4{valid & ~ready & ~is_io}}),
                       .wdata(wdata), .rdata(rdata_mem));
  always @(posedge clk) begin
    ready  <= valid & ~ready;
    io_sel <= is_io;
    if (valid & ~ready & is_io & wstrb[0]) led <= wdata[4:0];
  end

  picorv32 #(
    .ENABLE_COUNTERS(0), .LATCHED_MEM_RDATA(1), .TWO_STAGE_SHIFT(0),
    .CATCH_MISALIGN(0), .CATCH_ILLINSN(0), .ENABLE_REGS_16_31(REGS_16_31)
  ) cpu (
    .clk(clk), .resetn(~rst), .mem_valid(valid), .mem_instr(instr), .mem_ready(ready),
    .mem_addr(addr), .mem_wdata(wdata), .mem_wstrb(wstrb),
    .mem_rdata(io_sel ? {27'b0, led} : rdata_mem));
endmodule
