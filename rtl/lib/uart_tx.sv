// Minimal 8N1 UART transmitter. Assert `start` for one clock while `busy` is low.
`default_nettype none
module uart_tx #(
    parameter int CLKS_PER_BIT = 104
) (
    input  wire       clk,
    input  wire       start,
    input  wire [7:0] data,
    output wire       tx,
    output wire       busy
);
    localparam int CW = $clog2(CLKS_PER_BIT);

    logic [8:0]    shift = '1;                  // {data, start}; shifts in 1s (stop/idle)
    logic [3:0]    left  = '0;                  // bits still to send incl. stop
    logic [CW-1:0] count = '0;

    assign tx   = shift[0];
    assign busy = (left != 0);

    always_ff @(posedge clk) begin
        if (!busy) begin
            if (start) begin
                shift <= {data, 1'b0};
                left  <= 4'd10;
                count <= CW'(CLKS_PER_BIT - 1);
            end
        end else if (count != 0) begin
            count <= count - 1'b1;
        end else begin
            shift <= {1'b1, shift[8:1]};
            left  <= left - 1'b1;
            count <= CW'(CLKS_PER_BIT - 1);
        end
    end
endmodule
