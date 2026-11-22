// SERV / QERV baseline harness: servile (SERV's own minimal wrapper: core + bus arbiter
// + RF-in-RAM interface) + serv_rf_ram (1 BRAM) + 4 KB wishbone RAM + 5-bit LED port
// on the ext bus. No timer, no CSRs/interrupts (with_csr=0, servile default).
// WIDTH=1 -> SERV, WIDTH=4 -> QERV.
`default_nettype none
module top #(parameter WIDTH = 1) (input wire clk, input wire rst, output reg [4:0] led);
  localparam RFW = 2*WIDTH;
  localparam RFD = $clog2(32*32/RFW);

  wire [31:0] m_adr, m_dat, x_adr, x_dat;
  wire [3:0]  m_sel, x_sel;
  wire        m_we, m_stb, x_we, x_stb;
  wire [31:0] m_rdt;
  reg         m_ack, x_ack;

  wire [RFD-1:0] rf_waddr, rf_raddr;
  wire [RFW-1:0] rf_wdata, rf_rdata;
  wire           rf_wen, rf_ren;

  mem32 #(.AW(10)) ram(.clk(clk), .addr(m_adr[11:2]),
                       .we({4{m_stb & m_we & ~m_ack}} & m_sel),
                       .wdata(m_dat), .rdata(m_rdt));
  always @(posedge clk) m_ack <= m_stb & ~m_ack & ~rst;

  always @(posedge clk) begin
    x_ack <= x_stb & ~x_ack & ~rst;
    if (x_stb & x_we) led <= x_dat[4:0];
  end

  serv_rf_ram #(.width(RFW), .csr_regs(0)) rf_ram(
    .i_clk(clk), .i_waddr(rf_waddr), .i_wdata(rf_wdata), .i_wen(rf_wen),
    .i_raddr(rf_raddr), .i_ren(rf_ren), .o_rdata(rf_rdata));

  servile #(.width(WIDTH), .with_csr(1'b0)) cpu(
    .i_clk(clk), .i_rst(rst), .i_timer_irq(1'b0),
    .o_wb_mem_adr(m_adr), .o_wb_mem_dat(m_dat), .o_wb_mem_sel(m_sel),
    .o_wb_mem_we(m_we), .o_wb_mem_stb(m_stb), .i_wb_mem_rdt(m_rdt), .i_wb_mem_ack(m_ack),
    .o_wb_ext_adr(x_adr), .o_wb_ext_dat(x_dat), .o_wb_ext_sel(x_sel),
    .o_wb_ext_we(x_we), .o_wb_ext_stb(x_stb), .i_wb_ext_rdt({27'b0, led}), .i_wb_ext_ack(x_ack),
    .o_rf_waddr(rf_waddr), .o_rf_wdata(rf_wdata), .o_rf_wen(rf_wen),
    .o_rf_raddr(rf_raddr), .i_rf_rdata(rf_rdata), .o_rf_ren(rf_ren));
endmodule
