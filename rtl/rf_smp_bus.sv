//============================================================================
//  Sample line fetch: 8 consecutive Ensoniq sample bytes from SDRAM.
//
//  rf_gfx_bus with one plane: a request is a level held until the ram
//  domain's completion toggle comes back through a three-flop chain (the
//  CDC reasoning is in rf_gfx_bus), one 4-word burst = 8 bytes = 8 samples.
//  The region: the MRA streams the two Ensoniq ROMs plain at byte
//  0x780000, and the ES5505's word address i is byte i of that (ROADMAP
//  Phase 3), so line {bank, addr[19:3]} is SDRAM bytes 0x780000 +
//  {bank, addr[19:3], 3'b000}, word address 0x3C0000 + {bank, addr[19:3], 2'b00}.
//============================================================================

module rf_smp_bus
(
    input  logic        clk_cpu,
    input  logic        reset,

    input  logic [21:3] addr,          // {bank[1:0], sample address[19:3]}
    input  logic        req,           // one-cycle pulse
    output logic [63:0] line,          // byte k in [8k +: 8]
    output logic        valid,         // one-cycle pulse
    output logic        busy,

    input  logic        clk_ram,
    output logic [26:1] ch_addr,
    input  logic [63:0] ch_dout,
    output logic        ch_req,
    input  logic        ch_ready
);
    localparam logic [26:1] BASE = 26'h740000;      // byte 0xE80000

    /* verilator lint_off PROCASSINIT */
    logic done_t = 1'b0;
    /* verilator lint_on PROCASSINIT */
    logic [63:0] ram_line;
    always_ff @(posedge clk_ram) begin
        if (ch_ready) begin ram_line <= ch_dout; done_t <= ~done_t; end
    end

    logic d_s, d_1, d_2, d_3;
    always_ff @(posedge clk_cpu) begin
        d_s <= done_t; d_1 <= d_s; d_2 <= d_1; d_3 <= d_2;
    end
    wire d_edge = d_2 ^ d_3;

    always_ff @(posedge clk_cpu) begin
        valid <= 1'b0;
        if (reset) begin
            busy   <= 1'b0;
            ch_req <= 1'b0;
        end else if (!busy) begin
            if (req) begin
                ch_addr <= BASE + {5'd0, addr, 2'b00};
                ch_req  <= 1'b1;
                busy    <= 1'b1;
            end
        end else if (d_edge) begin
            ch_req <= 1'b0;
            busy   <= 1'b0;
            line   <= ram_line;
            valid  <= 1'b1;
        end
    end

endmodule
