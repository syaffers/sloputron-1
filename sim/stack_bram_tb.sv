// stack_bram against a behavioural model of swapforth's stack2 (head + shift-register tail).
// Random push/pop/write sequences, kept within DEPTH stored entries (stack_bram documents
// different overflow behaviour). Checks `rd` every cycle at both depths J1a uses (15 and 17).
`timescale 1ns/1ps
`default_nettype none
/* verilator lint_off BLKSEQ */   // per-cycle temporaries in the stimulus process
module stack_check #(parameter int DEPTH = 15, parameter int N = 200_000, parameter int SEED = 1) (
    input wire clk, output logic done
);
    logic        we = 0;
    logic [1:0]  delta = 0;
    logic [15:0] wd = 0;
    wire  [15:0] rd;
    stack_bram #(.W(16), .DEPTH(DEPTH)) dut(.clk, .rd, .we, .delta, .wd);

    // reference: stack2 semantics
    logic [15:0] head = 0;
    logic [15:0] tail [DEPTH];
    int depth = 0, cycles = 0, errors = 0, max_seen = 0;
    int unsigned rng = SEED;
    int unsigned r;                              // per-cycle temporaries
    int          d;
    logic [1:0]  nd;
    initial begin
        foreach (tail[i]) tail[i] = 0;
        done = 0;
    end

    function automatic int unsigned xs(input int unsigned x);
        x ^= x << 13; x ^= x >> 17; x ^= x << 5; return x;
    endfunction

    always @(posedge clk) begin
        // 1. reference update with the inputs the DUT samples at this edge
        if (delta[0]) begin
            if (!delta[1]) begin
                for (int i = DEPTH - 1; i > 0; i--) tail[i] <= tail[i-1];
                tail[0] <= head;
            end else begin
                for (int i = 0; i < DEPTH - 1; i++) tail[i] <= tail[i+1];
                tail[DEPTH-1] <= 16'h55aa;
            end
        end
        if (we | delta[0]) head <= we ? wd : tail[0];
        depth <= depth + (delta[0] ? (delta[1] ? -1 : 1) : 0);

        // 2. next random inputs, staying inside [0, DEPTH] stored entries
        begin
            r  = xs(rng);
            d  = depth + (delta[0] ? (delta[1] ? -1 : 1) : 0);
            rng <= r;
            case (r % 7)
                0, 1, 2: nd = 2'b01;
                3, 4:    nd = 2'b11;
                5:       nd = 2'b10;
                default: nd = 2'b00;
            endcase
            if (nd[0] && !nd[1] && d == DEPTH) nd = 2'b11;
            if (nd[0] &&  nd[1] && d == 0)     nd = 2'b01;
            delta <= nd;
            // a push without a write copies the entry below the top, which must exist
            we    <= r[8] | r[9] | (nd == 2'b01 && d == 0);
            wd    <= r[31:16];
            if (d > max_seen) max_seen <= d;
        end
        cycles <= cycles + 1;
        if (cycles == N) done <= 1;
    end

    // compare mid-cycle, after the rising-edge updates and before the next edge
    always @(negedge clk) if (!done && cycles > 0 && rd !== head) begin
        if (errors < 10) $display("DEPTH=%0d cycle %0d: rd %h, expected %h", DEPTH, cycles, rd, head);
        errors <= errors + 1;
    end
endmodule

module stack_bram_tb;
    logic clk = 0;
    always #5 clk = ~clk;
    wire done15, done17;
    stack_check #(.DEPTH(15), .SEED(1)) d15(.clk, .done(done15));
    stack_check #(.DEPTH(17), .SEED(7)) d17(.clk, .done(done17));
    initial begin
        wait (done15 && done17);
        @(negedge clk);
        $display("stack_bram DEPTH 15: %0d cycles, max depth %0d, %0d errors", d15.cycles, d15.max_seen, d15.errors);
        $display("stack_bram DEPTH 17: %0d cycles, max depth %0d, %0d errors", d17.cycles, d17.max_seen, d17.errors);
        if (d15.errors != 0 || d17.errors != 0 || d15.max_seen != 15 || d17.max_seen != 17)
            $fatal(1, "FAIL: stack_bram differs from stack2");
        $display("PASS");
        $finish;
    end
endmodule
