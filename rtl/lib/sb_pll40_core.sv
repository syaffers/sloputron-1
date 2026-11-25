// The iCE40 PLL primitive, declared as a black box so the slang front end accepts it.
// synth_ice40 passes it through and nextpnr places the real PLL. Only the ports and
// parameters used here are declared (simple feedback; values from `icepll -i 12 -o MHZ`).
// Simulation and lint skip this module: under the VERILATOR macro the board top uses the
// 12 MHz clock directly (rtl/board/sloputron.sv).
`default_nettype none
`ifndef VERILATOR
(* blackbox *)
module SB_PLL40_CORE #(
    parameter             FEEDBACK_PATH = "SIMPLE",
    parameter logic [3:0] DIVR          = 4'd0,
    parameter logic [6:0] DIVF          = 7'd0,
    parameter logic [2:0] DIVQ          = 3'd0,
    parameter logic [2:0] FILTER_RANGE  = 3'd0
) (
    input  wire REFERENCECLK,
    input  wire RESETB,
    input  wire BYPASS,
    output wire PLLOUTCORE,
    output wire PLLOUTGLOBAL,
    output wire LOCK
);
endmodule
`endif
