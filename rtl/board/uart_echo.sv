// Phase 1 flow check: echo every byte received on the FT2232H UART (115200 8N1).
// A one-byte holding register covers a byte that completes while TX is still busy,
// so back-to-back input at a slightly fast host baud is not dropped.
// LEDs: red D1..D4 = low nibble of the last byte, green D5 toggles per byte.
`default_nettype none
module uart_echo #(
    parameter int CLKS_PER_BIT = 104            // 12 MHz / 115200
) (
    input  wire       clk,
    input  wire       uart_rx,
    output wire       uart_tx,
    output logic [4:0] led = '0
);
    logic [7:0] rx_data, hold;
    logic       rx_valid, tx_busy;
    logic       pending = 1'b0;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rx(uart_rx), .data(rx_data), .valid(rx_valid));

    wire send = pending & ~tx_busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .start(send), .data(hold), .tx(uart_tx), .busy(tx_busy));

    always_ff @(posedge clk) begin
        if (rx_valid) begin
            hold     <= rx_data;
            pending  <= 1'b1;
            led[3:0] <= rx_data[3:0];
            led[4]   <= ~led[4];
        end else if (send) begin
            pending  <= 1'b0;
        end
    end
endmodule
