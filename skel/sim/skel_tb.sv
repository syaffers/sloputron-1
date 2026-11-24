// Phase 2 skeleton testbench. Each skeleton runs the CRC-16/CCITT-FALSE program from
// skel/asm.py (build/skel/*.hex) in the real harness (skel_top). Every thread stores its
// result to data address 0xFF; the run passes when all of them store 0x29B1 and nothing
// else is stored there. Prints the cycle count of the last thread's result (informational:
// provisional instruction sets, hand-written code).
`timescale 1ns/1ps
`default_nettype none
module skel_run #(parameter int CORE = 2, parameter int N = 1, parameter string PROG = "") (
    output logic done, output logic pass
);
    logic clk = 0;
    always #5 clk = ~clk;
    wire [4:0] led;
    skel_top #(.CORE(CORE), .N(N), .ROM(PROG), .RAM("build/skel/data.hex")) dut (.clk, .led);

    localparam int THREADS = (CORE == 1 || CORE == 4) ? N : 1;
    int cycles = 0, good = 0, bad = 0;
    initial begin
        done = 0; pass = 0;
        while (cycles < 200_000 && good + bad < THREADS) begin
            @(posedge clk);
            cycles++;
            if (dut.dwe && dut.dwa == 8'hff) begin
                if (dut.dwd == 16'h29b1) good++;
                else begin
                    bad++;
                    $display("F%0d, %0d thread(s): cycle %0d stored %04h, expected 29b1", CORE, THREADS, cycles, dut.dwd);
                end
            end
        end
        repeat (200) begin                       // nothing else may reach the output
            @(posedge clk);
            if (dut.dwe && dut.dwa == 8'hff) bad++;
        end
        pass = good == THREADS && bad == 0;
        $display("F%0d, %0d thread(s): %0d/%0d correct, last result at cycle %0d", CORE, THREADS,
                 good, THREADS, cycles);
        done = 1;
    end
endmodule

module skel_check #(parameter int CORE = 2) ();
    localparam bit BARREL = CORE == 1 || CORE == 4;
    localparam string PROG = CORE == 1 ? "build/skel/prog_reg.hex"
                           : CORE == 3 ? "build/skel/prog_acc.hex" : "build/skel/prog_stack.hex";
    wire d0, p0, d1, p1;
    skel_run #(.CORE(CORE), .N(4), .PROG(PROG)) r0 (.done(d0), .pass(p0));
    if (BARREL) begin : n8
        skel_run #(.CORE(CORE), .N(8), .PROG(PROG)) r1 (.done(d1), .pass(p1));
    end else begin : n1
        assign d1 = 1'b1;
        assign p1 = 1'b1;
    end
    initial begin
        wait (d0 && d1);
        if (p0 && p1) $display("PASS");
        else $fatal(1, "FAIL");
        $finish;
    end
endmodule

module skel_f1_tb; skel_check #(.CORE(1)) c (); endmodule
module skel_f2_tb; skel_check #(.CORE(2)) c (); endmodule
module skel_f3_tb; skel_check #(.CORE(3)) c (); endmodule
module skel_f4_tb; skel_check #(.CORE(4)) c (); endmodule
