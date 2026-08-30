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
    // par is the parity of the frame being DRAWN; the mixer reads ~par. It
    // comes FROM the sprite engine rather than being toggled here as well:
    // two counters advancing on the same edge is a bug waiting for the one
    // reset that misses one of them, and if they ever disagreed the mixer
    // would read the bank being written.
    input  logic        frame_start,
    input  logic        par,

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
    output logic [15:0] miss,           // lines composed without their sprites

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

    // ================= READ: DDR3 -> the lines the mixer will want =======
    // A SLIDING WINDOW of NRB lines, filled in order and indexed by
    // line % NRB, so the mixer reads line L from buffer L[1:0] and the
    // prefetcher just walks forward.
    //
    // The first version held ONE line ahead and fetched reactively when the
    // mixer asked for a line it did not have. On the board that produced
    // sprites broken into dashes along the raster -- some scanlines had their
    // sprite data and some did not -- because a fetch that takes longer than
    // a line can never be caught up from one line of slack, and DDR3 here is
    // shared with screen_rotate and the HPS, so its stalls are nothing like
    // the model's. Depth is the fix, and it is cheap: 4 x 512 x 16 bits is
    // 4 M10K out of the 18 this change handed back.
    //
    // The window is refilled from line 0 at frame_start, and vblank is 31
    // lines long, so the first NRB lines are fetched with the mixer nowhere
    // near them.
    localparam int NRB = 4;
    typedef enum logic [1:0] { R_IDLE, R_REQ, R_WAIT } rst_t;
    rst_t rst;
    logic  [6:0] r_word;            // words requested
    logic  [7:0] r_got;             // words returned; see the >= test below
    logic  [8:0] nf;                // next line to fetch (256 = done)
    logic  [1:0] r_fill;            // nf % NRB
    logic  [7:0] buf_line [0:NRB-1];
    logic [NRB-1:0] buf_ok;

    (* ramstyle = "M10K" *) logic [15:0] lbuf [0:NRB-1][0:511];
    wire  [1:0] rd_sel = rd_line[1:0];
    wire        rd_hit = buf_ok[rd_sel] && (buf_line[rd_sel] == rd_line);
    logic [15:0] rd_q;
    logic        rd_hit_q;
    always_ff @(posedge clk) begin
        rd_q     <= lbuf[rd_sel][rd_x];
        rd_hit_q <= rd_hit;
    end
    assign rd_color = rd_hit_q ? rd_q : 16'd0;

    // How many lines the mixer composed without their sprites being ready.
    // This is the direct successor of SPRLINE's late-line count: the same
    // question -- did the sprite data arrive in time -- for the new
    // mechanism. It must stay at zero.
    logic  [7:0] rd_line_q;
    always_ff @(posedge clk) begin
        rd_line_q <= rd_line;
        if (reset || frame_start) miss <= 16'd0;
        else if (rd_line != rd_line_q && !rd_hit && miss != 16'hFFFF)
            miss <= miss + 16'd1;
    end

    always_ff @(posedge clk) begin
        if (ddr_dout_ready && rst != R_IDLE) begin
            lbuf[r_fill][{r_got[6:0], 2'd0} + 9'd0] <= ddr_dout[15:0];
            lbuf[r_fill][{r_got[6:0], 2'd0} + 9'd1] <= ddr_dout[31:16];
            lbuf[r_fill][{r_got[6:0], 2'd0} + 9'd2] <= ddr_dout[47:32];
            lbuf[r_fill][{r_got[6:0], 2'd0} + 9'd3] <= ddr_dout[63:48];
        end
    end

    // ================= the port ==========================================
    // READS WIN, and a line is fetched as ONE 80-beat burst.
    //
    // Both are lessons from the board, not the bench. The first version gave
    // writes priority and issued reads one word at a time; the bench's
    // memory accepted a command every cycle, so it was exact to a 400-cycle
    // latency -- and on the board the sprites shredded into dashes. Dumping
    // the framebuffer back out of DDR3 through the HPS (/dev/mem mmap)
    // proved the STORED image perfect while the screen was broken: writes
    // were landing, and the read-back was starving behind them -- 80
    // commands a line on a port that takes real time per command, behind a
    // draw that free-runs its whole frame of writes at the start of the
    // raster.
    //
    // So: the reader goes first (the mixer is the one with a deadline; the
    // writer has the whole frame), and a line is ONE burst command whose 80
    // beats stream back on DOUT_READY -- which is what BURSTCNT exists for.
    // The write side stays single-beat: the stored dump proves it keeps up,
    // and single beats let rotation's writes slot between ours without the
    // arbiter needing a lock.
    assign ddr_burstcnt = (rst == R_REQ) ? 8'd80 : 8'd1;
    assign ddr_be       = 8'hFF;
    assign ddr_rd       = (rst == R_REQ);
    assign ddr_we       = (wst == W_ISSUE) && (rst != R_REQ);
    assign ddr_din      = w_acc;
    assign ddr_addr     = (rst == R_REQ)
                        ? line_word(~par, nf[7:0])
                        : (line_word(w_bank, w_line) + 29'(w_word));

    always_ff @(posedge clk) begin
        if (reset) begin
            wst <= W_IDLE; rst <= R_IDLE;
            r_fill <= 2'd0; buf_ok <= '0; nf <= 9'd0;
            for (int b = 0; b < NRB; b++) buf_line[b] <= 8'd0;
            w_word <= 0; w_pix <= 0; r_word <= 0; r_got <= 8'd0;
        end else begin
            if (frame_start) begin
                buf_ok <= '0;           // last frame's lines are stale
                nf     <= 9'd0;         // refill the window from line 0
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
                // advance only on a cycle our write was actually on the bus
                // (a pending read command masks ddr_we)
                W_ISSUE: if (!ddr_busy && ddr_we) begin
                    w_pix <= 2'd0;
                    if (w_word == WPL - 1) wst <= W_IDLE;
                    else begin w_word <= w_word + 7'd1; wst <= W_RD; end
                end
                default: wst <= W_IDLE;
            endcase

            // ---- read FSM: keep the buffer the mixer is NOT using filled
            // with the line after the one it is on
            // Walk forward: keep the window [rd_line, rd_line+NRB) filled.
            case (rst)
                R_IDLE: if (!nf[8] && (nf < {1'b0, rd_line} + NRB)) begin
                    r_fill <= nf[1:0];
                    r_word <= 0; r_got <= 8'd0; rst <= R_REQ;
                end
                // one command for the whole line; the beats stream back
                R_REQ: if (!ddr_busy) rst <= R_WAIT;
                // >=, not the exact cycle the last word lands: with a fast
                // memory the returns keep pace with the requests and this
                // counter is already past it by the time R_WAIT is entered.
                R_WAIT: if (r_got >= WPL) begin
                    buf_line[r_fill] <= nf[7:0];
                    buf_ok[r_fill]   <= 1'b1;
                    nf               <= nf + 9'd1;
                    rst              <= R_IDLE;
                end
                default: rst <= R_IDLE;
            endcase
            if (ddr_dout_ready && rst != R_IDLE) r_got <= r_got + 8'd1;
        end
    end

endmodule
