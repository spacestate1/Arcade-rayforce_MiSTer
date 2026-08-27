//============================================================================
//  Explicit dual-port block RAM, one-cycle read -- NO INFERENCE.
//
//  Ported from Arcade_propcycle_MiSTer/rtl/pc_bram.sv.
//  Why this exists: quartus_map 17.0 balloons past 6.6 GB and never finishes
//  trying to infer large byte-sliced arrays. Instantiating altsyncram
//  directly makes the mapping a lookup instead of a search.
//
//  Timing contract, BOTH branches: write port A and read port B, the read
//  address is registered by the RAM, output is unregistered -- data for
//  the address presented in cycle N is valid during cycle N+1.
//
//  Byte-enabled memories are built as one instance per byte lane.
//============================================================================

module rf_bram #(
    parameter WIDTH = 8,
    parameter AW    = 10
) (
    input  wire             clk,
    input  wire [AW-1:0]    waddr,
    input  wire [WIDTH-1:0] wdata,
    input  wire             wren,
    input  wire [AW-1:0]    raddr,
    output wire [WIDTH-1:0] q
);

`ifdef VERILATOR

    reg [WIDTH-1:0] mem [0:(2**AW)-1] /*verilator public*/;
    reg [WIDTH-1:0] q_r;
    always @(posedge clk) begin
        if (wren) mem[waddr] <= wdata;
        q_r <= mem[raddr];
    end
    assign q = q_r;

`else

    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .width_a(WIDTH), .widthad_a(AW),
        .width_b(WIDTH), .widthad_b(AW),
        .numwords_a(2**AW), .numwords_b(2**AW),
        .address_reg_b("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .lpm_type("altsyncram"),
        .intended_device_family("Cyclone V")
    ) r (
        .clock0(clk),
        .address_a(waddr), .data_a(wdata), .wren_a(wren),
        .address_b(raddr), .q_b(q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(1'b1), .byteena_b(1'b1),
        .clock1(1'b1), .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .data_b({WIDTH{1'b1}}), .eccstatus(),
        .q_a(), .rden_a(1'b1), .rden_b(1'b1), .wren_b(1'b0)
    );

`endif

endmodule
