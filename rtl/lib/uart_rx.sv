// Minimal 8N1 UART receiver. Samples each bit at its centre; no oversampling filter.
// `valid` pulses for one clock in the middle of the stop bit when the stop bit is 1.
`default_nettype none
module uart_rx #(
    parameter int CLKS_PER_BIT = 104            // 12 MHz / 115200 = 104.17
) (
    input  wire        clk,
    input  wire        rx,
    output logic [7:0] data,
    output logic       valid
);
    localparam int CW = $clog2(CLKS_PER_BIT * 3 / 2 + 1);

    logic [1:0]    sync = 2'b11;                // metastability guard, idle high
    logic          busy = 1'b0;
    logic [CW-1:0] count = '0;
    logic [3:0]    bitn = '0;                   // 0..7 data, 8 stop

    always_ff @(posedge clk) begin
        sync  <= {sync[0], rx};
        valid <= 1'b0;
        if (!busy) begin
            if (!sync[1]) begin                 // start bit edge
                busy  <= 1'b1;
                count <= CW'(CLKS_PER_BIT * 3 / 2 - 1);  // to centre of bit 0
                bitn  <= '0;
            end
        end else if (count != 0) begin
            count <= count - 1'b1;
        end else if (bitn != 4'd8) begin
            data  <= {sync[1], data[7:1]};      // LSB first
            bitn  <= bitn + 1'b1;
            count <= CW'(CLKS_PER_BIT - 1);
        end else begin
            valid <= sync[1];                   // stop bit must be high
            busy  <= 1'b0;
        end
    end
endmodule
