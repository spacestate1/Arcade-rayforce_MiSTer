//============================================================================
//  Sprite engine: the walked list, drawn per screen line into a line buffer.
//
//  No framebuffer. The measurement in HANDOFF.md showed Ray Force never uses
//  sprite trails and never exceeds a few tens of sprites on a line, so a
//  full-screen 16-bit framebuffer (~160 BRAM) is not needed. Instead:
//
//    PREPASS (once per frame, runs the whole frame long, off the beam):
//      1. rf_video_spr_list walks sprite RAM -> a compact sprite list.
//      2. EXPAND: each sprite is spread over the screen lines it covers. The
//         dy8 accumulator maps its 16 source rows (walked 15->0) to screen
//         lines; EVERY in-range row becomes a record appended to that line's
//         bucket (a linked list: head/tail per line, a next pointer per
//         record). No vertical dedup -- when zoom crushes several rows onto
//         one line they OVERLAY, a later row filling the transparent gaps of
//         an earlier one. Row order (15->0) and sprite order (list order) are
//         chosen so the bucket, drawn head->tail with overwrite, lands the
//         LAST write on the model's winner (forward-row / reverse-list
//         write-if-empty, first opaque wins).
//
//    DRAW (runs AHEAD of the mixer, into a ring of NB line buffers):
//      from frame_start, draw lines 0..255 in order as fast as the fetches
//      allow, up to NB-1 lines ahead of the line the mixer is composing
//      (rd_line) -- the bank the mixer reads is the one bank the draw may
//      not touch. The first version drew exactly one line per raster line,
//      so a dense line had one line's 3456 clocks and no more; the board
//      showed 3582-clock lines in attract mode and lost the next line each
//      time. The buckets are ready for the whole frame and sprites cost
//      ~10 % of it on average, so only local density matters, and a ring
//      of NB absorbs NB-1 consecutive dense lines.
//      Per line: walk the line's bucket; for each record fetch its 16-pixel sprite row
//      (rf_spr_gfx_bus) and lay it down with the dx8 accumulator -- x zoom,
//      the "last source pixel wins a shared screen pixel" dedup, flipx, the
//      pen mask, the colour base -- overwriting, into a double-banked line
//      buffer the mixer samples at smp_x. TWO fetches are kept in flight:
//      two rf_spr_gfx_bus instances take alternate records and a two-slot
//      queue hands them to the draw in issue order (the order is what the
//      overwrite semantics rest on). With one fetch in flight a record cost
//      the whole SDRAM round trip (~30 clocks on the board: two bursts on
//      the lowest-priority channel plus the CDC both ways) and a 114-record
//      line overran the 3456-clock budget; with two, the channel is kept
//      busy and the 17-clock draw is the bound. sim/Makefile `pipe-lat`
//      is the regression for this at a hardware-like latency.
//
//  The bucket store is DOUBLE BANKED: the prepass fills one bank across the
//  whole frame while the draw reads last frame's bank, swapped at frame_start.
//  So sprites lag the playfields by one frame here; MAME's sprite_lag for
//  gunlock is 2 -- close, tuned on hardware if it reads wrong, the same way
//  the raster timing was. Prepass and draw are separate always blocks: the
//  buckets have a single writer (the prepass, into the write bank) and the
//  draw only reads (the read bank), so there is no multi-driver on the store.
//
//  The line buffer needs no clearing: each entry tags the line it was written
//  for, and a read for another line reads as empty. Zoom is reproduced
//  exactly (dy8/dx8), which Ray Force needs -- it shrinks sprites to a line.
//
//  Storage -- sized for the MLAB budget, which is the binding one. A record
//  is only {sprite index, source row} (14 bits): the per-sprite data (x, x
//  scale, code, colour, flipx) is stored ONCE, in sl_d, and looked up by the
//  draw. The list is split by consumer: sl_y (ty, y scale, flipy) is read
//  only by the expand, in the same prepass that wrote it, so it is
//  single-banked; sl_d is read by the draw a frame later, so it is
//  double-banked like the record store. The buckets are built by counting
//  sort (see the store below), so there are no per-line heads, tails or
//  next pointers -- one run table per bank, in an rf_bram.
//
//  History: the first version stored 54-bit records in linked lists and at
//  3328 records/bank needed 960 of the device's 985 MLAB-capable LABs; the
//  second slimmed the records and reached 4096; this one drops the links
//  and holds 8192 in the same ~780 MLABs.
//
//  MLAB rules (each learned from a failed map): one full-word read wire per
//  memory, sliced afterwards; `no_rw_check` because the async-read MLAB has
//  no defined same-cycle same-address read-during-write -- so the RTL never
//  does one. rec/sl_d: the prepass writes bank wb, the draw reads bank rb.
//  sl_y: written in P_WALK, read in P_C0/P_E0. cnt/lim: every read-modify-
//  write is a read state followed by a write state (P_CRD/P_CWR, P_SRD/
//  P_SWR, P_ERD/P_EWR). One write per array per cycle throughout.
//
//  The two gfx planes share the one free SDRAM channel through
//  rf_spr_ch_share at the top level (the bench wraps the pipe the same way).
//============================================================================

module rf_video_spr
(
    input  logic        clk,
    input  logic        reset,
    input  logic        clk_ram,

    input  logic        frame_start,    // swap banks, start a fresh prepass
    output logic        prepass_busy,
    output logic        line_busy,      // a line is being drawn (drops for
                                        // one cycle between lines)
    output logic  [8:0] lines_done,     // lines drawn so far this frame, 0-256
    output logic [15:0] rec_peak,       // records the last prepass built
    output logic [15:0] rec_drop,       // sprite rows it had no room for

    output logic [14:0] spr_addr,       // sprite RAM (walker)
    input  logic [15:0] spr_q,

    // sprite gfx SDRAM: two fetch buses (A, B) of two planes (lo, hi) each,
    // merged onto one channel by rf_spr_ch_share outside this module
    output logic [26:1] ch_a_lo_addr,
    input  logic [63:0] ch_a_lo_dout,
    output logic        ch_a_lo_req,
    input  logic        ch_a_lo_ready,
    output logic [26:1] ch_a_hi_addr,
    input  logic [63:0] ch_a_hi_dout,
    output logic        ch_a_hi_req,
    input  logic        ch_a_hi_ready,
    output logic [26:1] ch_b_lo_addr,
    input  logic [63:0] ch_b_lo_dout,
    output logic        ch_b_lo_req,
    input  logic        ch_b_lo_ready,
    output logic [26:1] ch_b_hi_addr,
    input  logic [63:0] ch_b_hi_dout,
    output logic        ch_b_hi_req,
    input  logic        ch_b_hi_ready,

    input  logic  [8:0] rd_x,           // 0..319 (raster x - 46)
    input  logic  [7:0] rd_line,        // line the mixer is composing
    output logic [15:0] rd_color,       // 0 = none
    output logic  [3:0] rd_used
);
    localparam int VX0 = 46, VX1 = 365, VY0 = 31, VY1 = 254;
    localparam int NSPR = 1024;

    // ---- the walker ------------------------------------------------------
    logic        wk_start, wk_busy, wk_done;
    logic        wk_flip; logic [1:0] wk_extra; logic [4:0] wk_penmask;
    logic        s_valid;
    logic signed [17:0] s_tx, s_ty;
    logic        [8:0]  s_sx, s_sy;
    logic       [16:0]  s_code;
    logic        [7:0]  s_color;
    logic               s_fx, s_fy;
    logic        [1:0]  s_pri;

    rf_video_spr_list walker (
        .clk(clk), .reset(reset),
        .start(wk_start), .start_bank(1'b0), .busy(wk_busy), .done(wk_done),
        .o_flip(wk_flip), .o_extra(wk_extra), .o_penmask(wk_penmask),
        .spr_addr(spr_addr), .spr_q(spr_q),
        .s_valid(s_valid), .s_tx(s_tx), .s_ty(s_ty), .s_sx(s_sx), .s_sy(s_sy),
        .s_code(s_code), .s_color(s_color), .s_fx(s_fx), .s_fy(s_fy), .s_pri(s_pri)
    );

    // ---- stored sprite list, split by consumer ---------------------------
    // sl_y: {ty[17:0], sy[8:0], fy}                 -- the expand (prepass)
    // sl_d: {tx[17:0], sx[8:0], code[13:0], color[7:0], fx} -- the draw
    (* ramstyle = "MLAB, no_rw_check" *) logic [27:0] sl_y [0:NSPR-1];
    (* ramstyle = "MLAB, no_rw_check" *) logic [49:0] sl_d [0:1][0:NSPR-1];
    logic [10:0] nspr;

    // ---- bucket store, double banked: a COUNTING SORT ---------------------
    // Pass 1 counts the rows landing on each line, a prefix sum hands every
    // line a contiguous run [base, end) of the record store, pass 2 places
    // each row at its line's fill pointer. Rows are visited in the same
    // order both passes (list order, rows 15->0), so a run IS the bucket in
    // draw order. No linked list and no next pointers: that is what pays
    // for 8192 records per bank at the MLAB cost of 4096 linked ones.
    //
    // Overflow: the prefix sum clamps each line's run to what is left, in
    // line order, so a frame past 8192 rows loses rows from its last lines
    // and reports them on the self-test page (rec_drop). The busiest dumped
    // frame needs 3144; a boss transition is what 8192 is for.
    localparam int NREC = 8192;         // per bank
    localparam int RW   = 13;           // record index width
    localparam int RW1  = RW + 1;       // the prefix sum reaches NREC
    // record: {sidx[9:0], srow[3:0]}
    (* ramstyle = "MLAB, no_rw_check" *) logic [13:0]   rec [0:1][0:NREC-1];
    // per line, prepass scratch: rows counted (pass 1), then the fill
    // pointer (pass 2); and the clamped end of the line's run
    (* ramstyle = "MLAB, no_rw_check" *) logic [RW-1:0] cnt [0:255];
    (* ramstyle = "MLAB, no_rw_check" *) logic [RW-1:0] lim [0:255];
    logic [15:0] rows_tot;              // rows the frame asked for
    logic [15:0] drop_cnt;              // rows refused (store full)
    logic        wb, rb;                // write (prepass) / read (draw) bank
    logic  [4:0] penmask_r;
    logic        flip_r;

    // the draw's run table: {end, base} per line, written by the prefix
    // pass into bank wb, read by the draw at {rb, nxt} -- data the cycle
    // after the address, so it is presented during D_IDLE
    logic            bt_we;
    logic      [8:0] bt_wa;
    logic [2*RW-1:0] bt_wd, bt_q;

    rf_bram #(.WIDTH(2*RW), .AW(9)) u_bt (
        .clk(clk),
        .waddr(bt_wa), .wdata(bt_wd), .wren(bt_we),
        .raddr({rb, nxt[7:0]}), .q(bt_q)
    );

    // ---- prepass state ---------------------------------------------------
    logic [10:0] ex_i;
    logic  [4:0] ex_yy;
    logic signed [24:0] ex_dy8;
    logic        [8:0]  ex_sy;
    logic               ex_fy;
    logic  [8:0] clr_i;                 // cnt clear, runs under the walk
    logic        wk_fin;                // the walk finished (clear may not have)
    logic  [7:0] sum_y;
    logic [RW:0] sum_acc;               // one bit wider: reaches NREC
    logic [RW-1:0] c_rd, f_rd, l_rd;    // MLAB reads, taken the cycle before use

    wire signed [24:0] ex_dy   = ex_dy8 >>> 8;
    wire               ex_inr  = (ex_dy >= VY0) && (ex_dy <= VY1);
    wire  [7:0]        ex_dyb  = ex_dy[7:0];
    wire  [3:0]        ex_srow = ex_yy[3:0] ^ {4{ex_fy}};

    // One full-word read wire per memory, sliced afterwards: Quartus will not
    // infer an MLAB from N separately-sliced reads of the same array (the
    // build died on exactly that -- "can't infer memory for variable 'slist'"),
    // this is the canonical pattern it accepts.
    wire [27:0]        sly_w  = sl_y[ex_i];
    wire signed [17:0] sly_ty = sly_w[27:10];
    wire        [8:0]  sly_sy = sly_w[9:1];
    wire               sly_fy = sly_w[0];

    // the prefix sum's clamp: what is left of the store for this line
    wire [RW:0]   sum_left = (sum_acc >= RW1'(NREC)) ? '0 : RW1'(NREC) - sum_acc;
    wire [RW:0]   sum_cap  = ({1'b0, c_rd} > sum_left) ? sum_left : {1'b0, c_rd};
    wire [RW:0]   sum_end  = sum_acc + sum_cap;

    // ---- draw state ------------------------------------------------------
    logic  [4:0] dr_xx;
    logic signed [24:0] dr_dx8;
    logic        [8:0]  dr_sx;
    logic       [12:0]  dr_base;
    logic        [1:0]  dr_pri;
    logic               dr_fx;
    logic        [7:0]  dr_line;
    logic        [3:0]  dr_used;
    logic       [95:0]  dr_pix;

    wire signed [24:0] dr_dx  = dr_dx8 >>> 8;
    wire signed [24:0] dr_dxn = (dr_dx8 + $signed({16'd0, dr_sx})) >>> 8;
    wire               dr_vis = (dr_dx >= VX0) && (dr_dx <= VX1) && (dr_dx != dr_dxn);
    wire  [3:0]        dr_src = dr_xx[3:0] ^ {4{dr_fx}};
    wire  [5:0]        dr_pen6= dr_pix[6*dr_src +: 6];
    wire  [4:0]        dr_pen = dr_pen6[4:0] & penmask_r;
    wire  [8:0]        dr_ix  = dr_dx[8:0] - 9'd46;

    // record at `fc` -- the next to issue; the line's run ends at `fe`. Two
    // lookups deep: rec[fc] gives the sprite index (async), registered into
    // sidx_r, then sl_d[sidx_r] gives the sprite (async). So the sprite
    // fields are good from TWO cycles after fc changes (fc_ok); every use
    // below waits for that.
    logic [RW-1:0] fc, fe;
    wire [13:0]        rc_w    = rec[rb][fc];
    wire        [9:0]  rc_sidx = rc_w[13:4];
    wire        [3:0]  rc_srow = rc_w[3:0];
    logic       [9:0]  sidx_r;
    always_ff @(posedge clk) sidx_r <= rc_sidx;
    wire [49:0]        sd_w    = sl_d[rb][sidx_r];
    wire signed [17:0] sd_tx   = sd_w[49:32];
    wire        [8:0]  sd_sx   = sd_w[31:23];
    wire       [13:0]  sd_code = sd_w[22:9];
    wire        [7:0]  sd_col  = sd_w[8:1];
    wire               sd_fx   = sd_w[0];
    wire signed [17:0] sd_x8   = sd_tx + 18'sd128;

    // ---- prefetch queue: two slots, slot i bound to fetch bus i ----------
    // Records are issued into alternate slots (q_is) and consumed from
    // alternate slots (q_cs), so the slot at q_cs is always the OLDEST
    // outstanding one and the draw order equals the bucket order. A slot
    // carries the sprite fields the draw needs, captured at issue, because
    // by promotion time `fc` has moved on.
    logic [1:0]        q_busy, q_ready;   // issued / pixels arrived
    logic [1:0][95:0]  q_pix;
    logic [1:0][17:0]  q_x8;
    logic [1:0][8:0]   q_sx;
    logic [1:0][7:0]   q_col;
    logic [1:0]        q_fx;
    logic              q_is, q_cs;
    logic              cur;              // a record is being drawn
    logic              fc_ok;            // fc's two-deep lookup has settled

    // ---- sprite gfx fetch, two buses ------------------------------------
    logic [1:0][13:0] gfx_code;
    logic [1:0][3:0]  gfx_row;
    logic [1:0]       gfx_req, gfx_valid, gfx_busy;
    logic [1:0][95:0] gfx_pix;

    rf_spr_gfx_bus gfx_a (
        .clk_cpu(clk), .reset(reset),
        .code(gfx_code[0]), .row(gfx_row[0]), .req(gfx_req[0]),
        .pix(gfx_pix[0]), .valid(gfx_valid[0]), .busy(gfx_busy[0]),
        .clk_ram(clk_ram),
        .ch_lo_addr(ch_a_lo_addr), .ch_lo_dout(ch_a_lo_dout), .ch_lo_req(ch_a_lo_req), .ch_lo_ready(ch_a_lo_ready),
        .ch_hi_addr(ch_a_hi_addr), .ch_hi_dout(ch_a_hi_dout), .ch_hi_req(ch_a_hi_req), .ch_hi_ready(ch_a_hi_ready)
    );

    rf_spr_gfx_bus gfx_b (
        .clk_cpu(clk), .reset(reset),
        .code(gfx_code[1]), .row(gfx_row[1]), .req(gfx_req[1]),
        .pix(gfx_pix[1]), .valid(gfx_valid[1]), .busy(gfx_busy[1]),
        .clk_ram(clk_ram),
        .ch_lo_addr(ch_b_lo_addr), .ch_lo_dout(ch_b_lo_dout), .ch_lo_req(ch_b_lo_req), .ch_lo_ready(ch_b_lo_ready),
        .ch_hi_addr(ch_b_hi_addr), .ch_hi_dout(ch_b_hi_dout), .ch_hi_req(ch_b_hi_req), .ch_hi_ready(ch_b_hi_ready)
    );

    // ---- line buffer ring: NB banks x 320 x {line[7:1], val[12:0]} -------
    // Bank = line mod NB. The tag that tells a stale entry from this line's
    // is line[7:1] -- it differs from any other line sharing the bank while
    // NB <= 128 -- so an entry is 20 bits and NB x 512 x 20 bits is NB/2
    // M10Ks (2 banks were three M10Ks at 21 bits).
    localparam int NB  = 4;
    localparam int NBW = $clog2(NB);

    logic            wr_en;
    logic [NBW+8:0]  wr_addr;
    logic [19:0]     wr_data, lb_q;

    rf_bram #(.WIDTH(20), .AW(NBW + 9)) u_lbuf (
        .clk(clk),
        .waddr(wr_addr), .wdata(wr_data), .wren(wr_en),
        .raddr({rd_line[NBW-1:0], rd_x}), .q(lb_q)
    );
    assign rd_color = (lb_q[19:13] == rd_line[7:1]) ? {3'd0, lb_q[12:0]} : 16'd0;

    logic [3:0] used_bank [0:NB-1];
    assign rd_used = used_bank[rd_line[NBW-1:0]];

    // ---- the run-ahead window ----------------------------------------------
    // nxt is the next line to draw (256 = the frame is done). The draw may
    // run while nxt is within NB-1 lines past the mixer's line, in 8-bit
    // modular arithmetic so the frame wrap (mixer still on 255 when the
    // draw restarts at 0) needs no special case.
    logic        active;
    logic  [8:0] nxt;
    wire   [7:0] ahead    = nxt[7:0] - rd_line;
    wire         can_draw = active && !nxt[8] && (ahead <= 8'(NB - 1));
    assign lines_done = nxt;

    // ================= PREPASS FSM (writes bank wb) =================
    typedef enum logic [3:0] {
        P_IDLE, P_WALK,
        P_C0, P_CRD, P_CWR,             // pass 1: count rows per line
        P_SRD, P_SWR,                   // prefix sum -> runs
        P_E0, P_ERD, P_EWR              // pass 2: place rows
    } pst_t;
    pst_t pst;
    assign prepass_busy = (pst != P_IDLE);

    // advance the row walk. ROW is the state that handles the next row of
    // this sprite, SPR the one that loads the next sprite -- written out
    // explicitly, every time (a "stay" that lands in the wrong state was
    // the bug the spr-line bench caught in the linked-list version).
    `define SPR_ADV(ROW, SPR) \
        if (ex_yy == 5'd0) begin ex_i <= ex_i + 11'd1; pst <= SPR; end \
        else begin ex_dy8 <= ex_dy8 - $signed({16'd0, ex_sy}); \
                   ex_yy  <= ex_yy - 5'd1; pst <= ROW; end
    // load sprite ex_i's expand state (its 16 rows walked 15 -> 0)
    `define SPR_LOAD_EX \
        begin ex_sy <= sly_sy; ex_fy <= sly_fy; ex_yy <= 5'd15; \
              ex_dy8 <= $signed(sly_ty) + (flip_r ? 25'sd0 : 25'sd255) \
                      + $signed({16'd0, ({sly_sy, 4'd0} - {4'd0, sly_sy})}); end

    always_ff @(posedge clk) begin
        wk_start <= 1'b0;
        bt_we    <= 1'b0;
        if (reset) begin
            pst <= P_IDLE;
            wb  <= 1'b0; rb <= 1'b1;
            nspr <= 11'd0;
        end else if (frame_start) begin
            // publish the bank just built, start filling the other
            rb <= wb;
            wb <= ~wb;
            nspr     <= 11'd0;
            clr_i    <= 9'd0;
            wk_fin   <= 1'b0;
            rows_tot <= 16'd0;
            drop_cnt <= 16'd0;
            wk_start <= 1'b1;
            pst <= P_WALK;
        end else case (pst)
            // the walk streams sprites in; the count table is cleared under
            // it (256 cycles -- an empty list finishes first, hence wk_fin)
            P_WALK: begin
                if (s_valid && nspr < 11'(NSPR)) begin
                    sl_y[nspr]     <= {s_ty, s_sy, s_fy};
                    sl_d[wb][nspr] <= {s_tx, s_sx, s_code[13:0], s_color, s_fx};
                    nspr <= nspr + 11'd1;
                end
                if (!clr_i[8]) begin
                    cnt[clr_i[7:0]] <= '0;
                    clr_i <= clr_i + 9'd1;
                end
                if (wk_done) begin
                    penmask_r <= wk_penmask;
                    flip_r    <= wk_flip;
                    wk_fin    <= 1'b1;
                end
                if ((wk_done || wk_fin) && clr_i[8]) begin
                    ex_i <= 11'd0;
                    pst  <= P_C0;
                end
            end

            // ---- pass 1: count
            P_C0: begin
                if (ex_i >= nspr) begin
                    sum_y   <= 8'd0;
                    sum_acc <= '0;
                    pst     <= P_SRD;
                end else begin
                    `SPR_LOAD_EX
                    pst <= P_CRD;
                end
            end
            P_CRD: begin
                if (ex_inr) begin
                    c_rd <= cnt[ex_dyb];
                    pst  <= P_CWR;
                end else begin
                    `SPR_ADV(P_CRD, P_C0)
                end
            end
            P_CWR: begin
                cnt[ex_dyb] <= c_rd + 1'b1;
                if (rows_tot != 16'hFFFF) rows_tot <= rows_tot + 16'd1;
                `SPR_ADV(P_CRD, P_C0)
            end

            // ---- prefix sum: line y gets [sum_acc, sum_acc + cap); cnt[y]
            // becomes its fill pointer, lim[y] its end. Ends are 13-bit
            // modular (8192 reads as 0): the draw compares for equality and
            // fc wraps with it, so a run touching the top of the store is
            // still walked in full.
            P_SRD: begin
                c_rd <= cnt[sum_y];
                pst  <= P_SWR;
            end
            P_SWR: begin
                bt_we   <= 1'b1;
                bt_wa   <= {wb, sum_y};
                bt_wd   <= {sum_end[RW-1:0], sum_acc[RW-1:0]};
                lim[sum_y] <= sum_end[RW-1:0];
                cnt[sum_y] <= sum_acc[RW-1:0];
                sum_acc <= sum_end;
                sum_y   <= sum_y + 8'd1;
                if (sum_y == 8'd255) begin
                    ex_i <= 11'd0;
                    pst  <= P_E0;
                end else begin
                    pst  <= P_SRD;
                end
            end

            // ---- pass 2: place
            P_E0: begin
                if (ex_i >= nspr) begin
                    // what the frame asked for and what was refused, for
                    // the self-test page: refused rows come off the END of
                    // the run order, i.e. the sprites drawn on top
                    rec_peak <= rows_tot;
                    rec_drop <= drop_cnt;
                    pst <= P_IDLE;
                end else begin
                    `SPR_LOAD_EX
                    pst <= P_ERD;
                end
            end
            P_ERD: begin
                if (ex_inr) begin
                    f_rd <= cnt[ex_dyb];
                    l_rd <= lim[ex_dyb];
                    pst  <= P_EWR;
                end else begin
                    `SPR_ADV(P_ERD, P_E0)
                end
            end
            P_EWR: begin
                if (f_rd != l_rd) begin
                    rec[wb][f_rd] <= {ex_i[9:0], ex_srow};
                    cnt[ex_dyb]   <= f_rd + 1'b1;
                end else if (drop_cnt != 16'hFFFF) begin
                    drop_cnt <= drop_cnt + 16'd1;
                end
                `SPR_ADV(P_ERD, P_E0)
            end

            default: pst <= P_IDLE;
        endcase
    end
    `undef SPR_ADV
    `undef SPR_LOAD_EX

    // ================= DRAW FSM (reads bank rb) =================
    // Issue: whenever the next record's lookup has settled and the issue
    // slot is free, start its fetch and advance fc. Promote: when the
    // current record is drawn (or there is none), take the consume slot as
    // soon as its pixels are in. Done: nothing drawing, nothing in flight,
    // no records left.
    typedef enum logic [1:0] { D_IDLE, D_LEAD0, D_RUN, D_DONE } dst_t;
    dst_t dst;
    assign line_busy = (dst != D_IDLE && dst != D_DONE);

    always_ff @(posedge clk) begin
        gfx_req <= 2'b00;
        wr_en   <= 1'b0;
        fc_ok   <= 1'b1;                 // cleared below whenever fc changes

        // capture completions (bus i serves slot i)
        if (gfx_valid[0] && q_busy[0]) begin q_pix[0] <= gfx_pix[0]; q_ready[0] <= 1'b1; end
        if (gfx_valid[1] && q_busy[1]) begin q_pix[1] <= gfx_pix[1]; q_ready[1] <= 1'b1; end

        if (reset) begin
            dst <= D_IDLE; q_busy <= 2'b00; q_ready <= 2'b00; cur <= 1'b0;
            active <= 1'b0; nxt <= 9'd0;
        end else if (frame_start) begin
            // the buckets just swapped: restart at line 0. In normal running
            // the draw finished line 255 long ago; a fetch still in flight
            // (a frame_start mid-line, e.g. the bench's priming pass) is
            // simply not captured -- q_busy is cleared -- and the bus stays
            // busy until it lands, which the issue rule waits for.
            dst <= D_IDLE; q_busy <= 2'b00; q_ready <= 2'b00; cur <= 1'b0;
            active <= 1'b1; nxt <= 9'd0;
        end else case (dst)
            D_IDLE: if (can_draw) begin
                dr_line <= nxt[7:0];
                dr_used <= 4'd0;
                q_busy  <= 2'b00; q_ready <= 2'b00;
                q_is    <= 1'b0;  q_cs    <= 1'b0;
                cur     <= 1'b0;
                dst <= D_LEAD0;
            end

            // the run table answers for {rb, nxt} (presented during D_IDLE)
            D_LEAD0: begin
                if (bt_q[RW-1:0] == bt_q[2*RW-1:RW]) begin
                    used_bank[dr_line[NBW-1:0]] <= dr_used;     // empty line
                    dst <= D_DONE;
                end else begin
                    fc    <= bt_q[RW-1:0];
                    fe    <= bt_q[2*RW-1:RW];
                    fc_ok <= 1'b0;
                    dst   <= D_RUN;
                end
            end

            D_RUN: begin
                // ---- issue the next record into the free slot
                if (fc != fe && fc_ok && !q_busy[q_is] && !gfx_busy[q_is]) begin
                    gfx_code[q_is] <= sd_code;
                    gfx_row[q_is]  <= rc_srow;
                    gfx_req[q_is]  <= 1'b1;
                    q_busy[q_is]   <= 1'b1;
                    q_ready[q_is]  <= 1'b0;
                    q_x8[q_is]     <= sd_x8;
                    q_sx[q_is]     <= sd_sx;
                    q_col[q_is]    <= sd_col;
                    q_fx[q_is]     <= sd_fx;
                    fc    <= fc + 1'b1;
                    fc_ok <= 1'b0;
                    q_is  <= ~q_is;
                end

                // ---- draw the current record / promote the next / finish
                if (!cur || dr_xx == 5'd16) begin
                    if (q_ready[q_cs]) begin
                        dr_pix  <= q_pix[q_cs];
                        dr_sx   <= q_sx[q_cs];
                        dr_base <= 13'h1000 + {1'b0, q_col[q_cs], 4'd0};
                        dr_pri  <= q_col[q_cs][7:6];
                        dr_fx   <= q_fx[q_cs];
                        dr_dx8  <= $signed(q_x8[q_cs]);
                        dr_xx   <= 5'd0;
                        q_busy[q_cs]  <= 1'b0;
                        q_ready[q_cs] <= 1'b0;
                        q_cs <= ~q_cs;
                        cur  <= 1'b1;
                    end else if (!q_busy[q_cs] && fc == fe) begin
                        used_bank[dr_line[NBW-1:0]] <= dr_used;
                        dst <= D_DONE;
                    end
                    // else wait for the oldest fetch to land
                end else begin
                    if (dr_vis && dr_pen != 5'd0) begin
                        wr_en   <= 1'b1;
                        wr_addr <= {dr_line[NBW-1:0], dr_ix};
                        wr_data <= {dr_line[7:1], dr_base | {8'd0, dr_pen}};
                        dr_used <= dr_used | (4'd1 << dr_pri);
                    end
                    dr_dx8 <= dr_dx8 + $signed({16'd0, dr_sx});
                    dr_xx  <= dr_xx + 5'd1;
                end
            end

            D_DONE: begin
                nxt <= nxt + 9'd1;
                dst <= D_IDLE;
            end
            default: dst <= D_IDLE;
        endcase
    end

endmodule
