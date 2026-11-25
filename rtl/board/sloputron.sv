// sloputron-1 on the iCEstick: the F1 core (rtl/core/f1_core.sv), its program ROM, data RAM,
// and a hardware UART and the LEDs on the data bus (D-007).
//   program ROM  2048 x 16 (4 KB, 8 BRAMs), filled from ROM at configuration
//   data RAM     1024 x 16 at data addresses 0x000-0x3FF (4 BRAMs), zero at configuration
//   I/O          0x800-0xFFF, decoded from address bit 11 and bits 1..0 (isa.toml [memory]):
//                0xFFC UART_TX (W), 0xFFD UART_STATUS (R), 0xFFE UART_RX (R, clears), 0xFFF LED (W)
// The clock is the board's 12 MHz oscillator, or the PLL when PLL_DIVF > 0 (set CLK_HZ to
// match; scripts/board_sweep.py does this from `icepll`). Loads take effect one cycle later
// (the RAM's synchronous read), so the I/O read data is registered the same way.
`default_nettype none
module sloputron #(
    parameter int    CLK_HZ       = 12_000_000,     // the CPU clock: 12 MHz, or the PLL output
    /* verilator lint_off UNUSEDPARAM */            // used only by the PLL (not simulated)
    parameter int    PLL_DIVR     = 0,              // PLL settings from icepll; DIVF = 0: no PLL
    parameter int    PLL_DIVF     = 0,
    parameter int    PLL_DIVQ     = 0,
    parameter int    PLL_FILTER   = 0,
    /* verilator lint_on UNUSEDPARAM */
    parameter string ROM          = "build/programs/demo.hex"
) (
    input  wire        clk,
    input  wire        uart_rx,
    output wire        uart_tx,
    output logic [4:0] led = '0
);
    import isa_pkg::*;
    localparam int RAM_WORDS    = 1024;
    localparam int CLKS_PER_BIT = (CLK_HZ + 57_600) / 115_200;        // 104 at 12 MHz
    // The start-up hold (f1_core) lasts at least the 85 us that was tested at 12 MHz.
    localparam int STARTUP      = 1 << $clog2((CLK_HZ + 11_999_999) / 12_000_000 * 1024);

    // ---- clock: the oscillator, or the PLL (the core waits for the PLL to lock) -----------
    wire cclk, lock;
    generate if (PLL_DIVF == 0) begin : g_osc
        assign cclk = clk;
        assign lock = 1'b1;
    end else begin : g_pll
`ifdef VERILATOR
        assign cclk = clk;
        assign lock = 1'b1;
`else
        SB_PLL40_CORE #(
            .FEEDBACK_PATH("SIMPLE"), .DIVR(4'(PLL_DIVR)), .DIVF(7'(PLL_DIVF)),
            .DIVQ(3'(PLL_DIVQ)), .FILTER_RANGE(3'(PLL_FILTER))
        ) pll (
            .REFERENCECLK(clk), .RESETB(1'b1), .BYPASS(1'b0),
            .PLLOUTCORE(), .PLLOUTGLOBAL(cclk), .LOCK(lock));
`endif
    end endgenerate
    logic [1:0] locked = '0;                        // LOCK is asynchronous: synchronise it
    always_ff @(posedge cclk) locked <= {locked[0], lock};
    wire run = PLL_DIVF == 0 ? 1'b1 : locked[1];

    wire  [10:0]          iaddr;
    logic [15:0]          insn;
    /* verilator lint_off UNUSEDSIGNAL */            // bit 10 is not decoded (RAM 9..0, I/O 11)
    wire  [DATA_BITS-1:0] daddr, dwa;
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [15:0]          dwd;
    wire                  dre, dwe;
    logic [15:0]          drd;

    /* verilator lint_off PINCONNECTEMPTY */           // the retirement port is for simulation
    f1_core #(.STARTUP(STARTUP)) cpu (.clk(cclk), .run, .iaddr, .insn, .daddr, .dre, .drd, .dwe, .dwa, .dwd,
        .rvfi_valid(), .rvfi_thread(), .rvfi_pc(), .rvfi_insn(), .rvfi_pc_next(), .rvfi_c(),
        .rvfi_rd_we(), .rvfi_rd(), .rvfi_rd_wdata(), .rvfi_mem_re(), .rvfi_mem_we(),
        .rvfi_mem_addr(), .rvfi_mem_rdata(), .rvfi_mem_wdata());
    /* verilator lint_on PINCONNECTEMPTY */

    // ---- memories ---------------------------------------------------------------------
    (* ram_style = "block" *)              logic [15:0] rom [2048];
    (* ram_style = "block", no_rw_check *) logic [15:0] ram [RAM_WORDS];
    initial $readmemh(ROM, rom);
    initial for (int i = 0; i < RAM_WORDS; i++) ram[i] = '0;
    always_ff @(posedge cclk) insn <= rom[iaddr];

    wire io_rd = daddr[11];
    wire io_wr = dwe & dwa[11];
    logic [15:0] ram_q;
    always_ff @(posedge cclk) begin
        if (dwe & !dwa[11]) ram[dwa[9:0]] <= dwd;
        ram_q <= ram[daddr[9:0]];
    end

    // ---- UART -------------------------------------------------------------------------
    logic [7:0] rx_data, rx_byte = '0;
    logic       rx_valid, rx_full = 1'b0, tx_busy;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk(cclk), .rx(uart_rx), .data(rx_data), .valid(rx_valid));
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(cclk), .start(io_wr && dwa[1:0] == IO_UART_TX[1:0] && !tx_busy), .data(dwd[7:0]),
        .tx(uart_tx), .busy(tx_busy));

    always_ff @(posedge cclk) begin
        if (rx_valid) begin                         // a new byte wins over a clearing read
            rx_byte <= rx_data;
            rx_full <= 1'b1;
        end else if (dre && io_rd && daddr[1:0] == IO_UART_RX[1:0]) begin
            rx_full <= 1'b0;
        end
        if (io_wr && dwa[1:0] == IO_LED[1:0]) led <= dwd[4:0];
    end

    // ---- read data: RAM or I/O, both one cycle after the address ------------------------
    logic [15:0] io_q;
    logic        io_sel;
    always_ff @(posedge cclk) begin
        io_sel <= io_rd;
        case (daddr[1:0])
            IO_UART_STATUS[1:0]: io_q <= {14'd0, rx_full, tx_busy};
            IO_UART_RX[1:0]:     io_q <= {8'd0, rx_byte};
            default:             io_q <= '0;
        endcase
    end
    assign drd = io_sel ? io_q : ram_q;
endmodule
