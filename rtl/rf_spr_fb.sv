//============================================================================
//  The sprite framebuffer in DDR3 -- what the arcade board and MAME do.
//
//  WHY THIS EXISTS. The sprite draw used to write into a ring of on-chip line
//  buffers that the mixer read a few lines later, so the draw had to keep up
//  with the RASTER, line by line. It cannot. Measured on build 30101648, the
//  worst line carries 784 sprite rows and the draw loop is 17 clocks a row:
//  13328 clocks against a 3456-clock line budget, 3.9x over, and no fetch or
//  priority change touches that because the draw loop IS the floor (the same
//  build measured 17.8 clocks a row, i.e. almost no fetch wait). A ring of 16
//  banks 55296 clocks of slack, which covers about four such lines and then
//  runs dry -- which is exactly what a busy scene or a boss fight is.
//
//  But the frame as a whole is not remotely full: ~8000 sprite rows a frame
//  at 17 clocks is ~15 % of a frame's 884736 clocks. The work fits easily;
//  only its DISTRIBUTION does not. The real F3 board knows this, which is why
//  it draws sprites into a framebuffer and displays it a frame later, and why
//  MAME's config table carries a sprite_lag of 2 for this game.
//
//  So: the draw fills one line at a time into a small ping-pong buffer with
//  no deadline but the frame's, each finished line is streamed to a DDR3
//  framebuffer, and the mixer reads LAST frame's framebuffer back a line
//  ahead of where it is displaying. There is no per-line deadline left to
//  miss. Three consequences, all wanted:
//
//    - the glitching is gone structurally, not mitigated
//    - sprite lag becomes 2 frames, which is what MAME uses for this game
//      (README Known problem #3, fixed as a side effect)
//    - the on-chip line-buffer ring drops from 16 banks to 2 + 2, freeing
//      about 12 M10K on a device sitting at 551/553
//
//  LAYOUT. 16 bits a pixel, 4 pixels a 64-bit word, 80 words a line, 256
//  lines a bank, 2 banks (the frame being drawn and the frame being shown):
//  40960 words = 320 KB, at 0x30000000 -- the conventional base for a core's
//  own DDR3, well clear of screen_rotate's 0x24000000. Bandwidth is 19 MB/s
//  read plus write, against a port that does hundreds.
//
//  Every transaction is a single word (BURSTCNT 1). 80 words in and 80 out
//  per line against 3456 clocks is under 5 % occupancy, so bursting would buy
//  nothing and cost the arbiter its statelessness -- see rf_ddr_arb.
//============================================================================

module rf_spr_fb
(
    input  logic        clk,
    input  logic        reset,

    // ---- the frame boundary ---------------------------------------------
    // par is the parity of the frame being DRAWN; the mixer reads ~par.
    input  logic        frame_start,

    // ---- write side: a finished line from the draw ----------------------
    input  logic        wr_req,         // pulse: line wr_line is ready
    input  logic  [7:0] wr_line,
    output logic        wr_busy,        // streaming; the draw must not reuse
                                        // the bank it just handed over
    output logic  [8:0] lb_addr,        // into the draw's line buffer
    input  logic [15:0] lb_q,           // 1-cycle read latency

    // ---- read side: what the mixer samples ------------------------------
    input  logic  [7:0] rd_line,        // the line being composed
    input  logic  [8:0] rd_x,
    output logic [15:0] rd_color,

    // ---- DDR3, through rf_ddr_arb ---------------------------------------
    output logic  [7:0] ddr_burstcnt,
    output logic [28:0] ddr_addr,
    output logic [63:0] ddr_din,
    output logic  [7:0] ddr_be,
    output logic        ddr_we,
    output logic        ddr_rd,
    input  logic        ddr_busy,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready
);

    // 0x30000000 in bytes is word 0x06000000; the top 7 bits are the region,
    // the same shape screen_rotate uses for its own 0x24000000.
    localparam logic [28:0] FB_BASE  = 29'h0600_0000;
    localparam int          WPL      = 80;          // 64-bit words per line
    localparam int          WPB      = 256 * WPL;   // words per frame bank

    logic par;                                      // frame being drawn

    // word index of (bank, line): bank*WPB + line*80, and 80 = 64 + 16 so
    // the multiply is two shifts and an add
    function automatic logic [28:0] line_word(input logic b, input logic [7:0] l);
        line_word = FB_BASE + 29'(b ? WPB : 0) + 29'({l, 6'd0}) + 29'({l, 4'd0});
    endfunction

    // ================= WRITE: draw line -> DDR3 =========================
    // Read four pixels out of the draw's line buffer, pack, issue one word.
    // 320 reads and 80 writes a line, interleaved, against 3456 clocks.
    // W_RD presents a pixel address; W_CAP captures it one clock later, which
    // is the line buffer's read latency. Collapsing the two (capturing in the
    // same state that advances the address) shifts every pixel by one and
    // wraps the last of each word into the next.
    typedef enum logic [1:0] { W_IDLE, W_RD, W_CAP, W_ISSUE } wst_t;
    wst_t wst;
    logic  [6:0] w_word;            // 0..79
    logic  [1:0] w_pix;             // which of the four
    logic [63:0] w_acc;
    logic  [7:0] w_line;
    logic        w_bank;

    assign wr_busy = (wst != W_IDLE);
    assign lb_addr = 9'({w_word, 2'd0}) + 9'(w_pix);

    // ================= READ: DDR3 -> the line the mixer wants ===========
    // Two on-chip line buffers: the mixer samples one while the other is
    // being filled with the next line. A line is 64.7 us and a DDR3 round
    // trip is a few hundred ns, so the prefetch has three orders of
    // magnitude of slack -- it only has to be STARTED early enough.
    typedef enum logic [1:0] { R_IDLE, R_REQ, R_WAIT } rst_t;
    rst_t rst;
    logic  [6:0] r_word;            // words requested
    logic  [6:0] r_got;             // words returned
    logic  [7:0] r_line;            // the line being fetched
    logic        r_fill;            // which local buffer is being filled
    // Which screen line each buffer holds, and whether it holds anything.
    // The mixer reads the buffer whose line matches rd_line -- NOT "the one
    // not being filled". Selecting by fill state instead was a bug: at the
    // moment the prefetch of line L+1 completes it would hand the mixer that
    // buffer while the mixer is still composing L, and every line would show
    // the next line's sprites.
    logic  [7:0] buf_line [0:1];
    logic  [1:0] buf_ok;

    // two 320 x 16 line buffers, one M10K
    (* ramstyle = "M10K" *) logic [15:0] lbuf [0:1][0:511];
    wire         rd_sel  = (buf_ok[0] && buf_line[0] == rd_line) ? 1'b0 : 1'b1;
    wire         rd_hit  = buf_ok[rd_sel] && (buf_line[rd_sel] == rd_line);
    logic [15:0] rd_q;
    logic        rd_hit_q;
    always_ff @(posedge clk) begin
        rd_q     <= lbuf[rd_sel][rd_x];
        rd_hit_q <= rd_hit;
    end
    assign rd_color = rd_hit_q ? rd_q : 16'd0;

    // the four pixels of a returning word land at r_got*4 + k
    always_ff @(posedge clk) begin
        if (ddr_dout_ready && rst != R_IDLE) begin
            lbuf[r_fill][{r_got, 2'd0} + 9'd0] <= ddr_dout[15:0];
            lbuf[r_fill][{r_got, 2'd0} + 9'd1] <= ddr_dout[31:16];
            lbuf[r_fill][{r_got, 2'd0} + 9'd2] <= ddr_dout[47:32];
            lbuf[r_fill][{r_got, 2'd0} + 9'd3] <= ddr_dout[63:48];
        end
    end

    // ================= the port ==========================================
    // Writes win: the draw hands over one line at a time and must not be
    // held up, while a read prefetch has a whole line of slack.
    assign ddr_burstcnt = 8'd1;
    assign ddr_be       = 8'hFF;
    assign ddr_we       = (wst == W_ISSUE);
    assign ddr_rd       = (wst != W_ISSUE) && (rst == R_REQ);
    assign ddr_din      = w_acc;
    assign ddr_addr     = (wst == W_ISSUE)
                        ? (line_word(w_bank, w_line) + 29'(w_word))
                        : (line_word(~par,   r_line) + 29'(r_word));

    always_ff @(posedge clk) begin
        if (reset) begin
            wst <= W_IDLE; rst <= R_IDLE; par <= 1'b0;
            r_fill <= 1'b0; buf_ok <= 2'b00;
            buf_line[0] <= 8'd0; buf_line[1] <= 8'd0;
            w_word <= 0; w_pix <= 0; r_word <= 0; r_got <= 0;
        end else begin
            if (frame_start) begin
                par    <= ~par;
                buf_ok <= 2'b00;        // last frame's lines are stale
                rst    <= R_IDLE;
            end

            // ---- write FSM
            case (wst)
                W_IDLE: if (wr_req) begin
                    w_line <= wr_line; w_bank <= par;
                    w_word <= 0; w_pix <= 0;
                    wst <= W_RD;
                end
                // lb_q is valid one clock after lb_addr, so shift the pixel
                // into the accumulator on the cycle AFTER presenting it
                W_RD:  wst <= W_CAP;            // lb_addr presented; wait a clock
                W_CAP: begin
                    w_acc <= {lb_q, w_acc[63:16]};  // pixel 0 ends up lowest
                    if (w_pix == 2'd3) wst <= W_ISSUE;
                    else begin w_pix <= w_pix + 2'd1; wst <= W_RD; end
                end
                W_ISSUE: if (!ddr_busy) begin
                    w_pix <= 2'd0;
                    if (w_word == WPL - 1) wst <= W_IDLE;
                    else begin w_word <= w_word + 7'd1; wst <= W_RD; end
                end
                default: wst <= W_IDLE;
            endcase

            // ---- read FSM: keep the buffer the mixer is NOT using filled
            // with the line after the one it is on
            // Fetch whichever of {the line being shown, the next one} is not
            // already in a buffer, the current line first -- after a
            // frame_start neither is present and the mixer needs rd_line now.
            case (rst)
                R_IDLE: if (!(buf_ok[0] && buf_line[0] == rd_line) &&
                             !(buf_ok[1] && buf_line[1] == rd_line)) begin
                    r_line <= rd_line;   r_fill <= rd_sel;
                    r_word <= 0; r_got <= 0; rst <= R_REQ;
                end else if (!(buf_ok[0] && buf_line[0] == rd_line + 8'd1) &&
                             !(buf_ok[1] && buf_line[1] == rd_line + 8'd1)) begin
                    r_line <= rd_line + 8'd1; r_fill <= ~rd_sel;
                    r_word <= 0; r_got <= 0; rst <= R_REQ;
                end
                R_REQ: if (!ddr_busy && ddr_rd) begin
                    if (r_word == WPL - 1) rst <= R_WAIT;
                    else r_word <= r_word + 7'd1;
                end
                R_WAIT: if (r_got == WPL - 1 && ddr_dout_ready) begin
                    buf_line[r_fill] <= r_line;
                    buf_ok[r_fill]   <= 1'b1;
                    rst              <= R_IDLE;
                end
                default: rst <= R_IDLE;
            endcase
            if (ddr_dout_ready && rst != R_IDLE) r_got <= r_got + 7'd1;
        end
    end

endmodule
