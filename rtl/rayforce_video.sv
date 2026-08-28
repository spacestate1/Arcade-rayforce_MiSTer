//============================================================================
//  Ray Force -- F3 raster timing + Phase 2 diagnostic page
//
//  Timing is the real machine's, from MAME taito_f3.cpp:
//      set_raw(26.686 MHz / 4, 432, 46, 320+46, 262, 24, 232+24)
//      pixel clock 6.6715 MHz = clk_sys / 8 (clk_sys = 53.372 MHz)
//      => 58.94 Hz, which the OSD reporting that number is part of the test.
//
//  The F3 renders 232 scanlines; each game then crops itself with line RAM
//  and a visarea. gunlock/rayforce use f3_224a: set_visarea(46, 365, 31, 254)
//  -- 320x224 starting at line 31, NOT line 24. Line RAM is indexed by the
//  raw raster line (MAME's scanline_draw walks screen_y 0..255 and indexes
//  line ram with it), so vcnt IS the line-RAM index and the visible window
//  is a crop of it. Getting this offset wrong shifts every per-line effect
//  by seven lines, which is the kind of bug that looks like bad line RAM
//  decoding for a week.
//
//  vbl_rise is the main CPU's vblank interrupt: MAME schedules it at
//  visarea.max_y + 1, so line 255.
//
//  The picture is still a diagnostic page, not a game. What is on it now:
//    - eleven hex readouts: the download proof and BIST from Phase 1, plus
//      the Phase 2 liveness counters (frames, IRQ acknowledges, and writes
//      per video region). A program that is really running rewrites sprite
//      and playfield RAM every frame; a hung one does not, so those counters
//      are the "is it alive" test that does not need a single pixel of the
//      real renderer to work.
//    - a live dump of all 8192 palette entries, one pixel each. This is the
//      first thing the game generates that can be compared against MAME
//      directly: same screenshot, same colours, or the palette write path
//      is wrong.
//============================================================================

module rayforce_video
(
    input  logic        clk,          // 53.372 MHz
    input  logic        reset,

    input  logic        dl_active,
    input  logic        dl_seen,
    input  logic [31:0] dl_bytes,
    input  logic [31:0] dl_sum,
    input  logic  [7:0] dl_index,
    input  logic        trap_oor,
    input  logic [31:0] wr_count,
    input  logic [31:0] wr_hash,
    input  logic [31:0] last_pc,
    input  logic [31:0] bist_sum,
    input  logic        bist_done,

    // Phase 2 liveness counters from rf_main
    input  logic [15:0] frame_cnt,
    input  logic [15:0] irq2_cnt,
    input  logic [15:0] irq3_cnt,
    input  logic [15:0] pf_wr_cnt,
    input  logic [15:0] spr_wr_cnt,
    input  logic [15:0] pal_wr_cnt,
    input  logic [15:0] line_wr_cnt,

    // palette RAM read port (B side of the CPU's palette BRAM)
    output logic [13:0] v_pal_addr,
    input  logic [15:0] v_pal_q,

    // Refresh Rate OSD option. Native is 262 lines = 58.94 Hz (MAME: 58.97);
    // 60Hz trims the vertical blank to 257 lines = 60.08 Hz, H rate
    // unchanged, so the game runs 1.9% fast in exchange for a picture every
    // 60 Hz display holds without judder. rf_video_pipe carries the same
    // two constants for its lookahead wrap.
    input  logic  [1:0] vis_mode,     // which F3 visarea (see below)
    input  logic        rate_60,

    output logic        vbl_rise,     // one pulse at the vblank interrupt line

    // raster position, for the self-test page renderer
    output logic  [2:0] div_o,
    output logic  [8:0] hcnt_o,
    output logic  [8:0] vcnt_o,

    output logic        ce_pix,       // clk / 8
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,        // active high, straight into arcade_video
    output logic        vsync
);

    // ---- counters --------------------------------------------------------
    // vcnt IS the line-RAM index; the visible window is a crop of the
    // 262-line raster, so vsync has to live in what is left.
    //
    // The crop is the ONE thing that differs between the four Taito F3
    // machine configurations in MAME, and every F3 game uses one of them
    // (taito_f3.cpp: the base f3 set_raw is 432x262 for all of them, and
    // f3_224a/b/c only override set_visarea):
    //
    //   vis_mode 0  f3_224a  lines 31..254   224 visible   <- Ray Force
    //   vis_mode 1  f3_224b  lines 32..255   224 visible
    //   vis_mode 2  f3_224c  lines 24..247   224 visible
    //   vis_mode 3  f3       lines 24..255   232 visible   <- Elevator
    //                                                         Action Returns
    //
    // 0 is the default so a core with no game-config ROM behaves as before.
    localparam int H_TOTAL = 432, H_START = 46, H_END = 366;   // 320 visible
    localparam int V_TOTAL = 262;
    localparam int HS_BEG  = 388, HS_WID  = 32;
    localparam int VS_BEG  = 258, VS_WID  = 3;

    wire [8:0] v_start = (vis_mode == 2'd0) ? 9'd31 :
                         (vis_mode == 2'd1) ? 9'd32 : 9'd24;
    wire [8:0] v_end   = (vis_mode == 2'd3) ? 9'd256 : (v_start + 9'd224);

    wire [8:0] v_total = rate_60 ? 9'd257 : V_TOTAL[8:0];
    wire [8:0] vs_beg  = rate_60 ? 9'd1   : VS_BEG[8:0];   // 258 wraps to 1

    logic [2:0] div;
    logic [8:0] hcnt;
    logic [8:0] vcnt;
    logic [7:0] frame;

    always_ff @(posedge clk) begin
        div    <= div + 3'd1;
        ce_pix <= (div == 3'd7);
        if (reset) begin
            div <= '0; hcnt <= '0; vcnt <= '0; frame <= '0;
        end else if (div == 3'd7) begin
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= '0;
                if (vcnt == v_total - 9'd1) begin
                    vcnt  <= '0;
                    frame <= frame + 8'd1;
                end else vcnt <= vcnt + 9'd1;
            end else hcnt <= hcnt + 9'd1;
        end
    end

    assign div_o  = div;
    assign hcnt_o = hcnt;
    assign vcnt_o = vcnt;

    // The vblank interrupt fires as the raster leaves the visible area.
    wire line_end = (div == 3'd7) && (hcnt == H_TOTAL - 1);
    always_ff @(posedge clk) vbl_rise <= !reset && line_end && (vcnt == v_end - 9'd1);

    assign hblank = (hcnt < H_START) || (hcnt >= H_END);
    assign vblank = (vcnt < v_start) || (vcnt >= v_end);
    assign hsync  = (hcnt >= HS_BEG) && (hcnt < HS_BEG + HS_WID);
    assign vsync  = (vcnt >= vs_beg) && (vcnt < vs_beg + VS_WID[8:0]);

    wire [8:0] x = hcnt - H_START[8:0];   // 0..319 when visible
    wire [8:0] y = vcnt - v_start;        // 0 at the top visible line

    // ---- 8x8 hex font, 16 glyphs ----------------------------------------
    function automatic logic [7:0] glyph(input logic [3:0] n, input logic [2:0] row);
        case ({n, row})
            {4'h0,3'd0}:glyph=8'h3C; {4'h0,3'd1}:glyph=8'h66; {4'h0,3'd2}:glyph=8'h6E; {4'h0,3'd3}:glyph=8'h76;
            {4'h0,3'd4}:glyph=8'h66; {4'h0,3'd5}:glyph=8'h66; {4'h0,3'd6}:glyph=8'h3C; {4'h0,3'd7}:glyph=8'h00;
            {4'h1,3'd0}:glyph=8'h18; {4'h1,3'd1}:glyph=8'h38; {4'h1,3'd2}:glyph=8'h18; {4'h1,3'd3}:glyph=8'h18;
            {4'h1,3'd4}:glyph=8'h18; {4'h1,3'd5}:glyph=8'h18; {4'h1,3'd6}:glyph=8'h7E; {4'h1,3'd7}:glyph=8'h00;
            {4'h2,3'd0}:glyph=8'h3C; {4'h2,3'd1}:glyph=8'h66; {4'h2,3'd2}:glyph=8'h06; {4'h2,3'd3}:glyph=8'h0C;
            {4'h2,3'd4}:glyph=8'h30; {4'h2,3'd5}:glyph=8'h60; {4'h2,3'd6}:glyph=8'h7E; {4'h2,3'd7}:glyph=8'h00;
            {4'h3,3'd0}:glyph=8'h3C; {4'h3,3'd1}:glyph=8'h66; {4'h3,3'd2}:glyph=8'h06; {4'h3,3'd3}:glyph=8'h1C;
            {4'h3,3'd4}:glyph=8'h06; {4'h3,3'd5}:glyph=8'h66; {4'h3,3'd6}:glyph=8'h3C; {4'h3,3'd7}:glyph=8'h00;
            {4'h4,3'd0}:glyph=8'h0C; {4'h4,3'd1}:glyph=8'h1C; {4'h4,3'd2}:glyph=8'h3C; {4'h4,3'd3}:glyph=8'h6C;
            {4'h4,3'd4}:glyph=8'h7E; {4'h4,3'd5}:glyph=8'h0C; {4'h4,3'd6}:glyph=8'h0C; {4'h4,3'd7}:glyph=8'h00;
            {4'h5,3'd0}:glyph=8'h7E; {4'h5,3'd1}:glyph=8'h60; {4'h5,3'd2}:glyph=8'h7C; {4'h5,3'd3}:glyph=8'h06;
            {4'h5,3'd4}:glyph=8'h06; {4'h5,3'd5}:glyph=8'h66; {4'h5,3'd6}:glyph=8'h3C; {4'h5,3'd7}:glyph=8'h00;
            {4'h6,3'd0}:glyph=8'h3C; {4'h6,3'd1}:glyph=8'h60; {4'h6,3'd2}:glyph=8'h7C; {4'h6,3'd3}:glyph=8'h66;
            {4'h6,3'd4}:glyph=8'h66; {4'h6,3'd5}:glyph=8'h66; {4'h6,3'd6}:glyph=8'h3C; {4'h6,3'd7}:glyph=8'h00;
            {4'h7,3'd0}:glyph=8'h7E; {4'h7,3'd1}:glyph=8'h06; {4'h7,3'd2}:glyph=8'h0C; {4'h7,3'd3}:glyph=8'h18;
            {4'h7,3'd4}:glyph=8'h30; {4'h7,3'd5}:glyph=8'h30; {4'h7,3'd6}:glyph=8'h30; {4'h7,3'd7}:glyph=8'h00;
            {4'h8,3'd0}:glyph=8'h3C; {4'h8,3'd1}:glyph=8'h66; {4'h8,3'd2}:glyph=8'h3C; {4'h8,3'd3}:glyph=8'h66;
            {4'h8,3'd4}:glyph=8'h66; {4'h8,3'd5}:glyph=8'h66; {4'h8,3'd6}:glyph=8'h3C; {4'h8,3'd7}:glyph=8'h00;
            {4'h9,3'd0}:glyph=8'h3C; {4'h9,3'd1}:glyph=8'h66; {4'h9,3'd2}:glyph=8'h66; {4'h9,3'd3}:glyph=8'h3E;
            {4'h9,3'd4}:glyph=8'h06; {4'h9,3'd5}:glyph=8'h0C; {4'h9,3'd6}:glyph=8'h38; {4'h9,3'd7}:glyph=8'h00;
            {4'hA,3'd0}:glyph=8'h18; {4'hA,3'd1}:glyph=8'h3C; {4'hA,3'd2}:glyph=8'h66; {4'hA,3'd3}:glyph=8'h66;
            {4'hA,3'd4}:glyph=8'h7E; {4'hA,3'd5}:glyph=8'h66; {4'hA,3'd6}:glyph=8'h66; {4'hA,3'd7}:glyph=8'h00;
            {4'hB,3'd0}:glyph=8'h7C; {4'hB,3'd1}:glyph=8'h66; {4'hB,3'd2}:glyph=8'h7C; {4'hB,3'd3}:glyph=8'h66;
            {4'hB,3'd4}:glyph=8'h66; {4'hB,3'd5}:glyph=8'h66; {4'hB,3'd6}:glyph=8'h7C; {4'hB,3'd7}:glyph=8'h00;
            {4'hC,3'd0}:glyph=8'h3C; {4'hC,3'd1}:glyph=8'h66; {4'hC,3'd2}:glyph=8'h60; {4'hC,3'd3}:glyph=8'h60;
            {4'hC,3'd4}:glyph=8'h60; {4'hC,3'd5}:glyph=8'h66; {4'hC,3'd6}:glyph=8'h3C; {4'hC,3'd7}:glyph=8'h00;
            {4'hD,3'd0}:glyph=8'h78; {4'hD,3'd1}:glyph=8'h6C; {4'hD,3'd2}:glyph=8'h66; {4'hD,3'd3}:glyph=8'h66;
            {4'hD,3'd4}:glyph=8'h66; {4'hD,3'd5}:glyph=8'h6C; {4'hD,3'd6}:glyph=8'h78; {4'hD,3'd7}:glyph=8'h00;
            {4'hE,3'd0}:glyph=8'h7E; {4'hE,3'd1}:glyph=8'h60; {4'hE,3'd2}:glyph=8'h7C; {4'hE,3'd3}:glyph=8'h60;
            {4'hE,3'd4}:glyph=8'h60; {4'hE,3'd5}:glyph=8'h60; {4'hE,3'd6}:glyph=8'h7E; {4'hE,3'd7}:glyph=8'h00;
            {4'hF,3'd0}:glyph=8'h7E; {4'hF,3'd1}:glyph=8'h60; {4'hF,3'd2}:glyph=8'h7C; {4'hF,3'd3}:glyph=8'h60;
            {4'hF,3'd4}:glyph=8'h60; {4'hF,3'd5}:glyph=8'h60; {4'hF,3'd6}:glyph=8'h60; {4'hF,3'd7}:glyph=8'h00;
            default: glyph = 8'h00;
        endcase
    endfunction

    // ---- eleven hex readouts, 8 digits each, glyphs doubled to 16x16 ----
    localparam int RX = 8;      // left edge of the readout block
    localparam int RY = 6;      // top of row 0
    localparam int RP = 19;     // row pitch
    localparam int NROWS = 11;

    // Phase 1 proofs first (download, write-stream oracle, SDRAM BIST), then
    // the Phase 2 liveness counters.
    wire [31:0] row_val [0:NROWS-1];
    assign row_val[0]  = dl_bytes;
    assign row_val[1]  = dl_sum;
    assign row_val[2]  = {6'h00, bist_done, dl_index, 5'd0, trap_oor, dl_seen, dl_active};
    assign row_val[3]  = wr_count;
    assign row_val[4]  = wr_hash;
    assign row_val[5]  = bist_sum;
    assign row_val[6]  = last_pc;
    assign row_val[7]  = {frame_cnt,   irq2_cnt};
    assign row_val[8]  = {irq3_cnt,    pal_wr_cnt};
    assign row_val[9]  = {pf_wr_cnt,   spr_wr_cnt};
    assign row_val[10] = {line_wr_cnt, 16'h0000};

    // ---- palette dump ----------------------------------------------------
    // All 8192 entries as a 128x64 block of single pixels. An F3 palette
    // entry is a 32-bit word, 0x00RRGGBB, so it is two reads of the 16-bit
    // palette RAM: word 2n holds RR in its low byte, word 2n+1 holds GGBB.
    //
    // The fetch is pipelined one pixel ahead. arcade_video samples RGB on the
    // ce_pix cycle, which is the same cycle hcnt advances to the pixel being
    // shown, so the entry for pixel N+1 is fetched during pixel N's eight
    // clocks and latched at the div 7 -> 0 rollover.
    localparam int PX = 160, PY = 6, PW = 128, PH = 64;

    wire [8:0] xn = hcnt + 9'd1 - H_START[8:0];   // the pixel ce_pix will show
    wire [8:0] pxo = xn - PX[8:0];                // 0..127 inside the panel
    wire [8:0] pyo = y  - PY[8:0];                // 0..63  inside the panel
    wire pal_win = (pxo < PW) && (pyo < PH);
    wire [12:0] pal_idx = {pyo[5:0], pxo[6:0]};

    logic  [7:0] pal_r;
    logic [15:0] pal_gb;
    logic [23:0] pal_rgb;

    always_ff @(posedge clk) begin
        case (div)
            3'd0: v_pal_addr <= {pal_idx, 1'b0};
            3'd2: pal_r      <= v_pal_q[7:0];
            3'd3: v_pal_addr <= {pal_idx, 1'b1};
            3'd5: pal_gb     <= v_pal_q;
            3'd7: pal_rgb    <= {pal_r, pal_gb};
            default: ;
        endcase
    end

    // pal_win is evaluated for the same pixel the fetch was aimed at, so it
    // has to be delayed by exactly the same amount as the colour.
    logic pal_win_r;
    always_ff @(posedge clk) if (div == 3'd7) pal_win_r <= pal_win;

    // ---- text rendering (pipelined to close timing) ----------------------
    // The glyph function is a large combinational case statement that was
    // the critical path (Fmax 49.09 MHz vs target 53.372 MHz). Register the
    // glyph lookup and bit index to break the path.
    logic       text_on;
    logic [3:0] glyph_nib;
    logic [2:0] glyph_row;
    logic [2:0] glyph_bit;
    logic       text_on_r;

    always_comb begin
        text_on  = 1'b0;
        glyph_nib = 4'd0;
        glyph_row = 3'd0;
        glyph_bit = 3'd0;
        for (int rrow = 0; rrow < NROWS; rrow++) begin
            automatic int ty = RY + rrow * RP;
            if (y >= ty && y < ty + 16 && x >= RX && x < RX + 128) begin
                automatic logic [8:0] cx = x - RX[8:0];
                glyph_nib = row_val[rrow] >> (4 * (7 - cx[8:4]));
                glyph_row = 3'((y - ty) >> 1);
                glyph_bit = 3'd7 - cx[3:1];
                text_on   = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (ce_pix) begin
            automatic logic [7:0] bits = glyph(glyph_nib, glyph_row);
            text_on_r <= text_on && bits[glyph_bit];
        end
    end

    // ---- compose ---------------------------------------------------------
    // Dark field, the palette dump on the right, hex readouts on the left,
    // and a moving column at the bottom so a frozen frame is distinguishable
    // from a live one.
    always_comb begin
        logic [7:0] br, bg, bb;
        br = 8'h10; bg = 8'h14; bb = 8'h20;             // dark blue field

        // frame of the palette panel
        if (x >= PX-2 && x < PX+PW+2 && y >= PY-2 && y < PY+PH+2) begin
            br = 8'h40; bg = 8'h40; bb = 8'h40;
        end
        if (pal_win_r) begin
            br = pal_rgb[23:16]; bg = pal_rgb[15:8]; bb = pal_rgb[7:0];
        end

        // life column sweeping the bottom strip
        if (y >= 210 && y < 222 && x[8:1] == frame) begin
            br = 8'hFF; bg = 8'hA0; bb = 8'h00;
        end
        // download activity: left margin strip lights while ioctl writes come in
        if (dl_active && x < 4) begin
            br = 8'h00; bg = 8'hFF; bb = 8'h00;
        end
        if (text_on_r) begin
            br = 8'hFF; bg = 8'hFF; bb = 8'hFF;
        end
        r = (hblank | vblank) ? 8'h00 : br;
        g = (hblank | vblank) ? 8'h00 : bg;
        b = (hblank | vblank) ? 8'h00 : bb;
    end

endmodule
