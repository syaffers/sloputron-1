// sloputron-1 on the iCEstick: the F1 core (rtl/core/f1_core.sv), its program ROM, data RAM,
// and a hardware UART and the LEDs on the data bus (D-007).
//   program ROM  2048 x 16 (4 KB, 8 BRAMs), filled from ROM at configuration
//   data RAM     1024 x 16 at data addresses 0x000-0x3FF (4 BRAMs), zero at configuration
//   I/O          0x800-0xFFF, decoded from address bit 11 and bits 1..0 (isa.toml [memory]):
//                0xFFC UART_TX (W), 0xFFD UART_STATUS (R), 0xFFE UART_RX (R, clears), 0xFFF LED (W)
// The clock is the board's 12 MHz oscillator. Loads take effect one cycle later (the RAM's
// synchronous read), so the I/O read data is registered the same way.
`default_nettype none
module sloputron #(
    parameter int    CLKS_PER_BIT = 104,            // 12 MHz / 115200
    parameter string ROM          = "build/programs/demo.hex"
) (
    input  wire        clk,
    input  wire        uart_rx,
    output wire        uart_tx,
    output logic [4:0] led = '0
);
    import isa_pkg::*;
    localparam int RAM_WORDS = 1024;

    wire  [10:0]          iaddr;
    logic [15:0]          insn;
    /* verilator lint_off UNUSEDSIGNAL */            // bit 10 is not decoded (RAM 9..0, I/O 11)
    wire  [DATA_BITS-1:0] daddr, dwa;
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [15:0]          dwd;
    wire                  dre, dwe;
    logic [15:0]          drd;

    f1_core cpu (.clk, .iaddr, .insn, .daddr, .dre, .drd, .dwe, .dwa, .dwd);

    // ---- memories ---------------------------------------------------------------------
    (* ram_style = "block" *)              logic [15:0] rom [2048];
    (* ram_style = "block", no_rw_check *) logic [15:0] ram [RAM_WORDS];
    initial $readmemh(ROM, rom);
    initial for (int i = 0; i < RAM_WORDS; i++) ram[i] = '0;
    always_ff @(posedge clk) insn <= rom[iaddr];

    wire io_rd = daddr[11];
    wire io_wr = dwe & dwa[11];
    logic [15:0] ram_q;
    always_ff @(posedge clk) begin
        if (dwe & !dwa[11]) ram[dwa[9:0]] <= dwd;
        ram_q <= ram[daddr[9:0]];
    end

    // ---- UART -------------------------------------------------------------------------
    logic [7:0] rx_data, rx_byte = '0;
    logic       rx_valid, rx_full = 1'b0, tx_busy;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (.clk, .rx(uart_rx), .data(rx_data), .valid(rx_valid));
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk, .start(io_wr && dwa[1:0] == IO_UART_TX[1:0] && !tx_busy), .data(dwd[7:0]),
        .tx(uart_tx), .busy(tx_busy));

    always_ff @(posedge clk) begin
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
    always_ff @(posedge clk) begin
        io_sel <= io_rd;
        case (daddr[1:0])
            IO_UART_STATUS[1:0]: io_q <= {14'd0, rx_full, tx_busy};
            IO_UART_RX[1:0]:     io_q <= {8'd0, rx_byte};
            default:             io_q <= '0;
        endcase
    end
    assign drd = io_sel ? io_q : ram_q;
endmodule
