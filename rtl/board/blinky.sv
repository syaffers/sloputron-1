// Phase 1 flow check: the four red LEDs show a binary count (~1.4 Hz LSB)
// and the green LED blinks at ~0.7 Hz. No reset needed: iCE40 FFs power up to 0.
`default_nettype none
module blinky (
    input  wire       clk,   // 12 MHz
    output wire [4:0] led
);
    logic [26:0] count = '0;
    always_ff @(posedge clk) count <= count + 1'b1;

    assign led[3:0] = count[26:23];
    assign led[4]   = count[23];
endmodule
