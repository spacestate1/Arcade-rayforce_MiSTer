//============================================================================
//  Dual-clock dual-port block RAM, explicit altsyncram (no inference).
//  Ported from Arcade_propcycle_MiSTer/rtl/pc_bram_dc.sv.
//
//  Port A: read/write on clk_a (the CPU side).
//  Port B: read-only on clk_b (the video side), optionally WIDER than port
//  A by RATIO_B (power of two).
//
//  One-cycle reads on both ports (address registered by the RAM, output
//  unregistered), matching rf_bram.
//============================================================================

module rf_bram_dc #(
    parameter WIDTH_A = 16,
    parameter AW_A    = 10,          // depth 2**AW_A words of WIDTH_A
    parameter RATIO_B = 1            // port B width = WIDTH_A * RATIO_B
) (
    input  wire                        clk_a,
    input  wire [AW_A-1:0]             addr_a,
    input  wire [WIDTH_A-1:0]          wdata_a,
    input  wire                        wren_a,
    output wire [WIDTH_A-1:0]          q_a,

    input  wire                        clk_b,
    input  wire [AW_A-$clog2(RATIO_B)-1:0] addr_b,
    output wire [WIDTH_A*RATIO_B-1:0]  q_b
);

    localparam AW_B    = AW_A - $clog2(RATIO_B);
    localparam WIDTH_B = WIDTH_A * RATIO_B;

`ifdef VERILATOR

    reg [WIDTH_A-1:0] mem [0:(2**AW_A)-1] /*verilator public*/;
    reg [WIDTH_A-1:0] qa_r;
    reg [WIDTH_B-1:0] qb_r;
    always @(posedge clk_a) begin
        if (wren_a) mem[addr_a] <= wdata_a;
        qa_r <= mem[addr_a];
    end
    // Altera mixed-width convention: port-A word (RATIO*b + i) appears in
    // q_b bits [i*WIDTH_A +: WIDTH_A] -- LOWEST address in the LOW slice.
    integer i;
    always @(posedge clk_b) begin
        for (i = 0; i < RATIO_B; i = i + 1)
            qb_r[i*WIDTH_A +: WIDTH_A] <= mem[addr_b * RATIO_B + i];
    end
    assign q_a = qa_r;
    assign q_b = qb_r;

`else

    altsyncram #(
        .operation_mode("BIDIR_DUAL_PORT"),
        .width_a(WIDTH_A), .widthad_a(AW_A), .numwords_a(2**AW_A),
        .width_b(WIDTH_B), .widthad_b(AW_B), .numwords_b(2**AW_B),
        .address_reg_b("CLOCK1"),
        .outdata_reg_a("UNREGISTERED"),
        .outdata_reg_b("UNREGISTERED"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .lpm_type("altsyncram"),
        .intended_device_family("Cyclone V")
    ) r (
        .clock0(clk_a), .clock1(clk_b),
        .address_a(addr_a), .data_a(wdata_a), .wren_a(wren_a), .q_a(q_a),
        .address_b(addr_b), .data_b({WIDTH_B{1'b1}}), .wren_b(1'b0), .q_b(q_b),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(1'b1), .byteena_b(1'b1),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );

`endif

endmodule
