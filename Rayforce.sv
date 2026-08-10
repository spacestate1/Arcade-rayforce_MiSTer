//============================================================================
//  Ray Force / Gunlock (Taito F3) for MiSTer -- skeleton build
//
//  This is deliberately NOT a game yet. It exists to prove the plumbing on
//  real hardware before any chip RTL is written, the same way the Raiden II
//  core started:
//
//    - the MiSTer framework wrapper compiles and the core loads from an MRA
//    - the PLL makes the F3 pixel clock: 26.686 MHz / 4 = 6.6715 MHz,
//      generated as clk_sys = 53.372 MHz / 8 (432 x 262 total = 58.94 Hz,
//      taito_f3.cpp set_raw values)
//    - the MRA -> HPS -> ioctl download path works: every byte of the ROM
//      stream is counted and checksummed AS RECEIVED, and the totals are
//      shown on screen in hex, live
//
//  So the acceptance test for this build is: pick Ray Force from the Arcade
//  menu, see the test screen, and read byte count 0x00A20000 with a stable
//  checksum -- at 58.94 Hz. Nothing else is claimed.
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
assign UART_TXD = 1'b1;                    // idle; the UART stream comes later
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

// SDRAM parked safe: clock enable low, chip deselected, DQ released.
assign SDRAM_CLK  = 0;
assign SDRAM_CKE  = 0;
assign SDRAM_A    = 0;
assign SDRAM_BA   = 0;
assign SDRAM_DQ   = 'Z;
assign {SDRAM_DQML, SDRAM_DQMH} = 2'b11;
assign SDRAM_nCS  = 1;
assign SDRAM_nCAS = 1;
assign SDRAM_nRAS = 1;
assign SDRAM_nWE  = 1;

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

localparam CONF_STR = {
    "Rayforce;;",
    "-;",
    "R[0],Reset;",
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

wire [31:0] joystick_0;

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
    .ioctl_wait(1'b0),

    .joystick_0(joystick_0),
    .ps2_key()
);

///////////////////////   CLOCKS   ///////////////////////////////
//
// clk_sys = 53.372 MHz = 8 x the F3 pixel clock (26.686 MHz XTAL / 4).
// outclk_0 stays at the 96 MHz the Raiden SDRAM controller closes timing
// at, so the controller can drop in later without touching the PLL again.

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

//////////////////////  ROM DOWNLOAD PROOF  //////////////////////
//
// Counts and checksums the ioctl stream exactly as received. The MRA for
// gunlock/rayforce streams 0x00A20000 bytes (10.125 MB); the rolling sum is
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

    .ce_pix(ce_pix),
    .r(rgb_r), .g(rgb_g), .b(rgb_b),
    .hblank(hblank), .vblank(vblank),
    .hsync(hsync), .vsync(vsync)
);

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
    .RGB_in({rgb_r, rgb_g, rgb_b}),
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
