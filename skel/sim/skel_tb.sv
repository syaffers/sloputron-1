// Phase 2 skeleton testbench. Each skeleton runs the CRC-16/CCITT-FALSE program from
// skel/asm.py (build/skel/*.hex) in the real harness (skel_top). Every thread stores its
// result to data address 0xFF; the run passes when all of them store 0x29B1 and nothing
// else is stored there. Prints the cycle count of the last thread's result (informational:
// provisional instruction sets, hand-written code). The register cores (F1, F5) also run
// prog_reg_hz.hex, a hazard test whose correct result is also 0x29B1.
`timescale 1ns/1ps
`default_nettype none
module skel_run #(parameter int CORE = 2, parameter int N = 1, parameter bit FWD = 1,
                  parameter string PROG = "", parameter string NAME = "") (
    output logic done, output logic pass
);
    logic clk = 0;
    always #5 clk = ~clk;
    wire [4:0] led;
    skel_top #(.CORE(CORE), .N(N), .FWD(FWD), .ROM(PROG), .RAM("build/skel/data.hex")) dut (.clk, .led);

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
                    $display("%s: cycle %0d stored %04h, expected 29b1", NAME, cycles, dut.dwd);
                end
            end
        end
        repeat (200) begin                       // nothing else may reach the output
            @(posedge clk);
            if (dut.dwe && dut.dwa == 8'hff) bad++;
        end
        pass = good == THREADS && bad == 0;
        $display("%s: %0d/%0d correct, last result at cycle %0d", NAME, good, THREADS, cycles);
        done = 1;
    end
endmodule

// Up to four runs per core: the crc program, plus N = 8 threads for the barrels or the
// no-forwarding build for F5, and the hazard program for the register cores.
module skel_check #(parameter int CORE = 2) ();
    localparam bit    BARREL = CORE == 1 || CORE == 4;
    localparam bit    REG    = CORE == 1 || CORE == 5;
    localparam string PROG   = REG ? "build/skel/prog_reg.hex"
                             : CORE == 3 ? "build/skel/prog_acc.hex" : "build/skel/prog_stack.hex";
    localparam string HZ     = "build/skel/prog_reg_hz.hex";
    localparam string F      = $sformatf("F%0d", CORE);
    localparam string A      = CORE == 5 ? "forwarding" : BARREL ? "4 threads" : "1 thread";
    localparam string B      = CORE == 5 ? "no forwarding" : "8 threads";
    wire [3:0] d, p;
    skel_run #(.CORE(CORE), .N(4), .PROG(PROG), .NAME({F, " ", A, ", crc"})) r0 (.done(d[0]), .pass(p[0]));
    if (BARREL || CORE == 5) begin : second
        skel_run #(.CORE(CORE), .N(8), .FWD(0), .PROG(PROG), .NAME({F, " ", B, ", crc"}))
            r1 (.done(d[1]), .pass(p[1]));
    end else begin : no_second
        assign d[1] = 1'b1;
        assign p[1] = 1'b1;
    end
    if (REG) begin : hazard
        skel_run #(.CORE(CORE), .N(4), .PROG(HZ), .NAME({F, " ", A, ", hazards"})) r2 (.done(d[2]), .pass(p[2]));
        skel_run #(.CORE(CORE), .N(8), .FWD(0), .PROG(HZ), .NAME({F, " ", B, ", hazards"}))
            r3 (.done(d[3]), .pass(p[3]));
    end else begin : no_hazard
        assign d[3:2] = 2'b11;
        assign p[3:2] = 2'b11;
    end
    initial begin
        wait (&d);
        if (&p) $display("PASS");
        else $fatal(1, "FAIL");
        $finish;
    end
endmodule

module skel_f1_tb; skel_check #(.CORE(1)) c (); endmodule
module skel_f2_tb; skel_check #(.CORE(2)) c (); endmodule
module skel_f3_tb; skel_check #(.CORE(3)) c (); endmodule
module skel_f4_tb; skel_check #(.CORE(4)) c (); endmodule
module skel_f5_tb; skel_check #(.CORE(5)) c (); endmodule
