// FazyRV baseline harness (extra baseline, 2024 iCE40-targeted chunked RV32I):
// fazyrv_top (unmodified; CONF=MIN, RFTYPE=BRAM_DP_BP default, register file in BRAM)
// + 4 KB RAM shared by the imem and dmem buses exactly as in FazyRV's own fsoc.sv
// + 5-bit LED port at addr[22]=1.
`default_nettype none
module top #(parameter CHUNKSIZE = 8) (input wire clk, input wire rst, output reg [4:0] led);
  logic        i_stb, i_cyc, d_cyc, d_stb, d_we, trap;
  logic [31:0] i_adr, d_adr, d_wdat, m_rdat;
  logic [3:0]  d_be;
  logic        m_ack, io_ack;
  wire  sel_io = d_adr[22];
  wire  m_cyc  = (i_stb | (d_stb & ~sel_io));
  wire [31:0] m_adr = i_stb ? i_adr : d_adr;

  mem32 #(.AW(10)) ram(.clk(clk), .addr(m_adr[11:2]),
                       .we({4{d_we & d_stb & ~sel_io & ~i_stb & ~m_ack}} & d_be),
                       .wdata(d_wdat), .rdata(m_rdat));
  always_ff @(posedge clk) begin
    m_ack  <= m_cyc & ~m_ack & ~rst;
    io_ack <= d_stb & sel_io & ~io_ack & ~rst;
    if (d_stb & sel_io & d_we & ~io_ack) led <= d_wdat[4:0];
  end

  fazyrv_top #(.CHUNKSIZE(CHUNKSIZE), .CONF("MIN")) cpu (
    .clk_i(clk), .rst_in(~rst), .tirq_i(1'b0), .trap_o(trap),
    .wb_imem_stb_o(i_stb), .wb_imem_cyc_o(i_cyc), .wb_imem_adr_o(i_adr),
    .wb_imem_dat_i(m_rdat), .wb_imem_ack_i(m_ack & i_stb),
    .wb_dmem_cyc_o(d_cyc), .wb_dmem_stb_o(d_stb), .wb_dmem_we_o(d_we),
    .wb_dmem_ack_i((m_ack | io_ack) & d_stb), .wb_dmem_be_o(d_be),
    .wb_dmem_dat_i(sel_io ? {27'b0, led} : m_rdat), .wb_dmem_adr_o(d_adr),
    .wb_dmem_dat_o(d_wdat));
endmodule
