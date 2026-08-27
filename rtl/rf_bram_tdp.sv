//============================================================================
//  16-bit TRUE dual-port block RAM with byte enables on both ports.
//  Ported from Arcade_propcycle_MiSTer/rtl/pc_bram_tdp.sv.
//
//  rf_bram_be is simple dual port (write A, read B), which is enough for
//  every RAM the CPU owns alone. Shared RAM (video, line, pivot) needs
//  true dual port: one port for the CPU, one for the video pipeline.
//
//  Same packing as rf_bram_be (512x16 per M10K with byteena) -- going true
//  dual port costs no extra blocks, only the read-during-write guarantee,
//  which is DONT_CARE here because port A and port B never address the
//  same word at the same time by scheduling.
//
//  Timing contract, both ports: address registered, output unregistered --
//  q is valid the cycle AFTER the address is presented, and holds until
//  the address changes.
//============================================================================

module rf_bram_tdp #(
    parameter AW = 15,                // depth 2**AW 16-bit words
    parameter INIT_FILE = "UNUSED"
) (
    input  wire          clk,

    input  wire [AW-1:0] a_addr,
    input  wire [15:0]   a_wdata,
    input  wire          a_wren,
    input  wire [1:0]    a_be,        // be[1] upper byte, be[0] lower
    output wire [15:0]   a_q,

    input  wire [AW-1:0] b_addr,
    input  wire [15:0]   b_wdata,
    input  wire          b_wren,
    input  wire [1:0]    b_be,
    output wire [15:0]   b_q
);

`ifdef VERILATOR

    // SEMANTIC NOTE: the altsyncram below is configured
    // NEW_DATA_NO_NBE_READ for same-port read-during-write, but THIS model
    // returns OLD data in that case (q_r samples mem before the write
    // lands). The difference is unreachable today -- one operation per
    // cycle per port, never a read and a write of the same word together --
    // but if a future consumer does both in one cycle, sim and silicon will
    // disagree HERE, quietly. Keep the ports one-op-per-cycle.
    reg [15:0] mem [0:(2**AW)-1] /*verilator public*/;
    reg [15:0] a_q_r, b_q_r;
    always @(posedge clk) begin
        if (a_wren) begin
            if (a_be[1]) mem[a_addr][15:8] <= a_wdata[15:8];
            if (a_be[0]) mem[a_addr][7:0]  <= a_wdata[7:0];
        end
        a_q_r <= mem[a_addr];
    end
    always @(posedge clk) begin
        if (b_wren) begin
            if (b_be[1]) mem[b_addr][15:8] <= b_wdata[15:8];
            if (b_be[0]) mem[b_addr][7:0]  <= b_wdata[7:0];
        end
        b_q_r <= mem[b_addr];
    end
    assign a_q = a_q_r;
    assign b_q = b_q_r;

`else

    altsyncram #(
        .operation_mode("BIDIR_DUAL_PORT"),
        .width_a(16), .widthad_a(AW), .numwords_a(2**AW),
        .width_b(16), .widthad_b(AW), .numwords_b(2**AW),
        .width_byteena_a(2), .width_byteena_b(2),
        .address_reg_b("CLOCK0"),
        .indata_reg_b("CLOCK0"),
        .wrcontrol_wraddress_reg_b("CLOCK0"),
        .byteena_reg_b("CLOCK0"),
        .outdata_reg_a("UNREGISTERED"),
        .outdata_reg_b("UNREGISTERED"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
        .init_file(INIT_FILE),
        .lpm_type("altsyncram"),
        .intended_device_family("Cyclone V")
    ) r (
        .clock0(clk),
        .address_a(a_addr), .data_a(a_wdata), .wren_a(a_wren),
        .byteena_a(a_be), .q_a(a_q),
        .address_b(b_addr), .data_b(b_wdata), .wren_b(b_wren),
        .byteena_b(b_be), .q_b(b_q),
        .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .clock1(1'b1), .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1),
        .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
    );

`endif

endmodule
