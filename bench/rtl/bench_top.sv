// Benchmark harness for F1 and F5 (D-005). It is the skeleton harness (skel/rtl/skel_top.sv)
// with sizes as parameters:
//   program ROM  2**ROMA x 16, synchronous read
//   data RAM     DEPTH x 16 at data addresses 0 .. DEPTH-1 (DA address bits), one read port,
//                one write port
//   output port  a store to the all-ones data address latches the low 5 bits onto the
//                LEDs. The benchmark programs store there when they finish.
// With ROMA = 11, DEPTH = 256 and DA = 8 this is the standard skeleton harness, where cells
// and Fmax are measured. The benchmark simulations use DA = 12 and DEPTH = 4096.
// CORE: 1 = F1 barrel (N threads), 5 = F5 single thread (FWD = forwarding),
//       0 = the CPU core itself (rtl/core/f1_core.sv, ISA 1.0 = r_f1 with X = 7), used only
//       to check it against the kernels; its start-up hold is cut to 16 clocks.
`default_nettype none
module bench_top #(
    parameter int    CORE  = 1,
    parameter int    N     = 4,
    parameter bit    FWD   = 0,
    parameter int    X     = 0,                     // F1 ISA study extensions (r_f1.sv, D-008)
    parameter int    ROMA  = 11,
    parameter int    DEPTH = 256,
    parameter int    DA    = 8,
    parameter string ROM   = "skel_rom.hex",
    parameter string RAM   = "skel_ram.hex"
) (
    input  wire        clk,
    output logic [4:0] led
);
    wire  [10:0]   iaddr;
    logic [15:0]   insn;
    wire  [DA-1:0] daddr, dwa;
    logic [15:0]   drd;
    wire  [15:0]   dwd;
    wire           dwe;

    (* ram_style = "block" *)              logic [15:0] rom [2 ** ROMA];
    (* ram_style = "block", no_rw_check *) logic [15:0] ram [DEPTH];
    initial $readmemh(ROM, rom);
    initial $readmemh(RAM, ram);
    always_ff @(posedge clk) insn <= rom[iaddr[ROMA-1:0]];
    always_ff @(posedge clk) begin
        if (dwe) ram[dwa] <= dwd;
        drd <= ram[daddr];
    end
    always_ff @(posedge clk) if (dwe && &dwa) led <= dwd[4:0];

    generate if (CORE == 0) begin : g_core
        /* verilator lint_off PINCONNECTEMPTY */
        f1_core #(.N(N), .DA(DA), .STARTUP(16)) cpu (.clk, .run(1'b1), .iaddr, .insn, .daddr,
                                                    .dre(), .drd, .dwe, .dwa, .dwd,
        .rvfi_valid(), .rvfi_thread(), .rvfi_pc(), .rvfi_insn(), .rvfi_pc_next(), .rvfi_c(),
        .rvfi_rd_we(), .rvfi_rd(), .rvfi_rd_wdata(), .rvfi_mem_re(), .rvfi_mem_we(),
        .rvfi_mem_addr(), .rvfi_mem_rdata(), .rvfi_mem_wdata());
        /* verilator lint_on PINCONNECTEMPTY */
    end else if (CORE == 1) begin : g_f1
        r_f1 #(.N(N), .DA(DA), .X(X)) cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd);
    end else begin : g_f5
        r_f5 #(.FWD(FWD), .DA(DA)) cpu (.clk, .iaddr, .insn, .daddr, .drd, .dwe, .dwa, .dwd);
    end endgenerate
endmodule
