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
//  is a RUN: {sprite index, first source row, last source row} (18 bits),
//  the consecutive source rows of one sprite that land on the same screen
//  line. A y-shrunk sprite puts several of its 16 rows on one line, and the
//  draw lays them down back to back in the same order either way, so one
//  record for the run costs no exactness and no draw time -- only store.
//  Measured over every Ray Force dump (2026-08-29): 1.0-1.3 rows a record in
//  ordinary play, 2.8-3.25 in the shrink-heavy scenes (frame 4200: 2960 rows
//  -> 1046 records), and it is the shrink scenes that set the board's peak.
//  The per-sprite data (x, x scale, code, colour, flipx) is stored ONCE, in
//  sl_d, and looked up by the draw. The list is split by consumer: sl_y (ty, y scale, flipy) is read
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

    // which F3 visarea this game uses; feeds the sprite cull bounds
    input  logic  [1:0] vis_mode,

    input  logic        frame_start,    // swap banks, start a fresh prepass
    output logic        prepass_busy,
    output logic        line_busy,      // a line is being drawn (drops for
                                        // one cycle between lines)
    output logic  [8:0] lines_done,     // lines drawn so far this frame, 0-256
    // The flipscreen bit, straight from the sprite command word (word 5 bit
    // 13) -- the same place MAME takes m_flipscreen from. The playfields and
    // the pivot layer need it too, and it must be the GAME's bit rather than
    // a constant: Ray Force sets it permanently, Elevator Action Returns does
    // not, and this core had it wired to 1, so that game rendered upside down.
    output logic        o_flipscreen,

    output logic [15:0] rec_peak,       // records the last prepass built
    output logic [15:0] rec_drop,       // sprite rows it had no room for
    // Why a line is slow, which the clock count alone cannot say: is it
    // carrying a lot of rows, or is each row's fetch slow? SPRLINE says a
    // line took 15864 clocks; the worst line in every dumped frame carries
    // only 61 rows, and the draw loop is 17 clocks a row, so either the
    // board's lines are far denser than any dump (all of them are attract)
    // or a row costs ~260 clocks and is almost all fetch wait. These two
    // numbers divide one case from the other.
    output logic [15:0] fetch_max,      // longest single gfx fetch, in clocks
    output logic [15:0] rows_line_max,  // most rows drawn on one line

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
    // Visible span. X is the same for every F3 game; the Y pair is the
    // game's visarea and MUST follow vis_mode -- it is the per-row clip that
    // matches the model's _drawgfx, so a window narrower than the game's
    // real one silently drops sprite rows on the lines outside it (Elevator
    // Action Returns shows 24..255 where Ray Force shows 31..254).
    localparam int VX0 = 46, VX1 = 365;
    wire [8:0] VY0 = (vis_mode == 2'd0) ? 9'd31 :
                     (vis_mode == 2'd1) ? 9'd32 : 9'd24;
    wire [8:0] VY1 = (vis_mode == 2'd0) ? 9'd254 :
                     (vis_mode == 2'd2) ? 9'd247 : 9'd255;
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
        .clk(clk), .reset(reset), .vis_mode(vis_mode),
        .start(wk_start), .start_bank(1'b0), .busy(wk_busy), .done(wk_done),
        .o_flip(wk_flip), .o_extra(wk_extra), .o_penmask(wk_penmask),
        .spr_addr(spr_addr), .spr_q(spr_q),
        .s_valid(s_valid), .s_tx(s_tx), .s_ty(s_ty), .s_sx(s_sx), .s_sy(s_sy),
        .s_code(s_code), .s_color(s_color), .s_fx(s_fx), .s_fy(s_fy), .s_pri(s_pri)
    );

    // ---- stored sprite list, split by consumer ---------------------------
    // sl_y: {ty[17:0], sy[8:0], fy}                 -- the expand (prepass)
    // sl_d: {tx[17:0], sx[8:0], code[14:0], color[7:0], fx} -- the draw
    (* ramstyle = "MLAB, no_rw_check" *) logic [27:0] sl_y [0:NSPR-1];
    (* ramstyle = "MLAB, no_rw_check" *) logic [50:0] sl_d [0:1][0:NSPR-1];
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
    // line order, so a frame past NREC rows loses rows from its LAST lines
    // and reports them on the self-test page (rec_drop). That is the same
    // visible symptom as the sprite fetch running late -- sprites missing
    // from the bottom of the frame -- so when the bottom goes, read
    // SPR REC : DROP before blaming the fetch path.
    //
    // Sizing history. The busiest dumped frame needs 3144 rows; the BOARD
    // peaked at 8296 in a five-minute attract capture (2026-08-28) and
    // dropped 104 rows once in 632 page passes, which 8192 could not hold.
    // 12288 was chosen as ~45 % over that. It is not: a longer run on
    // 2026-08-29 (build 29101900) peaked at 10714 rows, 87 % of the store,
    // with 0 dropped -- 13 % margin, not 45 %. Whether the game ever asks
    // for more than 12288 is unknown; nothing has yet.
    //
    // Growing it is not free to try. An MLAB is 32 x 20 bits, so this store
    // is 2 x 384 = 768 MLABs at 18 bits a record (two bits of every word
    // unused, and no narrower packing fits: 64 x 10 mode is too narrow).
    // 16384 would be 1024. Run-length records (2026-08-29) are the cheaper
    // answer: the same 12288 slots hold 1.0-3.25x the rows they used to. The fitter has already died once at ~960 MLABs
    // in this design (HANDOFF, "The BRAM wall had moved into the MLABs")
    // and no fit report since B15 records the real headroom, so raising
    // NREC is a 35-minute build to find out, and it should be its own
    // build rather than confound one that is testing something else.
    // M10K is not an alternative either: 24 blocks a bank against ~26 free.
    localparam int NREC = 12288;        // per bank
    localparam int RW   = 14;           // record index width
    localparam int RW1  = RW + 1;       // the prefix sum reaches NREC
    // record: {sidx[9:0], srow_a[3:0], srow_b[3:0]} -- the run's first and
    // last source row. The draw steps from a toward b, so the direction
    // (rows walk 15 -> 0, and flipy inverts the source row) is implied.
    (* ramstyle = "MLAB, no_rw_check" *) logic [17:0]   rec [0:1][0:NREC-1];
    // per line, prepass scratch: rows counted (pass 1), then the fill
    // pointer (pass 2); and the clamped end of the line's run
    (* ramstyle = "MLAB, no_rw_check" *) logic [RW-1:0] cnt [0:255];
    (* ramstyle = "MLAB, no_rw_check" *) logic [RW-1:0] lim [0:255];
    logic [15:0] rows_tot;              // records the frame asked for
    logic [15:0] drop_cnt;              // records refused (store full)
    logic        wb, rb;                // write (prepass) / read (draw) bank
    logic  [4:0] penmask_r;
    logic        flip_r;
    // Published continuously rather than registered again: two always_ff
    // blocks assigning it is a multiple-driver error in Quartus (Verilator
    // only warns), and flip_r already holds exactly the value.
    assign o_flipscreen = flip_r;

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
    // the run being built (r_*) and the one being emitted (e_*). A row that
    // lands on a new line closes the open run into e_* and opens the next
    // in r_* in the same cycle, so the two must be separate registers.
    logic        r_open;
    logic  [7:0] r_dy, e_dy;
    logic  [3:0] r_a, r_b, e_a, e_b;
    logic        ret_end;               // after the emit: sprite end, not next row

    wire signed [24:0] ex_dy   = ex_dy8 >>> 8;
    wire               ex_inr  = (ex_dy >= $signed({16'd0, VY0})) &&
                                 (ex_dy <= $signed({16'd0, VY1}));
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
    wire [17:0]        rc_w    = rec[rb][fc];
    wire        [9:0]  rc_sidx = rc_w[17:8];
    wire        [3:0]  rc_a    = rc_w[7:4];      // the run's first source row
    wire        [3:0]  rc_b    = rc_w[3:0];      // ... and its last
    // partway through the record at fc: the next row of it to issue. fc
    // only advances on the run's last row, so fc_ok stays settled between
    // rows and the rows of a run issue on consecutive free slots.
    logic              ir_open;
    logic        [3:0] ir_row;
    wire        [3:0]  is_row  = ir_open ? ir_row : rc_a;
    wire        [3:0]  is_next = (rc_b > rc_a) ? is_row + 4'd1 : is_row - 4'd1;
    logic       [9:0]  sidx_r;
    always_ff @(posedge clk) sidx_r <= rc_sidx;
    wire [50:0]        sd_w    = sl_d[rb][sidx_r];
    wire signed [17:0] sd_tx   = sd_w[50:33];
    wire        [8:0]  sd_sx   = sd_w[32:24];
    wire       [14:0]  sd_code = sd_w[23:9];
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

    // ---- blank-row skip --------------------------------------------------
    // A fetched row whose 16 pens are all zero after the pen mask draws
    // NOTHING: every write below is guarded by (dr_vis && dr_pen != 0). It
    // still costs the full 17-cycle draw loop, and in a dense scene most of
    // what stacks up on a line is sprite edges, which are transparent.
    //
    // Skipping it is exactly equivalent -- not an approximation. The board
    // needs it: SPRFETCH:ROWMAX on build 30101648 read 784 rows on the worst
    // line at 17.8 clocks each, i.e. the draw loop IS the floor and 784 x 17
    // = 13328 clocks against a 3456 budget. No fetch or priority change can
    // touch that; the only ways down are fewer rows or fewer cycles a row,
    // and this is the free half of the first.
    logic q_any;
    always_comb begin
        q_any = 1'b0;
        for (int k = 0; k < 16; k++)
            if ((q_pix[q_cs][6*k +: 5] & penmask_r) != 5'd0) q_any = 1'b1;
    end
    logic              fc_ok;            // fc's two-deep lookup has settled

    // ---- sprite gfx fetch, two buses ------------------------------------
    logic [1:0][14:0] gfx_code;
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

    // ---- line buffer ring: NB banks x 320 x {tag[6:0], val[12:0]} -------
    // Bank = line mod NB, so every line sharing a bank has the same
    // line[NBW-1:0] and is told apart by line[7:NBW]. The tag is that plus
    // the FRAME PARITY:
    //
    //     tag = {par, line[7:NBW]}
    //
    // The parity is the cheap half of the fix for the ghosting reported from
    // the cabinet on 2026-08-28 (player shots leaving their pixels behind
    // along the whole path). The original claim that "the line buffer needs
    // no clearing" was wrong: an entry is only ever overwritten by another
    // sprite pixel at the same address, so a pixel written at (line L, x)
    // still carried a matching tag at (line L, x) in the NEXT frame and read
    // as a live sprite pixel until something happened to overwrite it.
    //
    // The parity alone is NOT enough -- it only tells adjacent frames apart,
    // so a pixel untouched for two frames comes back (sim/Makefile
    // `spr-ghost` failed exactly that way with the parity and no clear). The
    // buffer is therefore CLEARED per line, in D_CLR below, which is what
    // the real chip's framebuffer does (the model clears it every frame;
    // "sprite trails" is the F3 feature for not clearing, and Ray Force
    // never sets it). The tag then costs nothing and still guards the window
    // where the draw has not reached a line the mixer asks for.
    //
    // The clear is a SPAN, not the whole 320: each bank remembers the
    // leftmost and rightmost pixel its last occupant wrote, and only that
    // range is cleared before the next line uses it. Every pixel any
    // occupant wrote is therefore cleared before the next one draws, which
    // is the whole requirement -- and a flat 320-pixel clear was far too
    // expensive: it pushed the longest line from 3288 to 3608 clocks and
    // made 254 of 256 lines late in `pipe-lat` (the pathological frame at
    // hardware-like SDRAM latency). The span costs nothing on the empty and
    // near-empty lines that most of a frame is made of.
    //
    // It costs no memory: line[7:NBW] is 6 bits for NB = 4, so the tag is
    // still 7 bits and an entry still 20, i.e. NB x 512 x 20 bits = NB/2
    // M10Ks (2 banks were three M10Ks at 21 bits).
    // NB = 16, was 8, was 4. The draw has to bank slack across quiet lines:
    // the budget is 3456 clocks a line and the board's worst line needs
    // ~16000, so what matters is how many lines of slack the ring holds --
    // NB x 3456 in total.
    //
    //   NB=4   13824 clocks   under the worst single line; late lines came
    //                         in bursts (0 -> 4770 -> 6820) as scenes got busy
    //   NB=8   27648          covers any ONE line (the worst is 57 % of it),
    //                         but not a RUN of heavy lines -- which is what
    //                         a boss fight is, and the board still glitched
    //                         there with late lines saturating at 65535
    //   NB=16  55296          two full bosses' worth of run
    //
    // The cost is memory, not logic: the line buffer is NB x 512 x 20 bits,
    // so 8 -> 16 banks is +8 M10K against 12 free (541/553 in build
    // 29224005). The tag stays inside the 20-bit word -- it is
    // {par, line[7:NBW]}, and a wider NBW makes it SHORTER, 5 bits at NB=16.
    localparam int NB  = 16;
    localparam int NBW = $clog2(NB);

    logic            wr_en;
    logic [NBW+8:0]  wr_addr;
    logic [19:0]     wr_data, lb_q;

    rf_bram #(.WIDTH(20), .AW(NBW + 9)) u_lbuf (
        .clk(clk),
        .waddr(wr_addr), .wdata(wr_data), .wren(wr_en),
        .raddr({rd_line[NBW-1:0], rd_x}), .q(lb_q)
    );
    // the parity of the frame being drawn; the mixer reads the line the draw
    // wrote in this same frame (the draw runs ahead of it, never behind), and
    // the only window where the two disagree -- frame_start to the mixer's
    // line 0, raster 260-261 -- has no mixing in it
    logic par;
    wire [6:0] rd_tag = {par, rd_line[7:NBW]};
    assign rd_color = (lb_q[19:13] == rd_tag) ? {3'd0, lb_q[12:0]} : 16'd0;

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
        P_C0, P_CROW, P_CRD, P_CWR, P_CEND,   // pass 1: count records per line
        P_SRD, P_SWR,                         // prefix sum -> runs
        P_E0, P_EROW, P_ERD, P_EWR, P_EEND    // pass 2: place records
    } pst_t;
    pst_t pst;
    assign prepass_busy = (pst != P_IDLE);
    assign fetch_max     = f_max_q;
    assign rows_line_max = rows_line_pk_q;

    // One row of the walk, shared by both passes so they cannot disagree
    // about where a run starts and ends (pass 1 counts what pass 2 places).
    // A row in range on the open run's line extends it; any other row
    // closes the open run into e_* (RDST emits it) and, if in range, opens
    // a new one. The row is advanced here either way; the emit states use
    // e_* only, and come back to ROWST for the next row or ENDST after the
    // last. Every next state is written out explicitly (a "stay" that
    // landed in the wrong state was the bug the spr-line bench caught in
    // the linked-list version).
    `define RUN_STEP(ROWST, RDST, ENDST) \
        begin \
            if (ex_inr && r_open && ex_dyb == r_dy) begin \
                r_b <= ex_srow; \
                pst <= (ex_yy == 5'd0) ? ENDST : ROWST; \
            end else begin \
                e_dy <= r_dy; e_a <= r_a; e_b <= r_b; \
                r_open <= ex_inr; r_dy <= ex_dyb; r_a <= ex_srow; r_b <= ex_srow; \
                ret_end <= (ex_yy == 5'd0); \
                pst <= r_open ? RDST : (ex_yy == 5'd0) ? ENDST : ROWST; \
            end \
            if (ex_yy != 5'd0) begin \
                ex_dy8 <= ex_dy8 - $signed({16'd0, ex_sy}); \
                ex_yy  <= ex_yy - 5'd1; \
            end \
        end
    // the sprite's last row has been walked: emit the run still open, then
    // move to the next sprite
    `define RUN_END(RDST, SPRST) \
        begin \
            if (r_open) begin \
                e_dy <= r_dy; e_a <= r_a; e_b <= r_b; \
                r_open <= 1'b0; ret_end <= 1'b1; \
                pst <= RDST; \
            end else begin \
                ex_i <= ex_i + 11'd1; \
                pst  <= SPRST; \
            end \
        end
    // load sprite ex_i's expand state (its 16 rows walked 15 -> 0)
    `define SPR_LOAD_EX \
        begin ex_sy <= sly_sy; ex_fy <= sly_fy; ex_yy <= 5'd15; r_open <= 1'b0; \
              ex_dy8 <= $signed(sly_ty) + (flip_r ? 25'sd0 : 25'sd255) \
                      + $signed({16'd0, ({sly_sy, 4'd0} - {4'd0, sly_sy})}); end

    always_ff @(posedge clk) begin
        wk_start <= 1'b0;
        bt_we    <= 1'b0;
        if (reset) begin
            pst <= P_IDLE;
            wb  <= 1'b0; rb <= 1'b1;
            nspr <= 11'd0;
            flip_r <= 1'b0; penmask_r <= 5'h0F;
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
                    sl_d[wb][nspr] <= {s_tx, s_sx, s_code[14:0], s_color, s_fx};
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

            // ---- pass 1: count records per line
            P_C0: begin
                if (ex_i >= nspr) begin
                    sum_y   <= 8'd0;
                    sum_acc <= '0;
                    pst     <= P_SRD;
                end else begin
                    `SPR_LOAD_EX
                    pst <= P_CROW;
                end
            end
            P_CROW: `RUN_STEP(P_CROW, P_CRD, P_CEND)
            P_CRD: begin
                c_rd <= cnt[e_dy];
                pst  <= P_CWR;
            end
            P_CWR: begin
                cnt[e_dy] <= c_rd + 1'b1;
                if (rows_tot != 16'hFFFF) rows_tot <= rows_tot + 16'd1;
                pst <= ret_end ? P_CEND : P_CROW;
            end
            P_CEND: `RUN_END(P_CRD, P_C0)

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

            // ---- pass 2: place records
            P_E0: begin
                if (ex_i >= nspr) begin
                    // what the frame asked for and what was refused, for
                    // the self-test page: refused records come off the END
                    // of the run order, i.e. the sprites drawn on top
                    rec_peak <= rows_tot;
                    rec_drop <= drop_cnt;
                    pst <= P_IDLE;
                end else begin
                    `SPR_LOAD_EX
                    pst <= P_EROW;
                end
            end
            P_EROW: `RUN_STEP(P_EROW, P_ERD, P_EEND)
            P_ERD: begin
                f_rd <= cnt[e_dy];
                l_rd <= lim[e_dy];
                pst  <= P_EWR;
            end
            P_EWR: begin
                if (f_rd != l_rd) begin
                    rec[wb][f_rd] <= {ex_i[9:0], e_a, e_b};
                    cnt[e_dy]     <= f_rd + 1'b1;
                end else if (drop_cnt != 16'hFFFF) begin
                    drop_cnt <= drop_cnt + 16'd1;
                end
                pst <= ret_end ? P_EEND : P_EROW;
            end
            P_EEND: `RUN_END(P_ERD, P_E0)

            default: pst <= P_IDLE;
        endcase
    end
    `undef RUN_STEP
    `undef RUN_END
    `undef SPR_LOAD_EX

    // ================= DRAW FSM (reads bank rb) =================
    // Issue: whenever the next record's lookup has settled and the issue
    // slot is free, start its fetch and advance fc. Promote: when the
    // current record is drawn (or there is none), take the consume slot as
    // soon as its pixels are in. Done: nothing drawing, nothing in flight,
    // no records left.
    typedef enum logic [2:0] { D_IDLE, D_CLR, D_LEAD0, D_RUN, D_DONE } dst_t;
    dst_t dst;
    assign line_busy = (dst != D_IDLE && dst != D_DONE);
    // the clear span: what the bank's last occupant wrote, and what this
    // line is writing (lo > hi means nothing)
    logic [8:0] clr_x, clr_hi;
    logic [8:0] span_lo [0:NB-1];
    logic [8:0] span_hi [0:NB-1];
    logic [8:0] cur_lo, cur_hi;

    // ---- fetch/density diagnostics (see the ports) ----------------------
    // f_cnt runs while a bus has a fetch outstanding and is banked at the
    // fall; rows_line counts the rows ISSUED on the line being drawn. Both
    // peaks are per frame and are published at frame_start, which is the
    // only moment the draw is guaranteed idle.
    logic [15:0] f_cnt   [0:1];
    logic [15:0] f_max, f_max_q;
    logic [15:0] rows_line, rows_line_pk, rows_line_pk_q;
    logic  [1:0] gfx_busy_d;

    always_ff @(posedge clk) begin
        gfx_req <= 2'b00;
        wr_en   <= 1'b0;
        fc_ok   <= 1'b1;                 // cleared below whenever fc changes

        // capture completions (bus i serves slot i)
        if (gfx_valid[0] && q_busy[0]) begin q_pix[0] <= gfx_pix[0]; q_ready[0] <= 1'b1; end
        if (gfx_valid[1] && q_busy[1]) begin q_pix[1] <= gfx_pix[1]; q_ready[1] <= 1'b1; end

        // longest single fetch: count while a bus is busy, bank it at the fall
        gfx_busy_d <= gfx_busy;
        for (int b = 0; b < 2; b++) begin
            if (gfx_busy[b]) f_cnt[b] <= f_cnt[b] + 16'd1;
            else             f_cnt[b] <= 16'd0;
            if (gfx_busy_d[b] && !gfx_busy[b] && f_cnt[b] > f_max) f_max <= f_cnt[b];
        end

        if (reset) begin
            dst <= D_IDLE; q_busy <= 2'b00; q_ready <= 2'b00; cur <= 1'b0;
            active <= 1'b0; nxt <= 9'd0; par <= 1'b0; ir_open <= 1'b0;
            f_cnt[0] <= 0; f_cnt[1] <= 0; f_max <= 0; f_max_q <= 0;
            rows_line <= 0; rows_line_pk <= 0; rows_line_pk_q <= 0;
            gfx_busy_d <= 2'b00;
            for (int b = 0; b < NB; b++) begin
                span_lo[b] <= 9'd511; span_hi[b] <= 9'd0;      // empty
            end
        end else if (frame_start) begin
            par <= ~par;                // every entry of the frame just drawn
                                        // now reads as empty
            // the buckets just swapped: restart at line 0. In normal running
            // the draw finished line 255 long ago; a fetch still in flight
            // (a frame_start mid-line, e.g. the bench's priming pass) is
            // simply not captured -- q_busy is cleared -- and the bus stays
            // busy until it lands, which the issue rule waits for.
            dst <= D_IDLE; q_busy <= 2'b00; q_ready <= 2'b00; cur <= 1'b0;
            active <= 1'b1; nxt <= 9'd0; ir_open <= 1'b0;
            // publish last frame's peaks and start fresh
            f_max_q        <= f_max;        f_max        <= 16'd0;
            rows_line_pk_q <= rows_line_pk; rows_line_pk <= 16'd0;
            rows_line      <= 16'd0;
        end else case (dst)
            D_IDLE: if (can_draw) begin
                dr_line <= nxt[7:0];
                dr_used <= 4'd0;
                q_busy  <= 2'b00; q_ready <= 2'b00;
                q_is    <= 1'b0;  q_cs    <= 1'b0;
                cur     <= 1'b0;
                clr_x   <= span_lo[nxt[NBW-1:0]];
                clr_hi  <= span_hi[nxt[NBW-1:0]];
                cur_lo  <= 9'd511; cur_hi <= 9'd0;             // this line: empty
                if (rows_line > rows_line_pk) rows_line_pk <= rows_line;
                rows_line <= 16'd0;
                dst <= (span_lo[nxt[NBW-1:0]] > span_hi[nxt[NBW-1:0]]) ? D_LEAD0 : D_CLR;
            end

            // Clear this line's bank: 320 writes, ~9 % of the frame's clocks
            // and the reason a sprite goes away when it stops being drawn.
            // The run table's answer for {rb, nxt} is presented from D_IDLE
            // and nxt does not move until D_DONE, so bt_q is still valid at
            // the end of this.
            D_CLR: begin
                wr_en   <= 1'b1;
                wr_addr <= {dr_line[NBW-1:0], clr_x};
                wr_data <= 20'd0;
                clr_x   <= clr_x + 9'd1;
                if (clr_x >= clr_hi) dst <= D_LEAD0;
            end

            // the run table answers for {rb, nxt} (presented during D_IDLE)
            D_LEAD0: begin
                if (bt_q[RW-1:0] == bt_q[2*RW-1:RW]) begin
                    used_bank[dr_line[NBW-1:0]] <= dr_used;     // empty line
                    span_lo[dr_line[NBW-1:0]] <= cur_lo;        // nothing written
                    span_hi[dr_line[NBW-1:0]] <= cur_hi;
                    dst <= D_DONE;
                end else begin
                    fc    <= bt_q[RW-1:0];
                    fe    <= bt_q[2*RW-1:RW];
                    fc_ok <= 1'b0;
                    ir_open <= 1'b0;
                    dst   <= D_RUN;
                end
            end

            D_RUN: begin
                // ---- issue the next row of the record at fc into the free
                // slot; fc advances on the run's last row only
                if (fc != fe && fc_ok && !q_busy[q_is] && !gfx_busy[q_is]) begin
                    gfx_code[q_is] <= sd_code;
                    gfx_row[q_is]  <= is_row;
                    gfx_req[q_is]  <= 1'b1;
                    q_busy[q_is]   <= 1'b1;
                    q_ready[q_is]  <= 1'b0;
                    q_x8[q_is]     <= sd_x8;
                    q_sx[q_is]     <= sd_sx;
                    q_col[q_is]    <= sd_col;
                    q_fx[q_is]     <= sd_fx;
                    if (is_row == rc_b) begin
                        fc      <= fc + 1'b1;
                        fc_ok   <= 1'b0;
                        ir_open <= 1'b0;
                    end else begin
                        ir_open <= 1'b1;
                        ir_row  <= is_next;
                    end
                    q_is  <= ~q_is;
                    rows_line <= rows_line + 16'd1;
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
                        // an all-transparent row writes nothing, so take the
                        // next record instead of spending 17 cycles on it
                        cur  <= q_any;
                    end else if (!q_busy[q_cs] && fc == fe) begin
                        used_bank[dr_line[NBW-1:0]] <= dr_used;
                        span_lo[dr_line[NBW-1:0]] <= cur_lo;
                        span_hi[dr_line[NBW-1:0]] <= cur_hi;
                        dst <= D_DONE;
                    end
                    // else wait for the oldest fetch to land
                end else begin
                    if (dr_vis && dr_pen != 5'd0) begin
                        wr_en   <= 1'b1;
                        wr_addr <= {dr_line[NBW-1:0], dr_ix};
                        wr_data <= {par, dr_line[7:NBW], dr_base | {8'd0, dr_pen}};
                        dr_used <= dr_used | (4'd1 << dr_pri);
                        if (dr_ix < cur_lo) cur_lo <= dr_ix;
                        if (dr_ix > cur_hi) cur_hi <= dr_ix;
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
