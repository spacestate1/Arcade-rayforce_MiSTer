//============================================================================
//  Line RAM decode -- the F3's per-scanline effect engine.
//
//  Every one of the 256 scanlines can independently set scroll, row scroll,
//  column scroll, zoom, clipping, blending, palette offset and layer priority
//  for four playfields, four sprite priority groups and the pivot layer. All
//  of that lives in 64 KB of line RAM, reached through two levels of
//  indirection, and it is most of what taito_f3_v.cpp does.
//
//  This is a direct port of read_line_ram() from tools/f3_render.py, which
//  reproduces MAME's own frames pixel-exact and is therefore the spec. The
//  bench (sim/line_tb.cpp) diffs this module's output against that model for
//  all 256 lines of a dumped frame, so "it looks about right" never enters
//  into it.
//
//  Addressing. For section s (0-7) and subsection u (0-3):
//
//      latches = line_ram[s*0x100 + y]           <- the "line set" word
//      base    = 0x2000 + 0x800*s + 0x100*u      <- in 16-bit words
//      if latches bit (u+4) : read base + 0x400 + y     (alternate bank)
//      elif latches bit u   : read base + y
//      else                 : no update this line
//
//  "No update" is the important half: a value not re-latched on this line
//  KEEPS the value from the previous line. Games rely on that to set a zoom
//  or a scroll once and have it apply to a whole playfield, so the register
//  set persists across lines and is cleared only at the start of a frame.
//
//  With flipscreen -- which Ray Force uses, its graphics being stored flipped
//  in ROM -- the caller walks y from 255 down to 0 as the raster goes down the
//  screen, so latching propagates in the opposite direction. That is the
//  caller's business; this module just decodes the y it is given.
//============================================================================

module rf_video_line
(
    input  logic        clk,
    input  logic        reset,

    input  logic        frame_start,   // clears the latched register set
    input  logic        line_start,    // decode one line
    input  logic  [7:0] y,             // line RAM index (NOT the screen line)
    input  logic        extend,        // control_1[7] bit 7: 1024x512 playfields
    output logic        busy,

    // line RAM read port (B side of the CPU's line RAM)
    output logic [14:0] lr_addr,
    input  logic [15:0] lr_q,

    // ---- decoded per-line state -----------------------------------------
    // clip planes: 9-bit left/right edges, upper bit from section 0
    output logic [3:0][8:0] clip_l,
    output logic [3:0][8:0] clip_r,
    // blending contributions, 0-8 (see 0x6200)
    output logic [3:0][3:0] blend,
    output logic      [4:0] x_sample,      // mosaic: 16 = off
    output logic      [7:0] fx_6400,
    output logic     [15:0] bg_palette,

    // pivot / text layer
    output logic      [7:0] pivot_control,
    output logic            pivot_bsel,
    output logic     [15:0] pivot_enable,
    output logic     [15:0] pivot_mix,
    output logic            pivot_mosaic,

    // sprite priority groups
    output logic [3:0][15:0] sp_mix,
    output logic       [3:0] sp_bsel,
    output logic             sp_mosaic,

    // playfields
    output logic [3:0][8:0]  pf_colscroll,
    output logic [3:0]       pf_alt_tilemap,
    output logic [3:0][8:0]  pf_x_scale,     // 256 - zoom
    output logic [3:0][8:0]  pf_y_scale,
    output logic [3:0][15:0] pf_pal_add,
    output logic [3:0][19:0] pf_rowscroll,   // signed 24.8, see below
    output logic [3:0][15:0] pf_mix,
    output logic [3:0]       pf_mosaic
);

    // FIX_Y: the y zooms of playfields 2 and 4 are stored where you would
    // expect the other's to be (taito_f3_v.cpp says so, and the model agrees).
    function automatic logic [1:0] fix_y(input logic [1:0] i);
        case (i)
            2'd0: fix_y = 2'd0;
            2'd1: fix_y = 2'd3;
            2'd2: fix_y = 2'd2;
            default: fix_y = 2'd1;
        endcase
    endfunction

    // The line RAM port registers its address and leaves the output
    // unregistered, so data for an address presented in cycle N is valid in
    // N+1. Each read therefore needs an explicit wait state between setting
    // the address and consuming it -- without it every value read here is the
    // PREVIOUS address's, which decodes into a plausible-looking page of
    // wrong numbers rather than an obvious failure.
    typedef enum logic [2:0] {
        S_IDLE, S_LATCH_A, S_LATCH_W, S_LATCH_D, S_DATA_A, S_DATA_W, S_DATA_D, S_NEXT
    } st_t;
    st_t st;

    logic [2:0] sec;
    logic [1:0] sub;
    logic [15:0] latches;
    logic [14:0] data_addr;
    logic        have_data;

    // base word address of section/subsection, before the y offset
    wire [14:0] sub_base = 15'h2000 + {sec, 11'd0} + {sub, 8'd0};
    wire        alt_hit  = latches[{1'b0, sub} + 3'd4];
    wire        nrm_hit  = latches[sub];
    wire [14:0] want     = alt_hit ? (sub_base + 15'h400 + {7'd0, y})
                                   : (sub_base + {7'd0, y});

    assign busy = (st != S_IDLE);

    // rowscroll is 10.6 with a NEGATIVE fractional part: the model computes
    // (v<<2 & ~0xff) - (v<<2 & 0xff), which is not a shift and not a sign
    // extension. Written out so it cannot be "simplified" into either.
    wire [17:0] rs_raw  = {lr_q, 2'b00};
    wire [19:0] rs_val  = {2'b00, rs_raw[17:8], 8'd0} - {12'd0, rs_raw[7:0]};

    integer i;

    always_ff @(posedge clk) begin
        if (reset || frame_start) begin
            st <= S_IDLE;
            clip_l <= '0; clip_r <= '0; blend <= '0;
            x_sample <= 5'd16; fx_6400 <= '0; bg_palette <= '0;
            pivot_control <= '0; pivot_bsel <= 1'b0; pivot_enable <= '0;
            pivot_mix <= '0; pivot_mosaic <= 1'b0;
            sp_mix <= '0; sp_bsel <= '0; sp_mosaic <= 1'b0;
            pf_colscroll <= '0; pf_alt_tilemap <= '0;
            pf_pal_add <= '0; pf_rowscroll <= '0; pf_mix <= '0; pf_mosaic <= '0;
            for (i = 0; i < 4; i = i + 1) begin
                pf_x_scale[i] <= 9'd128;   // model default 0x80
                pf_y_scale[i] <= 9'd0;
            end
        end else begin
            case (st)
                S_IDLE: if (line_start) begin
                    sec <= 3'd0;
                    sub <= 2'd0;
                    lr_addr <= {7'd0, y};        // section 0 latch word
                    st  <= S_LATCH_W;
                end

                // the latch word for this section: line_ram[sec*0x100 + y]
                S_LATCH_A: begin
                    lr_addr <= {4'd0, sec, 8'd0} + {7'd0, y};
                    st      <= S_LATCH_W;
                end
                S_LATCH_W: st <= S_LATCH_D;
                S_LATCH_D: begin
                    latches <= lr_q;
                    sub     <= 2'd0;
                    st      <= S_DATA_A;
                end

                // A subsection nobody latched has nothing to read: skip the
                // three-cycle access. Measured on Ray Force (which latches
                // most subsections on most lines) this takes the mean from
                // 151 to 112 clocks a line; worst case stays 151 when all 32
                // are latched. Either way it is ~3-4% of the 3456 available.
                S_DATA_A: begin
                    have_data <= alt_hit | nrm_hit;
                    lr_addr   <= want;
                    st        <= (alt_hit | nrm_hit) ? S_DATA_W : S_NEXT;
                end
                S_DATA_W: st <= S_DATA_D;

                S_DATA_D: begin
                    if (have_data) begin
                        case (sec)
                        // ---- 4000: column scroll (pf 3/4) + clip high bits
                        3'd0: if (sub[1]) begin          // subsections 2 and 3
                            pf_colscroll[sub]   <= lr_q[8:0];
                            pf_alt_tilemap[sub] <= ~extend & lr_q[9];
                            clip_l[{sub[0], 1'b0}][8] <= lr_q[12];
                            clip_r[{sub[0], 1'b0}][8] <= lr_q[13];
                            clip_l[{sub[0], 1'b1}][8] <= lr_q[14];
                            clip_r[{sub[0], 1'b1}][8] <= lr_q[15];
                        end
                        // ---- 5000: clip plane low bits
                        3'd1: begin
                            clip_l[sub][7:0] <= lr_q[7:0];
                            clip_r[sub][7:0] <= lr_q[15:8];
                        end
                        // ---- 6000
                        3'd2: case (sub)
                            2'd0: begin
                                pivot_bsel    <= lr_q[9];
                                pivot_control <= lr_q[15:8];
                                for (i = 0; i < 4; i = i + 1)
                                    sp_mix[i][15:14] <= lr_q[2*i +: 2];
                            end
                            2'd1: for (i = 0; i < 4; i = i + 1)
                                // min(8, 0xF - alpha)
                                blend[i] <= (lr_q[4*i +: 4] < 4'd7)
                                            ? 4'd8 : (4'd15 - lr_q[4*i +: 4]);
                            2'd2: begin
                                x_sample <= 5'd16 - {1'b0, lr_q[7:4]};
                                for (i = 0; i < 4; i = i + 1)
                                    pf_mosaic[i] <= lr_q[i];
                                sp_mosaic    <= lr_q[8];
                                pivot_mosaic <= lr_q[9];
                                fx_6400      <= {lr_q[15:10], 2'b00};
                            end
                            default: bg_palette <= lr_q;
                        endcase
                        // ---- 7000
                        3'd3: case (sub)
                            2'd0: pivot_enable <= lr_q;
                            2'd1: pivot_mix    <= lr_q;
                            2'd2: for (i = 0; i < 4; i = i + 1) begin
                                sp_mix[i][13:4] <= lr_q[9:0];
                                sp_bsel[i]      <= lr_q[12 + i];
                            end
                            default: for (i = 0; i < 4; i = i + 1)
                                sp_mix[i][3:0] <= lr_q[4*i +: 4];
                        endcase
                        // ---- 8000: zoom, y zooms interleaved
                        3'd4: begin
                            pf_x_scale[sub]         <= 9'd256 - {1'b0, lr_q[15:8]};
                            pf_y_scale[fix_y(sub)]  <= {lr_q[7:0], 1'b0};
                        end
                        // ---- 9000: palette add
                        3'd5: pf_pal_add[sub] <= {lr_q[11:0], 4'd0};
                        // ---- a000: row scroll
                        3'd6: pf_rowscroll[sub] <= rs_val;
                        // ---- b000: playfield mixing info
                        default: pf_mix[sub] <= lr_q;
                        endcase
                    end
                    st <= S_NEXT;
                end

                S_NEXT: begin
                    if (sub == 2'd3) begin
                        if (sec == 3'd7) st <= S_IDLE;
                        else begin
                            sec <= sec + 3'd1;
                            st  <= S_LATCH_A;
                        end
                    end else begin
                        sub <= sub + 2'd1;
                        st  <= S_DATA_A;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
