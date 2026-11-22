// Minimax baseline harness: core (unmodified, PC_BITS=11, microcode at 0x400)
// + 2 KB unified memory. Minimax needs three ports on one memory (16-bit
// instruction read, 32-bit data read, data write); a BRAM has one read port,
// so the memory is mirrored: an instruction copy and a data copy, both written.
// 2 KB x 2 copies = 8 BRAMs. 5-bit LED port at addr[22]=1.
`default_nettype none
module top(input wire clk, input wire rst, output reg [4:0] led);
  localparam PC_BITS = 11;
  wire [PC_BITS-1:0] inst_addr;
  wire        inst_ce, rreq;
  wire [31:0] addr, wdata;
  wire [3:0]  wmask;
  reg  [15:0] inst;
  reg  [31:0] rdata;
  reg         rack;
  wire        is_io = addr[22];
  wire [3:0]  we = wmask & {4{~is_io}};

  // data copy: 512 x 32
  reg [31:0] dmem [0:511];
  // instruction copy: two 512 x 16 halves (even/odd halfword)
  reg [15:0] ilo [0:511];
  reg [15:0] ihi [0:511];
  initial begin $readmemh("rand32.hex", dmem, 0, 511); $readmemh("rand16.hex", ilo, 0, 511); $readmemh("rand16.hex", ihi, 0, 511); end

  wire [8:0] wa = addr[10:2];
  always @(posedge clk) begin
    if (we[0]) dmem[wa][ 7: 0] <= wdata[ 7: 0];
    if (we[1]) dmem[wa][15: 8] <= wdata[15: 8];
    if (we[2]) dmem[wa][23:16] <= wdata[23:16];
    if (we[3]) dmem[wa][31:24] <= wdata[31:24];
    if (we[0]) ilo[wa][ 7: 0] <= wdata[ 7: 0];
    if (we[1]) ilo[wa][15: 8] <= wdata[15: 8];
    if (we[2]) ihi[wa][ 7: 0] <= wdata[23:16];
    if (we[3]) ihi[wa][15: 8] <= wdata[31:24];
    rdata <= is_io ? {27'b0, led} : dmem[wa];
    rack  <= rreq;
    if (is_io & wmask[0]) led <= wdata[4:0];
  end

  reg [15:0] ilo_q, ihi_q; reg isel;
  always @(posedge clk) if (inst_ce) begin
    ilo_q <= ilo[inst_addr[PC_BITS-1:2]];
    ihi_q <= ihi[inst_addr[PC_BITS-1:2]];
    isel  <= inst_addr[1];
  end
  always @* inst = isel ? ihi_q : ilo_q;

  minimax #(.PC_BITS(PC_BITS), .UC_BASE(32'h00000400)) cpu(
    .clk(clk), .reset(rst), .inst(inst), .inst_ce(inst_ce), .rdata(rdata),
    .inst_addr(inst_addr), .addr(addr), .wdata(wdata), .wmask(wmask),
    .rreq(rreq), .rack(rack));
endmodule
