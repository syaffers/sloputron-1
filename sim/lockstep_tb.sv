// Lockstep check of the CPU against the C ISS (iss/, through iss/dpi.c).
//
// Each run puts a program in a full board design (rtl/board/sloputron.sv, 12 MHz) and
// hands every instruction the core finishes (f1_core's rvfi_* retirement port) to its own
// ISS, which executes the same instruction and compares the thread, PC, word, next PC,
// carry flag, register write and data access. After the start-up hold the core must finish
// exactly one instruction every clock. A host model sends random bytes to the UART all the
// time, so UART reads see real data.
// Programs:
//   demo, stress           programs/*.s (the board demo and the clock-sweep test)
//   rand0 .. rand3         every ROM word uniformly random: every encoding, reserved ones too
//   mix0 .. mix3           random canonical instructions, weighted towards data traffic,
//                          carry use and branches (iss/random_rom.py)
`timescale 1ns/1ps
`default_nettype none

import "DPI-C" function int iss_open(input string rom);
import "DPI-C" function int iss_retire(input int h, input int thread, input int pc, input int insn,
    input int pc_next, input int c, input int rd_we, input int rd, input int rd_wdata,
    input int mem_re, input int mem_we, input int mem_addr, input int mem_rdata,
    input int mem_wdata);
import "DPI-C" function int iss_checked(input int h);
import "DPI-C" function int iss_errors(input int h);

module lockstep_run #(
    parameter string ROM    = "build/programs/demo.hex",
    parameter string NAME   = "demo",
    parameter int    CLOCKS = 200_000
) (
    output logic done,
    output logic pass
);
    localparam real CLK_NS = 1000.0 / 12.0;
    localparam real BIT_NS = 1.0e9 / 115200.0;

    logic clk = 0, rx = 1;
    wire  tx;
    wire [4:0] led;
    always #(CLK_NS / 2) clk = ~clk;
    sloputron #(.ROM(ROM)) dut (.clk, .uart_rx(rx), .uart_tx(tx), .led);

    // host: random bytes with random gaps
    logic [7:0] b;
    initial forever begin
        b = 8'($urandom);
        #(BIT_NS * ($urandom % 40));
        rx = 0; #(BIT_NS);
        for (int i = 0; i < 8; i++) begin rx = b[i]; #(BIT_NS); end
        rx = 1; #(BIT_NS);
    end

    int h, cycles = 0, retired = 0, gaps = 0;
    bit started = 0;
    initial begin
        done = 0; pass = 0;
        h = iss_open(ROM);
        if (h < 0) $fatal(1, "%s: cannot open %s", NAME, ROM);
        while (cycles < CLOCKS) begin
            @(posedge clk);
            cycles++;
            if (dut.cpu.rvfi_valid) begin
                started = 1;
                retired++;
                void'(iss_retire(h, int'(dut.cpu.rvfi_thread), int'(dut.cpu.rvfi_pc),
                    int'(dut.cpu.rvfi_insn), int'(dut.cpu.rvfi_pc_next), int'(dut.cpu.rvfi_c),
                    int'(dut.cpu.rvfi_rd_we), int'(dut.cpu.rvfi_rd), int'(dut.cpu.rvfi_rd_wdata),
                    int'(dut.cpu.rvfi_mem_re), int'(dut.cpu.rvfi_mem_we),
                    int'(dut.cpu.rvfi_mem_addr), int'(dut.cpu.rvfi_mem_rdata),
                    int'(dut.cpu.rvfi_mem_wdata)));
            end else if (started) gaps++;              // the barrel must finish one per clock
        end
        pass = started && gaps == 0 && iss_errors(h) == 0 && iss_checked(h) == retired;
        $display("%-7s %0d instructions checked, %0d mismatches, %0d idle clocks: %s", NAME,
                 iss_checked(h), iss_errors(h), gaps, pass ? "ok" : "FAIL");
        done = 1;
    end
endmodule

module lockstep_tb;
    localparam int K = 10;
    wire [K-1:0] d, p;
    lockstep_run #(.ROM("build/programs/demo.hex"),   .NAME("demo"))   r0 (.done(d[0]), .pass(p[0]));
    lockstep_run #(.ROM("build/programs/stress.hex"), .NAME("stress")) r1 (.done(d[1]), .pass(p[1]));
    lockstep_run #(.ROM("build/lockstep/rand0.hex"),  .NAME("rand0"))  r2 (.done(d[2]), .pass(p[2]));
    lockstep_run #(.ROM("build/lockstep/rand1.hex"),  .NAME("rand1"))  r3 (.done(d[3]), .pass(p[3]));
    lockstep_run #(.ROM("build/lockstep/rand2.hex"),  .NAME("rand2"))  r4 (.done(d[4]), .pass(p[4]));
    lockstep_run #(.ROM("build/lockstep/rand3.hex"),  .NAME("rand3"))  r5 (.done(d[5]), .pass(p[5]));
    lockstep_run #(.ROM("build/lockstep/mix0.hex"),   .NAME("mix0"))   r6 (.done(d[6]), .pass(p[6]));
    lockstep_run #(.ROM("build/lockstep/mix1.hex"),   .NAME("mix1"))   r7 (.done(d[7]), .pass(p[7]));
    lockstep_run #(.ROM("build/lockstep/mix2.hex"),   .NAME("mix2"))   r8 (.done(d[8]), .pass(p[8]));
    lockstep_run #(.ROM("build/lockstep/mix3.hex"),   .NAME("mix3"))   r9 (.done(d[9]), .pass(p[9]));
    initial begin
        wait (&d);
        if (&p) $display("PASS");
        else $fatal(1, "FAIL");
        $finish;
    end
endmodule
