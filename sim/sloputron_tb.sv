// Self-checking testbench for rtl/board/sloputron.sv running programs/demo.s at the real
// 12 MHz clock and 115200 baud. A host model checks the banner, which carries the crc16
// that thread 2 computed and handed to thread 0. It then checks the echo with the three
// runs from uart_echo_tb, and that thread 1 has driven the LED port.
`timescale 1ns/1ps
`default_nettype none
module sloputron_tb;
    localparam real   CLK_NS  = 1000.0 / 12.0;
    localparam int    N_BYTES = 48;
    localparam string BANNER  = "sloputron-1 crc16=29B1\r\n";

    logic clk = 0, rx = 1;
    wire  tx;
    wire [4:0] led;
    always #(CLK_NS / 2) clk = ~clk;

    sloputron dut (.clk, .uart_rx(rx), .uart_tx(tx), .led);

    real host_bit_ns = 1.0e9 / 115200.0;

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

    initial begin
        #60ms;
        $display("FAIL: watchdog timeout");
        $fatal;
    end

    bit led_written = 0;
    always @(posedge clk) if (dut.dwe && &dut.dwa) led_written <= 1;

    string got;
    initial begin
        logic [7:0] b;
        got = "";
        for (int i = 0; i < BANNER.len(); i++) begin
            recv(b);
            got = {got, string'(b)};
        end
        if (got != BANNER) begin
            errors++;
            $display("FAIL: banner %p, expected %p", got, BANNER);
        end else $display("banner: %s", got.substr(0, got.len() - 3));
        run(0.0, 0);
        run(-2.0, 0);
        run(+2.0, 1);
        if (!led_written) begin errors++; $display("FAIL: thread 1 never wrote the LEDs"); end
        if (errors == 0) $display("PASS");
        else begin $display("FAIL: %0d errors", errors); $fatal; end
        $finish;
    end
endmodule
