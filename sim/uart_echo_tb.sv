// Self-checking testbench for rtl/board/uart_echo.sv at the real divisor.
// A host model drives uart_rx at a configurable baud error and checks every echoed byte.
// Run: make sim
`timescale 1ns/1ps
`default_nettype none
module uart_echo_tb;
    localparam real CLK_NS  = 1000.0 / 12.0;           // 12 MHz
    localparam int  N_BYTES = 64;

    logic clk = 0, rx = 1;
    wire  tx;
    wire [4:0] led;
    always #(CLK_NS / 2) clk = ~clk;

    uart_echo dut (.clk(clk), .uart_rx(rx), .uart_tx(tx), .led(led));

    // Host bit time: nominal 115200 baud, optionally skewed (+ = host faster).
    real host_bit_ns;

    task automatic send(input logic [7:0] b);
        rx = 0; #(host_bit_ns);
        for (int i = 0; i < 8; i++) begin rx = b[i]; #(host_bit_ns); end
        rx = 1; #(host_bit_ns);
    endtask

    task automatic recv(output logic [7:0] b);
        @(negedge tx);
        #(host_bit_ns * 1.5);
        for (int i = 0; i < 8; i++) begin b[i] = tx; #(host_bit_ns); end
        if (tx !== 1'b1) begin $display("FAIL: bad stop bit"); $fatal; end
    endtask

    logic [7:0] sent [N_BYTES];
    int errors = 0;

    task automatic run(input real skew_pct, input int gap_bits);
        logic [7:0] got;
        host_bit_ns = (1.0e9 / 115200.0) / (1.0 + skew_pct / 100.0);
        for (int i = 0; i < N_BYTES; i++) sent[i] = 8'($urandom);
        fork
            for (int i = 0; i < N_BYTES; i++) begin send(sent[i]); #(host_bit_ns * gap_bits); end
            for (int i = 0; i < N_BYTES; i++) begin
                recv(got);
                if (got !== sent[i]) begin
                    errors++;
                    $display("FAIL skew %0.1f%%: byte %0d sent %02x got %02x", skew_pct, i, sent[i], got);
                end
            end
        join
        $display("skew %0.1f%%, gap %0d bit(s): %0d bytes echoed", skew_pct, gap_bits, N_BYTES);
    endtask

    // Watchdog: 3 runs x 64 bytes x ~87 us/byte is ~17 ms of simulated time.
    initial begin
        #50ms;
        $display("FAIL: watchdog timeout (no echo?)");
        $fatal;
    end

    initial begin
        #(CLK_NS * 10);
        run(0.0, 0);    // nominal, back-to-back: exercises the holding register
        run(-2.0, 0);   // host 2% slow, back-to-back
        run(+2.0, 1);   // host 2% fast: RX tolerance. Needs a gap; a faster sender can
                        // never be echoed back-to-back indefinitely at the same baud.
        if (errors == 0) $display("PASS");
        else begin $display("FAIL: %0d errors", errors); $fatal; end
        $finish;
    end
endmodule
