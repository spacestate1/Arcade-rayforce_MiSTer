//============================================================================
//  16-bit dual-port block RAM with native byte enables, explicit altsyncram.
//
//  Ported from Arcade_propcycle_MiSTer/rtl/pc_bram_be.sv.
//  One 16-bit RAM with byteena packs at 512x16 per M10K -- paired 8-bit
//  lanes pack at 1024x8 and DOUBLE the block count.
//
//  Same timing contract as rf_bram: write port A, read port B, one-cycle
//  read (address registered, output unregistered).
//============================================================================

module rf_bram_be #(
    parameter AW = 10,                // depth 2**AW 16-bit words
    parameter INIT_FILE = "UNUSED"    // optional MIF baked into the bitstream
) (
    input  wire          clk,
    input  wire [AW-1:0] waddr,
    input  wire [15:0]   wdata,
    input  wire          wren,
    input  wire [1:0]    be,          // be[1] = upper byte, be[0] = lower
    input  wire [AW-1:0] raddr,
    output wire [15:0]   q
);

`ifdef VERILATOR

    reg [15:0] mem [0:(2**AW)-1] /*verilator public*/;
    reg [15:0] q_r;
    always @(posedge clk) begin
        if (wren) begin
            if (be[1]) mem[waddr][15:8] <= wdata[15:8];
            if (be[0]) mem[waddr][7:0]  <= wdata[7:0];
        end
        q_r <= mem[raddr];
    end
    assign q = q_r;

`else

    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .width_a(16), .widthad_a(AW), .numwords_a(2**AW),
        .width_b(16), .widthad_b(AW), .numwords_b(2**AW),
        .width_byteena_a(2),
        .address_reg_b("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"),
        // OLD_DATA, not DONT_CARE: waddr and raddr are the SAME address on
        // every CPU access here, so every write is a same-address
        // read-during-write and DONT_CARE leaves what port B returns
        // that cycle undefined -- the fitter may hand back anything.
        // OLD_DATA makes it deterministic (the previous contents), which
        // is what the one-cycle read contract already assumes.
        .read_during_write_mode_mixed_ports("OLD_DATA"),
        .init_file(INIT_FILE),
        .lpm_type("altsyncram"),
        .intended_device_family("Cyclone V")
    ) r (
        .clock0(clk),
        .address_a(waddr), .data_a(wdata), .wren_a(wren), .byteena_a(be),
        .address_b(raddr), .q_b(q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_b(1'b1),
        .clock1(1'b1), .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .data_b(16'hFFFF), .eccstatus(),
        .q_a(), .rden_a(1'b1), .rden_b(1'b1), .wren_b(1'b0)
    );

`endif

endmodule
