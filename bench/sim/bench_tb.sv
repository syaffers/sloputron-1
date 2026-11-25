// D-002 benchmarks on F1 and F5 (D-005), plus a pseudo-random hazard test. Each run loads one kernel (bench/kernels.py) into
// bench_top with a 4096-word data memory and waits until every thread has stored to the
// done address (0xFFF). It then compares the whole data memory, except that shared done
// word, with the image the reference interpreter expects. It prints the cycle count to the last thread's done
// store; all N copies run at once.
`timescale 1ns/1ps
`default_nettype none
module bench_run #(parameter int CORE = 1, parameter int N = 4, parameter bit FWD = 0,
                   parameter int X = 0,
                   parameter string KERNEL = "crc16", parameter string NAME = "") (
    output logic done, output logic pass
);
    localparam int    THREADS = CORE == 5 ? 1 : N;
    localparam string DIR     = $sformatf("build/bench/x%0d/", X);
    localparam string DATA    = $sformatf("%s%s_n%0d_data.hex", DIR, KERNEL, THREADS);
    localparam string EXPECT  = $sformatf("%s%s_n%0d_expect.hex", DIR, KERNEL, THREADS);

    logic clk = 0;
    always #5 clk = ~clk;
    wire [4:0] led;
    bench_top #(.CORE(CORE), .N(N), .FWD(FWD), .X(X), .DEPTH(4096), .DA(12),
                .ROM({DIR, KERNEL, ".hex"}), .RAM(DATA)) dut (.clk, .led);

    logic [15:0] expect_mem [4096];
    initial $readmemh(EXPECT, expect_mem);

    int cycles = 0, finished = 0, wrong = 0;
    initial begin
        done = 0; pass = 0;
        while (cycles < 2_000_000 && finished < THREADS) begin
            @(posedge clk);
            cycles++;
            if (dut.dwe && &dut.dwa) finished++;
        end
        repeat (20) @(posedge clk);
        for (int i = 0; i < 4095; i++)               // 0xFFF is the done port: last writer wins
            if (dut.ram[i] !== expect_mem[i]) begin
                if (wrong < 5) $display("%s %s: D[%03h] = %04h, expected %04h", NAME, KERNEL, i,
                                        dut.ram[i], expect_mem[i]);
                wrong++;
            end
        pass = finished == THREADS && wrong == 0;
        $display("%-28s %-7s %0d/%0d done, %0d words wrong, cycles %0d", NAME, KERNEL, finished,
                 THREADS, wrong, cycles);
        done = 1;
    end
endmodule

module bench_core #(parameter int CORE = 1, parameter int N = 4, parameter bit FWD = 0,
                    parameter int X = 0,
                    parameter string NAME = "") (output logic done, output logic pass);
    wire [4:0] d, p;
    bench_run #(.CORE(CORE), .N(N), .FWD(FWD), .X(X), .KERNEL("crc16"),  .NAME(NAME)) k0 (.done(d[0]), .pass(p[0]));
    bench_run #(.CORE(CORE), .N(N), .FWD(FWD), .X(X), .KERNEL("sort"),   .NAME(NAME)) k1 (.done(d[1]), .pass(p[1]));
    bench_run #(.CORE(CORE), .N(N), .FWD(FWD), .X(X), .KERNEL("mul16"),  .NAME(NAME)) k2 (.done(d[2]), .pass(p[2]));
    bench_run #(.CORE(CORE), .N(N), .FWD(FWD), .X(X), .KERNEL("memcpy"), .NAME(NAME)) k3 (.done(d[3]), .pass(p[3]));
    bench_run #(.CORE(CORE), .N(N), .FWD(FWD), .X(X), .KERNEL("hazard"), .NAME(NAME)) k4 (.done(d[4]), .pass(p[4]));
    assign done = &d;
    assign pass = &p;
endmodule

module bench_finish #(parameter int K = 2) (input wire [K-1:0] d, input wire [K-1:0] p);
    initial begin
        wait (&d);
        if (&p) $display("PASS");
        else $fatal(1, "FAIL");
        $finish;
    end
endmodule

// F1: ISA v3 with 4 and 8 threads, then the ISA study variants (X, D-008) with 4 threads.
// X bit 3 (unrolled kernels) is software only: r_f1 ignores it.
module r_f1_tb;
    wire [7:0] d, p;
    bench_core #(.CORE(1), .N(4), .NAME("F1, 4 threads"))      a (.done(d[0]), .pass(p[0]));
    bench_core #(.CORE(1), .N(8), .NAME("F1, 8 threads"))      b (.done(d[1]), .pass(p[1]));
    bench_core #(.CORE(1), .N(4), .X(1), .NAME("F1 x1, 4 threads")) c (.done(d[2]), .pass(p[2]));
    bench_core #(.CORE(1), .N(4), .X(2), .NAME("F1 x2, 4 threads")) e (.done(d[3]), .pass(p[3]));
    bench_core #(.CORE(1), .N(4), .X(3), .NAME("F1 x3, 4 threads")) g (.done(d[4]), .pass(p[4]));
    bench_core #(.CORE(1), .N(4), .X(7), .NAME("F1 x7, 4 threads")) h (.done(d[5]), .pass(p[5]));
    bench_core #(.CORE(1), .N(4), .X(11), .NAME("F1 x11, 4 threads")) i (.done(d[6]), .pass(p[6]));
    bench_core #(.CORE(1), .N(4), .X(15), .NAME("F1 x15, 4 threads")) j (.done(d[7]), .pass(p[7]));
    bench_finish #(.K(8)) f (.d, .p);
endmodule

// The CPU core (rtl/core/f1_core.sv, ISA 1.0) on the kernels with every extension (X = 15)
module f1_core_tb;
    wire [0:0] d, p;
    bench_core #(.CORE(0), .N(4), .X(15), .NAME("f1_core, ISA 1.0")) a (.done(d[0]), .pass(p[0]));
    bench_finish #(.K(1)) f (.d, .p);
endmodule

module r_f5_tb;
    wire [1:0] d, p;
    bench_core #(.CORE(5), .FWD(0), .NAME("F5, stalls"))     a (.done(d[0]), .pass(p[0]));
    bench_core #(.CORE(5), .FWD(1), .NAME("F5, forwarding")) b (.done(d[1]), .pass(p[1]));
    bench_finish f (.d, .p);
endmodule
