// Phase 2 skeleton harness, the same for all four finalists:
//   program ROM  2048 x 16 (4 KB, 8 BRAMs), synchronous read: insn = rom[iaddr] one cycle later
//   data RAM      256 x 16 (1 BRAM), one read port (drd = ram[daddr] one cycle later), one write
//   output port   a store to data address 0xFF also latches the low 5 bits onto the LEDs
// The memories are filled from hex files: random words for synthesis (so nothing can be
// constant-folded), a test program and its data in simulation.
// CORE: 1 = F1 barrel registers, 2 = F2 stack, 3 = F3 accumulator, 4 = F4 barrel stack,
//       5 = F5 single-thread registers (FWD selects forwarding; D-003).
`default_nettype none
module skel_top #(
    parameter int    CORE = 2,
    parameter int    N    = 4,               // threads (F1, F4)
    parameter bit    FWD  = 1,               // forwarding (F5)
    parameter string ROM  = "skel_rom.hex",
    parameter string RAM  = "skel_ram.hex"
) (
    input  wire        clk,
    output logic [4:0] led
);
    wire  [10:0] iaddr;
    logic [15:0] insn;
    wire  [7:0]  daddr, dwa;
    logic [15:0] drd;
    wire  [15:0] dwd;
    wire         dwe;

    (* ram_style = "block" *)                logic [15:0] rom [2048];
    (* ram_style = "block", no_rw_check *)   logic [15:0] ram [256];
    initial $readmemh(ROM, rom);
    initial $readmemh(RAM, ram);
    always_ff @(posedge clk) insn <= rom[iaddr];
    always_ff @(posedge clk) begin
        if (dwe) ram[dwa] <= dwd;
        drd <= ram[daddr];
    end
    always_ff @(posedge clk) if (dwe && dwa == 8'hff) led <= dwd[4:0];

    generate case (CORE)
        1: begin : g_f1 skel_f1 #(.N(N)) cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd); end
        2: begin : g_f2 skel_f2          cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd); end
        3: begin : g_f3 skel_f3          cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd); end
        5: begin : g_f5 skel_f5 #(.FWD(FWD)) cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd); end
        default: begin : g_f4 skel_f4 #(.N(N)) cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd); end
    endcase endgenerate
endmodule
