//============================================================================
//  Share the one DDRAM port between MiSTer's rotation framebuffer and ours.
//
//  The DE10-Nano gives a core exactly ONE port onto the HPS's DDR3, and
//  `screen_rotate` (sys/arcade_video.v) already owns it -- that is what turns
//  this vertical game the right way up on an ordinary display, so it cannot
//  be given up. It is, however, an easy neighbour:
//
//    - DDRAM_RD is tied to 0. It NEVER reads. So every DOUT that ever comes
//      back belongs to the other client, and no read tagging is needed.
//    - DDRAM_BURSTCNT is 1. Single 64-bit words, ~2.1 M/s.
//
//  So this is a plain per-cycle mux with the rotation client on top. Rotation
//  wins because its deadline is the video output itself; the sprite
//  framebuffer has a whole frame of slack and cannot care about losing a
//  cycle here and there.
//
//  BURST LENGTH IS 1 ON BOTH SIDES, deliberately. The MiSTer DDRAM controller
//  accepts one command per cycle while !BUSY, and a sprite line is 80 words
//  in and 80 words out against a 3456-clock line -- under 5 % occupancy even
//  at one word per command. Bursting would mean the granted client had to
//  hold the port for several cycles and feed it in step, which is where a
//  shared port grows its corner cases. Single words keep the arbiter
//  stateless: whoever is granted this cycle drives the port this cycle.
//
//  Everything is in the CLK_VIDEO domain, which this core drives from
//  clk_sys (Rayforce.sv wires video_mixer's clk_video to clk_sys), so the
//  sprite engine is in the same domain and there is no CDC here at all.
//============================================================================

module rf_ddr_arb
(
    input  logic        clk,

    // ---- client R: MiSTer's screen_rotate. Write only, never reads. ------
    input  logic  [7:0] r_burstcnt,
    input  logic [28:0] r_addr,
    input  logic [63:0] r_din,
    input  logic  [7:0] r_be,
    input  logic        r_we,
    output logic        r_busy,

    // ---- client F: the sprite framebuffer. Reads and writes. ------------
    input  logic  [7:0] f_burstcnt,
    input  logic [28:0] f_addr,
    input  logic [63:0] f_din,
    input  logic  [7:0] f_be,
    input  logic        f_we,
    input  logic        f_rd,
    output logic        f_busy,
    output logic [63:0] f_dout,
    output logic        f_dout_ready,

    // ---- the physical port ----------------------------------------------
    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,
    output logic        DDRAM_WE,
    output logic        DDRAM_RD,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY
);

    // Rotation first. Its request is a level the controller consumes while
    // !BUSY, exactly as it would see the port unshared.
    wire grant_r = r_we;
    wire grant_f = ~grant_r & (f_we | f_rd);

    always_comb begin
        if (grant_r) begin
            DDRAM_BURSTCNT = r_burstcnt;
            DDRAM_ADDR     = r_addr;
            DDRAM_DIN      = r_din;
            DDRAM_BE       = r_be;
            DDRAM_WE       = 1'b1;
            DDRAM_RD       = 1'b0;
        end else if (grant_f) begin
            DDRAM_BURSTCNT = f_burstcnt;
            DDRAM_ADDR     = f_addr;
            DDRAM_DIN      = f_din;
            DDRAM_BE       = f_be;
            DDRAM_WE       = f_we;
            DDRAM_RD       = f_rd;
        end else begin
            DDRAM_BURSTCNT = 8'd1;
            DDRAM_ADDR     = 29'd0;
            DDRAM_DIN      = 64'd0;
            DDRAM_BE       = 8'd0;
            DDRAM_WE       = 1'b0;
            DDRAM_RD       = 1'b0;
        end
    end

    // Each client sees the port as busy when the controller is busy, and the
    // framebuffer additionally whenever rotation is using it. Rotation's view
    // is therefore bit-identical to the unshared case -- it cannot tell this
    // module is here, which is the point: sys/ is not ours to debug.
    assign r_busy = DDRAM_BUSY;
    assign f_busy = DDRAM_BUSY | grant_r;

    // Rotation never reads, so every returning word is the framebuffer's.
    assign f_dout       = DDRAM_DOUT;
    assign f_dout_ready = DDRAM_DOUT_READY;

endmodule
