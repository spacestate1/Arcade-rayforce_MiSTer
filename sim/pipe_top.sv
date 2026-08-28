// Bench wrapper: rf_video_pipe with the two sprite gfx planes merged onto
// ONE shared channel through rf_spr_ch_share -- the wiring Rayforce.sv uses
// on the real controller (only ch4 is free), so the arbiter is covered by
// the pipe regression instead of meeting hardware untested. The shared
// channel also serialises the two plane fetches, which is the real timing
// the draw FSM's prefetch has to hide.
module pipe_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        clk_ram,

    input  logic  [2:0] div,
    input  logic  [8:0] hcnt,
    input  logic  [8:0] vcnt,
    input  logic        hblank,
    input  logic        vblank,
    input  logic        rate_60,

    input  logic [7:0][15:0] ctrl0,
    input  logic [7:0][15:0] ctrl1,
    input  logic        flip,

    output logic [14:0] line_addr,
    input  logic [15:0] line_q,
    output logic [13:0] pf_addr,
    input  logic [15:0] pf_q,
    output logic [13:0] pal_addr,
    input  logic [15:0] pal_q,
    output logic [11:0] text_addr,
    input  logic [15:0] text_q,
    output logic [11:0] char_addr,
    input  logic [15:0] char_q,
    output logic [14:0] pivot_addr,
    input  logic [15:0] pivot_q,

    output logic [26:1] ch1_addr,
    input  logic [63:0] ch1_dout,
    output logic        ch1_req,
    input  logic        ch1_ready,
    output logic [26:1] ch2_addr,
    input  logic [63:0] ch2_dout,
    output logic        ch2_req,
    input  logic        ch2_ready,

    output logic [14:0] spr_addr,
    input  logic [15:0] spr_q,

    // the one shared sprite gfx channel (ch4 on the real board)
    output logic [26:1] sps_addr,
    input  logic [63:0] sps_dout,
    output logic        sps_req,
    input  logic        sps_ready,

    output logic [23:0] rgb,

    output logic [31:0] dbg_lines,
    output logic [31:0] dbg_fetch,
    output logic [31:0] dbg_max,
    output logic [31:0] dbg_nz,
    output logic [31:0] dbg_spr,
    output logic [31:0] dbg_rec
);

    logic [26:1] a_lo_addr, a_hi_addr, b_lo_addr, b_hi_addr;
    logic [63:0] a_lo_dout, a_hi_dout, b_lo_dout, b_hi_dout;
    logic        a_lo_req, a_lo_ready, a_hi_req, a_hi_ready;
    logic        b_lo_req, b_lo_ready, b_hi_req, b_hi_ready;

    rf_video_pipe pipe (
        .clk(clk), .reset(reset), .clk_ram(clk_ram),
        .div(div), .hcnt(hcnt), .vcnt(vcnt),
        .hblank(hblank), .vblank(vblank), .rate_60(rate_60),
        .ctrl0(ctrl0), .ctrl1(ctrl1), .flip(flip),
        .line_addr(line_addr), .line_q(line_q),
        .pf_addr(pf_addr),     .pf_q(pf_q),
        .pal_addr(pal_addr),   .pal_q(pal_q),
        .text_addr(text_addr), .text_q(text_q),
        .char_addr(char_addr), .char_q(char_q),
        .pivot_addr(pivot_addr), .pivot_q(pivot_q),
        .ch1_addr(ch1_addr), .ch1_dout(ch1_dout), .ch1_req(ch1_req), .ch1_ready(ch1_ready),
        .ch2_addr(ch2_addr), .ch2_dout(ch2_dout), .ch2_req(ch2_req), .ch2_ready(ch2_ready),
        .spr_addr(spr_addr), .spr_q(spr_q),
        .spr_a_lo_addr(a_lo_addr), .spr_a_lo_dout(a_lo_dout), .spr_a_lo_req(a_lo_req), .spr_a_lo_ready(a_lo_ready),
        .spr_a_hi_addr(a_hi_addr), .spr_a_hi_dout(a_hi_dout), .spr_a_hi_req(a_hi_req), .spr_a_hi_ready(a_hi_ready),
        .spr_b_lo_addr(b_lo_addr), .spr_b_lo_dout(b_lo_dout), .spr_b_lo_req(b_lo_req), .spr_b_lo_ready(b_lo_ready),
        .spr_b_hi_addr(b_hi_addr), .spr_b_hi_dout(b_hi_dout), .spr_b_hi_req(b_hi_req), .spr_b_hi_ready(b_hi_ready),
        .rgb(rgb),
        .dbg_lines(dbg_lines), .dbg_fetch(dbg_fetch),
        .dbg_max(dbg_max), .dbg_nz(dbg_nz), .dbg_spr(dbg_spr), .dbg_rec(dbg_rec)
    );

    rf_spr_ch_share share (
        .clk_ram(clk_ram),
        .a_lo_addr(a_lo_addr), .a_lo_dout(a_lo_dout), .a_lo_req(a_lo_req), .a_lo_ready(a_lo_ready),
        .a_hi_addr(a_hi_addr), .a_hi_dout(a_hi_dout), .a_hi_req(a_hi_req), .a_hi_ready(a_hi_ready),
        .b_lo_addr(b_lo_addr), .b_lo_dout(b_lo_dout), .b_lo_req(b_lo_req), .b_lo_ready(b_lo_ready),
        .b_hi_addr(b_hi_addr), .b_hi_dout(b_hi_dout), .b_hi_req(b_hi_req), .b_hi_ready(b_hi_ready),
        .ch_addr(sps_addr), .ch_dout(sps_dout),
        .ch_req(sps_req),   .ch_ready(sps_ready)
    );

endmodule
