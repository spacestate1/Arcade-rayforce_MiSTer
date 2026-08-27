//============================================================================
//  Ray Force / Gunlock (Taito F3) for MiSTer
//
//  Phase 0 proved the plumbing (MRA -> HPS -> ioctl download, F3 raster
//  timing, TG68K.C in 020 mode running the real boot ROM). Phase 1 put the
//  ROM in SDRAM behind rf_prog_bus and closed timing. Phase 2 starts here.
//
//  What this build is: the real F3 main board (rf_main.sv) -- the full
//  taito_f3.cpp memory map with every video RAM present, the vblank and
//  timer interrupts delivered, inputs and EEPROM wired -- driving a
//  diagnostic page instead of a renderer.
//
//  Why that order: with the spike's fake map the boot code ran to its vblank
//  wait at ~0x4060 and stopped, so no video RAM ever held real data. Nothing
//  in the pixel pipeline can be developed, let alone diffed against MAME,
//  until the program is actually running its frame loop. The acceptance test
//  for THIS build is therefore not a picture of the game, it is:
//
//    - download 0x00B80000 bytes, checksum 0x77E1C279, 1 MB BIST 0xD53D7C04
//    - write hash still 0x10620931 (the map got bigger; the first 4096
//      writes are boot clear loops and must not have changed)
//    - frame counter advancing at ~59 Hz, irq2 acknowledges tracking it
//    - playfield / sprite / palette write counters climbing, i.e. the game
//      is drawing
//    - the palette dump showing the game's real colours
//============================================================================

module emu
(
    input         CLK_50M,
    input         RESET,
    inout  [48:0] HPS_BUS,
    output        CLK_VIDEO,
    output        CE_PIXEL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,
    output        VGA_F1,
    output [1:0]  VGA_SL,
    output        VGA_SCALER,
    output        VGA_DISABLE,

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,
    output        HDMI_BLACKOUT,
    output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
    output        FB_EN,
    output  [4:0] FB_FORMAT,
    output [11:0] FB_WIDTH,
    output [11:0] FB_HEIGHT,
    output [31:0] FB_BASE,
    output [13:0] FB_STRIDE,
    input         FB_VBL,
    input         FB_LL,
    output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
    output        FB_PAL_CLK,
    output  [7:0] FB_PAL_ADDR,
    output [23:0] FB_PAL_DOUT,
    input  [23:0] FB_PAL_DIN,
    output        FB_PAL_WR,
`endif
`endif

    output        LED_USER,
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,
    output  [1:0] BUTTONS,

    input         CLK_AUDIO,
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output  [1:0] AUDIO_MIX,

    inout   [3:0] ADC_BUS,

    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    output        DDRAM_CLK,
    input         DDRAM_BUSY,
    output  [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output  [7:0] DDRAM_BE,
    output        DDRAM_WE,

    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
    input         SDRAM2_EN,
    output        SDRAM2_CLK,
    output [12:0] SDRAM2_A,
    output  [1:0] SDRAM2_BA,
    inout  [15:0] SDRAM2_DQ,
    output        SDRAM2_nCS,
    output        SDRAM2_nCAS,
    output        SDRAM2_nRAS,
    output        SDRAM2_nWE,
`endif

    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    input   [6:0] USER_IN,
    output  [6:0] USER_OUT,

    input         OSD_STATUS
);

///////// Outputs this skeleton does not drive /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;
// UART_TXD is driven further down: it carries either the self-test page
// (rf_uart_log) or the write-ring dump (rf_uart_dump), selected in the OSD.
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

`ifdef MISTER_DUAL_SDRAM
assign {SDRAM2_A, SDRAM2_BA, SDRAM2_DQ, SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE, SDRAM2_CLK} = 'Z;
`endif

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_RD, DDRAM_DIN, DDRAM_BE, DDRAM_WE} = 0;

`ifdef MISTER_FB
assign FB_EN = 0;
assign {FB_FORMAT, FB_WIDTH, FB_HEIGHT, FB_BASE, FB_STRIDE, FB_FORCE_BLANK} = 0;
`ifdef MISTER_FB_PALETTE
assign {FB_PAL_CLK, FB_PAL_ADDR, FB_PAL_DOUT, FB_PAL_WR} = 0;
`endif
`endif

assign VGA_F1         = 0;
assign VGA_SCALER     = 0;
assign VGA_DISABLE    = 0;
assign HDMI_FREEZE    = 0;
assign HDMI_BLACKOUT  = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_L   = 0;
assign AUDIO_R   = 0;
assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

// Native picture is 320x224; the cabinet is vertical (ROT90) but the
// skeleton's diagnostic page is horizontal text, so no rotation yet.
assign VIDEO_ARX = 13'd4;
assign VIDEO_ARY = 13'd3;

//////////////////////////   HPS   ///////////////////////////////

`include "build_id.v"
// ddhhmmss of this compile -- see tools/make_build_stamp.sh. build_id.v is
// regenerated by the MiSTer build flow, so the stamp cannot live there.
`include "rf_build_stamp.vh"

// Button order in the J1 list is the MiSTer arcade convention: buttons start
// at joystick bit 4 and every core places Start at bit 10 and Coin at bit 11,
// which is what the placeholder dashes are for (raiden2 note, same layout).
localparam CONF_STR = {
    "Rayforce;;",
    "-;",
    "O[2],Service Mode,Off,On;",
    "O[3],Self Test,On,Off;",
    "O[5:4],UART Debug,Self Test,Off,Write Ring;",
    "-;",
    "R[0],Reset;",
    "J1,Shot,Laser,-,-,-,-,Start,Coin,Service,Pause;",
    "V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

wire [31:0] joystick_0;
wire [31:0] joystick_1;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .EXT_BUS(),
    .gamma_bus(gamma_bus),

    .forced_scandoubler(forced_scandoubler),
    .buttons(buttons),
    .status(status),
    .status_menumask(0),

    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_index(ioctl_index),
    .ioctl_wait(ioctl_wait),

    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .ps2_key()
);

///////////////////////   CLOCKS   ///////////////////////////////
//
// clk_sys = 53.372 MHz = 8 x the F3 pixel clock (26.686 MHz XTAL / 4).
// clk_ram = 97.04 MHz for the SDRAM controller: both outputs are exact off
// one 1067.44 MHz fractional VCO (C=11 and C=20), so clk_sys -- and the
// 58.94 Hz video timing derived from it -- is untouched by adding clk_ram.

wire clk_ram, clk_sys, pll_locked;

pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_ram),
    .outclk_1(clk_sys),
    .locked(pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

// sys_top holds RESET high for the WHOLE ROM download, so anything that must
// work during or right after the stream (the program bus) resets on
// bus_reset instead -- gating it on `reset` froze it mid-stream on
// Propcycle.
wire bus_reset = status[0] | buttons[1] | ~pll_locked;

// Debug options and the two UART producers are declared HERE, above every
// use: a forward reference at module scope becomes an implicit 1-bit net,
// which would silently truncate uart_mode to one bit and gate the wrong
// producer (the failure class the Raiden II core hit twice).
//   O[3]   Self Test    0 = show the page (default), 1 = show game video
//   O[5:4] UART Debug   0 = self-test page (default), 1 = off, 2 = the
//                       Phase 0/1 write-ring dump (rf_write_compare.py).
//                       On by default: the OSD cannot be driven remotely, and
//                       a debug channel that has to be switched on by hand at
//                       the cabinet is not much of a debug channel.
wire       selftest_on = ~status[3];
wire [1:0] uart_mode   = status[5:4];
wire       uart_log_txd, uart_ring_txd;

//////////////////////  ROM DOWNLOAD PROOF  //////////////////////
//
// Counts and checksums the ioctl stream exactly as received. The MRA for
// gunlock/rayforce streams 0x00B80000 bytes (11.5 MB); the rolling sum is
// the same rotate-left-1-then-add the Raiden BIST uses, so the value can be
// reproduced offline from the same zip to prove the bytes arrived intact.

reg [31:0] dl_bytes;
reg [31:0] dl_sum;
reg  [7:0] dl_index;
reg        dl_seen;

always @(posedge clk_sys) begin
    if (ioctl_wr && ioctl_index == 8'd0) begin
        // First write of a fresh download resets the accumulators, so a
        // second load does not stack on the first.
        if (ioctl_addr == 0) begin
            dl_bytes <= 32'd2;
            dl_sum   <= {16'd0, ioctl_dout};
        end else begin
            dl_bytes <= dl_bytes + 32'd2;
            dl_sum   <= {dl_sum[30:0], dl_sum[31]} + {16'd0, ioctl_dout};
        end
        dl_seen <= 1'b1;
    end
    if (ioctl_wr) dl_index <= ioctl_index;
end

///////////////////////   SDRAM   ////////////////////////////////
//
// Sorgelig 4-channel controller at clk_ram. Only ch3 is in use: the
// download loader owns it while ioctl_download is high, the CPU's
// line-cached program fetches (rf_prog_bus) own it afterwards. ch1/ch2/ch4
// are parked for the video/sound phases.

wire [26:1] ch3_addr_pb;                // prog_bus side of the loader mux
wire [63:0] ch3_dout;
wire [15:0] ch3_din_pb;
wire  [1:0] ch3_be_pb;
wire        ch3_req_pb, ch3_rnw_pb, ch3_ready;

// Direct download loader: the FIFO path inside pc_prog_bus dispatched ZERO
// writes during real downloads on Propcycle (mechanism unproven), so the
// proven shape is a dedicated FSM owning ch3 while ioctl_download is high --
// one SDRAM write per ioctl word, ioctl_wait held until the ram-domain done
// toggle comes back. The whole MRA stream is written flat (stream order IS
// the SDRAM map); maincpu words are byte-swapped LE->BE so the 68020 bus
// reads {even, odd}, everything else is stored raw.
reg         ld_req;
reg  [26:1] ld_addr;
reg  [15:0] ld_din;
reg         ld_busy;
/* verilator lint_off PROCASSINIT */
reg         ld_done_t = 1'b0;
/* verilator lint_on PROCASSINIT */
always @(posedge clk_ram) if (ch3_ready && ioctl_download) ld_done_t <= ~ld_done_t;
reg ld_d1, ld_d2, ld_d3;
always @(posedge clk_sys) begin
    ld_d1 <= ld_done_t; ld_d2 <= ld_d1; ld_d3 <= ld_d2;
end
wire ld_done_edge = ld_d2 ^ ld_d3;

wire dl_word = ioctl_wr && ioctl_index == 8'd0;

always @(posedge clk_sys) begin
    if (~pll_locked) begin
        ld_req <= 1'b0; ld_busy <= 1'b0;
    end else begin
        if (dl_word && !ld_busy) begin
            ld_addr <= ioctl_addr[26:1];
            ld_din  <= (ioctl_addr < 27'h100000)
                       ? {ioctl_dout[7:0], ioctl_dout[15:8]}   // LE -> BE
                       : ioctl_dout;
            ld_req  <= 1'b1;
            ld_busy <= 1'b1;
        end else if (ld_busy && ld_done_edge) begin
            ld_req  <= 1'b0;
            ld_busy <= 1'b0;
        end
    end
end

assign ioctl_wait = ld_busy;

sdram sdram
(
    .init(~pll_locked), .clk(clk_ram), .doRefresh(1'b0),
    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A),
    .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
    .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
    .ch1_addr(26'd0), .ch1_dout(), .ch1_req(1'b0), .ch1_ready(),
    .ch2_addr(26'd0), .ch2_dout(), .ch2_req(1'b0), .ch2_ready(),
    .ch3_addr(ioctl_download ? ld_addr : ch3_addr_pb),
    .ch3_dout(ch3_dout),
    .ch3_din(ioctl_download ? ld_din : ch3_din_pb),
    .ch3_be(ioctl_download ? 2'b11 : ch3_be_pb),
    .ch3_req(ioctl_download ? ld_req : ch3_req_pb),
    .ch3_rnw(ioctl_download ? 1'b0 : ch3_rnw_pb),
    .ch3_ready(ch3_ready),
    .ch4_addr(26'd0), .ch4_dout(), .ch4_req(1'b0), .ch4_ready()
);

////////////////////  PROGRAM BUS + READBACK BIST  ///////////////
//
// rf_prog_bus gives the CPU line-cached 16-bit reads of the program ROM in
// SDRAM. Its internal download FIFO is the one Propcycle found dead during
// real streams, so it is bypassed (dl_wr tied off) and the loader above
// does all SDRAM writes.
//
// Readback BIST: after the download, read the FULL 1 MB maincpu region back
// through the REAL fetch path and checksum it (rotl1+add per word, the
// raiden BIST fold); the CPU is held until it finishes. Expected value
// comes from tools/rf_stream_sum.py. Wrong sum = download side; right sum
// with a still-wild CPU = read side. Reading all 1 MB (not a 64 KB window)
// is also the Phase 1 "runs past 0x40000" proof: the spike itself spins
// waiting for a vblank IRQ it never gets (IPL is tied off).

wire [21:1] cpu_prog_addr;
wire        cpu_prog_req;
reg  [18:0] bist_addr;                  // word address, 0 .. 0x7FFFF
reg         bist_req;
reg  [31:0] bist_sum;
reg  [1:0]  bist_st;                    // 0 idle, 1 reading, 2 done
wire        bist_running = (bist_st == 2'd1);
wire        bist_done    = (bist_st == 2'd2);

wire [15:0] prog_data;
wire        prog_valid;

always @(posedge clk_sys) begin
    bist_req <= 1'b0;
    if (reset | ioctl_download | ~dl_seen) begin
        bist_st <= 2'd0; bist_addr <= 19'd0; bist_sum <= 32'd0;
    end else case (bist_st)
        2'd0: begin bist_st <= 2'd1; bist_req <= 1'b1; end
        2'd1: if (prog_valid) begin
            bist_sum <= {bist_sum[30:0], bist_sum[31]} + {16'd0, prog_data};
            if (bist_addr == 19'h7FFFF) bist_st <= 2'd2;
            else begin bist_addr <= bist_addr + 19'd1; bist_req <= 1'b1; end
        end
        default: ;
    endcase
end

rf_prog_bus prog_bus
(
    .clk_cpu(clk_sys), .reset(bus_reset),
    .addr(bist_running ? {2'd0, bist_addr} : cpu_prog_addr),
    .req(bist_running ? bist_req : cpu_prog_req),
    .data(prog_data), .valid(prog_valid),
    .dl_wr(1'b0), .dl_addr(21'd0), .dl_data(16'd0),
    .dl_busy(), .dl_cnt(),
    .clk_ram(clk_ram),
    .ch_addr(ch3_addr_pb), .ch_dout(ch3_dout), .ch_din(ch3_din_pb),
    .ch_be(ch3_be_pb), .ch_req(ch3_req_pb), .ch_rnw(ch3_rnw_pb),
    .ch_ready(ch3_ready)
);

//////////////////////  F3 MAIN BOARD  //////////////////////////
//
// Held in reset until the ROM download has completed and the readback BIST
// has passed through the fetch path, then runs the real boot code from
// SDRAM against the real F3 memory map, with the real vblank/timer
// interrupts. See rf_main.sv.

wire        cpu_reset = reset | ioctl_download | ~dl_seen | ~bist_done;

wire [31:0] wr_count, wr_hash, last_pc;
wire        trap_oor;
wire [11:0] ring_raddr, ring_wptr;
wire [55:0] ring_rdata;
wire        ring_full;

wire [15:0] frame_cnt, irq2_cnt, irq3_cnt;
wire [15:0] pf_wr_cnt, spr_wr_cnt, pal_wr_cnt, line_wr_cnt, txt_wr_cnt;
wire [15:0] irq2_rate, irq3_rate;
wire        irq_rate_valid;

// Video-side RAM read ports. Only the palette one is driven for now (the
// diagnostic page dumps it); the rest are declared and parked so the
// renderer can be dropped in without touching rf_main again.
wire [13:0] v_pal_addr;
wire [15:0] v_pal_q;

rf_main main
(
    .clk(clk_sys),
    .reset(cpu_reset),
    .prog_addr(cpu_prog_addr), .prog_req(cpu_prog_req),
    .prog_data(prog_data), .prog_valid(prog_valid),

    .vbl_rise(vbl_rise),
    .j0(joystick_0[15:0]), .j1(joystick_1[15:0]),
    .test_sw(status[2]),

    .ctrl0(), .ctrl1(),

    .v_pal_addr(v_pal_addr),   .v_pal_q(v_pal_q),
    .v_pf_addr(14'd0),         .v_pf_q(),
    .v_text_addr(12'd0),       .v_text_q(),
    .v_char_addr(12'd0),       .v_char_q(),
    .v_line_addr(15'd0),       .v_line_q(),
    .v_pivot_addr(15'd0),      .v_pivot_q(),
    .v_spr_addr(15'd0),        .v_spr_q(),

    .wr_count(wr_count), .wr_hash(wr_hash),
    .last_pc(last_pc), .trap_oor(trap_oor),
    .frame_cnt(frame_cnt), .irq2_cnt(irq2_cnt), .irq3_cnt(irq3_cnt),
    .pf_wr_cnt(pf_wr_cnt), .spr_wr_cnt(spr_wr_cnt),
    .pal_wr_cnt(pal_wr_cnt), .line_wr_cnt(line_wr_cnt),
    .txt_wr_cnt(txt_wr_cnt),
    .irq2_rate(irq2_rate), .irq3_rate(irq3_rate),
    .irq_rate_valid(irq_rate_valid),

    .ring_raddr(ring_raddr), .ring_rdata(ring_rdata), .ring_wptr(ring_wptr),
    .ring_full(ring_full)
);

rf_uart_dump uart_dump
(
    .clk(clk_sys),
    .reset(cpu_reset | (uart_mode != 2'd2)),
    .ring_wptr(ring_wptr), .ring_full(ring_full),
    .ring_raddr(ring_raddr), .ring_rdata(ring_rdata),
    .wr_hash(wr_hash),
    .txd(uart_ring_txd)
);

////////////////////////   VIDEO   ///////////////////////////////

rayforce_video video
(
    .clk(clk_sys),
    .reset(reset),

    .dl_active(ioctl_download),
    .dl_seen(dl_seen),
    .dl_bytes(dl_bytes),
    .dl_sum(dl_sum),
    .dl_index(dl_index),
    .trap_oor(trap_oor),
    .wr_count(wr_count),
    .wr_hash(wr_hash),
    .last_pc(last_pc),
    .bist_sum(bist_sum),
    .bist_done(bist_done),

    .frame_cnt(frame_cnt),
    .irq2_cnt(irq2_cnt),
    .irq3_cnt(irq3_cnt),
    .pf_wr_cnt(pf_wr_cnt),
    .spr_wr_cnt(spr_wr_cnt),
    .pal_wr_cnt(pal_wr_cnt),
    .line_wr_cnt(line_wr_cnt),

    .v_pal_addr(v_pal_addr),
    .v_pal_q(v_pal_q),

    .vbl_rise(vbl_rise),
    .div_o(vid_div), .hcnt_o(vid_hcnt), .vcnt_o(vid_vcnt),

    .ce_pix(ce_pix),
    .r(rgb_r), .g(rgb_g), .b(rgb_b),
    .hblank(hblank), .vblank(vblank),
    .hsync(hsync), .vsync(vsync)
);

wire vbl_rise;
wire [2:0] vid_div;
wire [8:0] vid_hcnt, vid_vcnt;

///////////////////  SELF TEST PAGE + UART DEBUG  ////////////////
//
// The self-test page is the bring-up instrument: a labelled pass/fail list
// instead of a screen of bare hex, drawn from its own ROMs so it still
// renders when the video chipset is half-written. rf_uart_log walks the SAME
// character port, so what comes out of /dev/ttyS1 is the page, character for
// character -- no second copy of the formatting to keep in step.
//
//   O[3]   Self Test    0 = show the page (default), 1 = show game video
//   O[5:4] UART Debug   0 = self-test page (default), 1 = off, 2 = the
//                       Phase 0/1 write-ring dump (rf_write_compare.py).
//                       On by default: the OSD cannot be driven remotely, and
//                       a debug channel that has to be switched on by hand at
//                       the cabinet is not much of a debug channel.

wire [23:0] st_rgb;
wire  [4:0] st_urow;
wire  [5:0] st_ucol;
wire  [7:0] st_uchar;

rf_selftest selftest
(
    .clk(clk_sys),
    .div(vid_div), .hcnt(vid_hcnt), .vcnt(vid_vcnt),

    .dl_active(ioctl_download), .dl_seen(dl_seen),
    .dl_bytes(dl_bytes), .dl_sum(dl_sum),
    .bist_sum(bist_sum), .bist_done(bist_done),
    .wr_count(wr_count), .wr_hash(wr_hash),
    .last_pc(last_pc), .trap_oor(trap_oor),
    .frame_cnt(frame_cnt), .irq2_cnt(irq2_cnt), .irq3_cnt(irq3_cnt),
    .irq2_rate(irq2_rate), .irq3_rate(irq3_rate),
    .irq_rate_valid(irq_rate_valid),
    .pal_wr_cnt(pal_wr_cnt), .pf_wr_cnt(pf_wr_cnt), .spr_wr_cnt(spr_wr_cnt),
    .line_wr_cnt(line_wr_cnt), .txt_wr_cnt(txt_wr_cnt),
    .build_hex(`RF_BUILD_HEX),

    .rgb(st_rgb),
    .u_row(st_urow), .u_col(st_ucol), .u_char(st_uchar)
);

rf_uart_log uart_log
(
    .clk(clk_sys),
    .reset(reset),
    .enable(uart_mode == 2'd0),
    .vbl_rise(vbl_rise),
    .row(st_urow), .col(st_ucol), .char_in(st_uchar),
    .txd(uart_log_txd)
);

// Idle high when a producer is not selected, so the HPS UART sees a quiet
// line rather than a break condition.
assign UART_TXD = (uart_mode == 2'd0) ? uart_log_txd  :
                  (uart_mode == 2'd2) ? uart_ring_txd : 1'b1;

wire       ce_pix;
wire [7:0] rgb_r, rgb_g, rgb_b;
wire       hblank, vblank, hsync, vsync;

wire [7:0] r8, g8, b8;
wire       vga_de, vga_hs, vga_vs;
wire [1:0] vga_sl;

arcade_video #(.WIDTH(320), .DW(24)) arcade_video
(
    .clk_video(clk_sys),
    .ce_pix(ce_pix),
    .RGB_in(selftest_on ? st_rgb : {rgb_r, rgb_g, rgb_b}),
    .HBlank(hblank), .VBlank(vblank),
    .HSync(hsync),  .VSync(vsync),

    .CLK_VIDEO(CLK_VIDEO),
    .CE_PIXEL(CE_PIXEL),
    .VGA_R(r8), .VGA_G(g8), .VGA_B(b8),
    .VGA_HS(vga_hs), .VGA_VS(vga_vs), .VGA_DE(vga_de),
    .VGA_SL(vga_sl),

    .fx(3'd0),
    .forced_scandoubler(forced_scandoubler),
    .gamma_bus(gamma_bus)
);

assign VGA_R  = r8;
assign VGA_G  = g8;
assign VGA_B  = b8;
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;
assign VGA_DE = vga_de;
assign VGA_SL = vga_sl;

endmodule
