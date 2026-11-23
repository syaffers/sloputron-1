// LIFO stack with the top entry in flip-flops and everything below it in one BRAM.
//
// Interface and behaviour match swapforth's stack2 (the J1a stacks) for any sequence that
// stays within DEPTH entries below the top:
//   rd     = top entry (registered)
//   delta  = {dir, move}: 01 push, 11 pop, 10 also pops one (as stack2 does), 00 no move
//   we     = write wd into the top. On a push the old top moves down; on a pop the entry
//            below comes up, then is overwritten if we is set.
// Overflow and underflow differ from stack2: the BRAM pointer wraps, while stack2 drops the
// bottom entry and fills with 16'h55aa.
//
// No bypass register is needed. The write port runs every cycle on the falling clock edge,
// writing the top into the dead slot just above the stored part (mem[p+1]). A push makes
// that slot live, and the read at the next rising edge already sees the new value. iCE40
// BRAM inverts its clocks for free (SB_RAM40_4KNW), so the only cost is a half-cycle path
// from `head` and `p` to the BRAM write port.
`default_nettype none
module stack_bram #(
    parameter int W     = 16,
    parameter int DEPTH = 15,                    // entries below the top that must survive
    localparam int AW   = $clog2(DEPTH + 1)
) (
    input  wire          clk,
    output wire  [W-1:0] rd,
    input  wire          we,
    input  wire  [1:0]   delta,
    input  wire  [W-1:0] wd
);
    (* ram_style = "block" *) logic [W-1:0] mem [0:(1<<AW)-1];
    logic [W-1:0]  head  = '0;
    logic [W-1:0]  below;                        // mem[p]: the BRAM's own output register
                                                 // (no initial value, or Yosys builds FFs)
    logic [AW-1:0] p     = '0;                   // index of the entry just below the top
    wire  [AW-1:0] pN    = !delta[0] ? p : delta[1] ? p - 1'b1 : p + 1'b1;

    always_ff @(negedge clk) mem[p + 1'b1] <= head;

    always_ff @(posedge clk) begin
        below <= mem[pN];
        p     <= pN;
        if (we | delta[0]) head <= we ? wd : below;
    end

    assign rd = head;
endmodule
