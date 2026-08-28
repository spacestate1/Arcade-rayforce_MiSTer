//============================================================================
//  Pivot / text layer: one screen line at a time into a double-banked line
//  buffer, read by the mixer as its "pivot" sample.
//
//  The F3 has one text-ish layer with two sources, chosen per scanline by
//  line RAM (pivot_control & 0xA0, the model's use_pix):
//
//    VRAM layer   64x64 tiles of 8x8 4bpp chars = 512x512. Tile word from
//                 text RAM: code[7:0], flipx bit 8, palette[14:9], flipy bit
//                 15. Char bitmaps from char RAM.
//    pixel layer  a 512x256 bitmap held in pivot RAM as 64x32 8x8 cells,
//                 scanned in COLUMNS (cell = col*32 + row). It has no tile
//                 words of its own: palette and flips are borrowed from the
//                 text RAM tile at [row (+32 when the scroll puts the cell
//                 in the lower half), col] -- MAME's get_tile_info_pixel
//                 hack, reproduced so the two agree even where both are odd.
//
//  Scroll comes from video control words 4/5 (0x660018/1A), with the model's
//  flipscreen adjustments; y wraps at 512 (VRAM) or 256 (pixel). Flipscreen
//  mirrors the finished layer in both axes -- source (xs, ys) = (511 - gx,
//  511 - y) -- and THEN each tile's own flip bits apply. Mosaic is a
//  sample-and-hold on x with the same phase counter as rf_video_pf.
//
//  The per-line "used" flag (MAME skips the layer on a line whose text-RAM
//  row is all zero codes) is a 64-word scan of that row before the pixel
//  pass; the pixel layer is always used.
//
//  THE BYTE-ORDER TRAP (HANDOFF.md): char and pivot RAM are read as the CPU
//  wrote them, so within a row's two words pixel 0 is the low nibble of the
//  SECOND word and pixel 7 the high nibble of the first: pixel c is nibble
//  c[1:0] of word (1 - c[2]).
//
//  Cost: 64 + 320 + 4 clocks per line, on RAM ports nothing else uses, so
//  it runs alongside the playfield build.
//============================================================================

module rf_video_pivot
(
    input  logic        clk,
    input  logic        reset,

    // ---- frame ---------------------------------------------------------
    input  logic        frame_start,   // latch scroll from ctrl1
    input  logic [7:0][15:0] ctrl1,    // 0x660010-1F: words 4/5 are x/y scroll
    input  logic        flip,

    // ---- line build ----------------------------------------------------
    input  logic        line_start,
    input  logic  [7:0] screen_y,
    input  logic  [7:0] pivot_control, // line RAM 6000 bits 15:8
    input  logic        mosaic_en,     // pivot_mosaic
    input  logic  [4:0] x_sample,      // 1..16
    output logic        busy,

    // video RAM read ports (B side of the CPU's BRAMs)
    output logic [11:0] text_addr,
    input  logic [15:0] text_q,
    output logic [11:0] char_addr,
    input  logic [15:0] char_q,
    output logic [14:0] pivot_addr,
    input  logic [15:0] pivot_q,

    // ---- line read (mixer side) -----------------------------------------
    // rd_bank selects the line the mixer is composing; the sample for rd_x
    // is on rd_color / rd_opaque the clock after rd_x is presented, and
    // rd_used is that line's usage flag.
    input  logic        rd_bank,
    input  logic  [8:0] rd_x,
    output logic [15:0] rd_color,      // palette * 16 + pen
    output logic        rd_opaque,     // pen != 0
    output logic        rd_used
);

    // ---- frame scroll (render_frame) -------------------------------------
    logic [8:0] reg_sx, reg_sy;
    logic [8:0] raw_sy;                // ctrl1[5], for the pixel-layer hack

    // ---- per-line state, latched at line_start -----------------------------
    logic       use_pix, mos;
    logic [4:0] xsamp;
    logic       wbank;
    logic [8:0] ys;                    // source row, after flipscreen
    logic [5:0] yy;                    // pixel layer: text row to borrow from
    logic       used [0:1];

    // ---- sequencing ------------------------------------------------------
    typedef enum logic [1:0] {P_IDLE, P_SCAN, P_PIX, P_DRAIN} pst_t;
    pst_t       pst;
    logic [6:0] scan_i;
    logic [8:0] x;
    logic       row_used;
    logic [3:0] mcnt;

    assign busy = (pst != P_IDLE);

    // 114 % sample: the mosaic phase at the left edge (same as rf_video_pf)
    function automatic logic [3:0] mos_phase0(input logic [4:0] s);
        case (s)
            5'd4: mos_phase0 = 4'd2;  5'd5: mos_phase0 = 4'd4;
            5'd7: mos_phase0 = 4'd2;  5'd8: mos_phase0 = 4'd2;
            5'd9: mos_phase0 = 4'd6;  5'd10: mos_phase0 = 4'd4;
            5'd11: mos_phase0 = 4'd4; 5'd12: mos_phase0 = 4'd6;
            5'd13: mos_phase0 = 4'd10; 5'd14: mos_phase0 = 4'd2;
            5'd15: mos_phase0 = 4'd9; 5'd16: mos_phase0 = 4'd2;
            default: mos_phase0 = 4'd0;
        endcase
    endfunction
    wire [3:0] mcnt_inc  = ({1'b0, mcnt} + 5'd1 == xsamp) ? 4'd0 : mcnt + 4'd1;
    wire [3:0] mcnt_next = (x == 9'd317) ? 4'd0 : mcnt_inc;

    // ---- line setup, combinational on the line_start inputs ------------------
    wire       up_i  = pivot_control[7] | pivot_control[5];       // & 0xA0
    wire [8:0] y9_i  = reg_sy + {1'b0, screen_y};
    wire [8:0] y9m_i = up_i ? {1'b0, y9_i[7:0]} : y9_i;           // & 0xFF / 0x1FF
    wire [8:0] ys_i  = flip ? (up_i ? {1'b0, ~y9m_i[7:0]} : ~y9m_i) : y9m_i;
    // pixel layer: borrow from text row +32 when the cell's y offset lands
    // in the lower 256 lines (build_pixel_layer's y_off test)
    wire [8:0] yo_i  = {ys_i[7:3], 3'd0} + raw_sy + (flip ? 9'd256 : 9'd0);

    // ---- pixel pipeline ----------------------------------------------------
    // stage 0 (combinational on x): source column
    wire [8:0] rx = mos ? (x - {5'd0, mcnt}) : x;
    wire [8:0] gx = rx + reg_sx;
    wire [8:0] xs = flip ? ~gx : gx;              // 511 - gx

    // p1/p2: text RAM address in flight; p3/p4: char/pivot address in flight
    logic       p1_v, p2_v, p3_v, p4_v;
    logic [8:0] p1_x, p2_x, p3_x, p4_x;
    logic [2:0] p1_c, p2_c;                       // pixel column in the cell
    logic [5:0] p1_col, p2_col;                   // cell column (pixel layer)
    logic [1:0] p3_n, p4_n;                       // nibble within the word
    logic [5:0] p3_pal, p4_pal;

    // the tile word for p2, and the cell address it selects
    wire [7:0] t_code = text_q[7:0];
    wire       t_fx   = text_q[8];
    wire [5:0] t_pal  = text_q[14:9];
    wire       t_fy   = text_q[15];
    wire [2:0] t_c    = p2_c ^ {3{t_fx}};
    wire [2:0] t_r    = ys[2:0] ^ {3{t_fy}};
    wire [10:0] t_cell = {p2_col, ys[7:3]};      // col * 32 + row

    // the pen for p4
    wire [15:0] g_q = use_pix ? pivot_q : char_q;
    wire  [3:0] pen = g_q[4 * p4_n +: 4];

    // ---- line buffer: 2 banks x 320 x {opaque, pal, pen} ---------------------
    logic [10:0] lb_q;
    rf_bram #(.WIDTH(11), .AW(10)) u_buf (
        .clk(clk),
        .waddr({wbank, p4_x}), .wdata({pen != 4'd0, p4_pal, pen}), .wren(p4_v),
        .raddr({rd_bank, rd_x}), .q(lb_q)
    );
    assign rd_color  = {6'd0, lb_q[9:0]};
    assign rd_opaque = lb_q[10];
    assign rd_used   = used[rd_bank];

    always_ff @(posedge clk) begin
        p1_v <= 1'b0; p2_v <= p1_v; p3_v <= 1'b0; p4_v <= p3_v;
        p2_x <= p1_x; p2_c <= p1_c; p2_col <= p1_col;
        p4_x <= p3_x; p4_n <= p3_n; p4_pal <= p3_pal;

        if (reset) begin
            pst <= P_IDLE;
            reg_sx <= '0; reg_sy <= '0; raw_sy <= '0;
            used[0] <= 1'b0; used[1] <= 1'b0;
        end else if (frame_start) begin
            // the model's x_index adds the scroll to the RASTER x (screen
            // x + 46), so H_START is folded in here once per frame
            reg_sx <= (flip ? (ctrl1[4][8:0] - 9'd12) : (9'd0 - ctrl1[4][8:0] - 9'd5)) + 9'd46;
            reg_sy <= flip ? ctrl1[5][8:0] : (9'd0 - ctrl1[5][8:0]);
            raw_sy <= ctrl1[5][8:0];
            pst <= P_IDLE;
        end else begin
            case (pst)
            P_IDLE: if (line_start) begin
                use_pix  <= up_i;
                ys       <= ys_i;
                yy       <= {yo_i[8], ys_i[7:3]};
                mos      <= mosaic_en;
                xsamp    <= x_sample;
                wbank    <= screen_y[0];
                row_used <= 1'b0;
                scan_i   <= 7'd0;
                x        <= 9'd0;
                mcnt     <= mos_phase0(x_sample);
                pst      <= up_i ? P_PIX : P_SCAN;
            end

            // any non-zero code word in text row ys[8:3]; registered
            // address + RAM latency = data for scan_i is seen at scan_i + 2
            P_SCAN: begin
                if (scan_i <= 7'd63) text_addr <= {ys[8:3], scan_i[5:0]};
                if (scan_i >= 7'd2 && text_q[7:0] != 8'd0) row_used <= 1'b1;
                if (scan_i == 7'd65) begin
                    used[wbank] <= row_used | (text_q[7:0] != 8'd0);
                    pst <= P_PIX;
                end
                scan_i <= scan_i + 7'd1;
            end

            // one pixel per clock; each stage below is data for the pixel
            // two clocks behind the one above
            P_PIX: begin
                text_addr <= use_pix ? {yy, xs[8:3]} : {ys[8:3], xs[8:3]};
                p1_v <= 1'b1; p1_x <= x; p1_c <= xs[2:0]; p1_col <= xs[8:3];
                x    <= x + 9'd1;
                mcnt <= mcnt_next;
                if (x == 9'd319) begin
                    if (use_pix) used[wbank] <= 1'b1;
                    pst <= P_DRAIN;
                end
            end

            P_DRAIN: if (!p1_v && !p2_v && !p3_v && !p4_v) pst <= P_IDLE;
            default: pst <= P_IDLE;
            endcase

            // stage 2 -> 3: the tile word is on text_q, pick the char word
            if (p2_v) begin
                char_addr  <= {t_code, t_r, ~t_c[2]};
                pivot_addr <= {t_cell, t_r, ~t_c[2]};
                p3_v   <= 1'b1;
                p3_x   <= p2_x;
                p3_n   <= t_c[1:0];
                p3_pal <= t_pal;
            end
        end
    end

endmodule
