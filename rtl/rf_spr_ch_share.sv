//============================================================================
//  Share one physical SDRAM channel between the sprite gfx planes.
//
//  The sprite engine keeps TWO tile-row fetches in flight (two rf_spr_gfx_bus
//  instances, A and B, taking alternate records) and each fetch is two
//  planes (low and high gfx ROM), so four requesters want the one free
//  channel, ch4. Each request is a LEVEL held until the plane's completion
//  toggle comes back, with the address stable the whole time (the
//  rf_gfx_bus CDC contract), so a grant-and-hold mux is enough:
//
//    - idle: grant a waiting plane, latch its address, raise the channel
//      request. Priority ROTATES: the port after the one just served goes
//      first, in the order A.lo, A.hi, B.lo, B.hi -- so a record's two
//      planes are served back to back and the OLDER record's planes go
//      before the younger's (the draw consumes records in issue order, so
//      serving the younger first would only stall it).
//    - granted: hold until the channel's ready pulse, which is forwarded to
//      the granted plane only
//    - served planes are masked until their request level actually drops:
//      the level outlives the completion by the CDC crossing (several
//      cycles), and without the mask the arbiter would re-grant a plane
//      that has already been served, double-toggling its completion and
//      permanently desyncing the edge detector in rf_spr_gfx_bus
//
//  Everything here is in the ram clock domain. The plane requests are
//  levels from the cpu domain and go through a two-flop synchroniser
//  before anything looks at them -- the same treatment the sdram
//  controller gives its own channel requests. The address is stable from
//  before the level rises, so by the time the synchronised level is seen
//  it is safe to latch unsynchronised. ch_req is a registered level the
//  controller's two-flop synchroniser edge-detects; between back-to-back
//  grants it is low for one cycle, which the synchroniser still resolves
//  as a gap.
//============================================================================

module rf_spr_ch_share
(
    input  logic        clk_ram,

    // plane request ports (levels from the cpu clock domain)
    input  logic [26:1] a_lo_addr,
    output logic [63:0] a_lo_dout,
    input  logic        a_lo_req,
    output logic        a_lo_ready,

    input  logic [26:1] a_hi_addr,
    output logic [63:0] a_hi_dout,
    input  logic        a_hi_req,
    output logic        a_hi_ready,

    input  logic [26:1] b_lo_addr,
    output logic [63:0] b_lo_dout,
    input  logic        b_lo_req,
    output logic        b_lo_ready,

    input  logic [26:1] b_hi_addr,
    output logic [63:0] b_hi_dout,
    input  logic        b_hi_req,
    output logic        b_hi_ready,

    // the one physical channel
    output logic [26:1] ch_addr,
    input  logic [63:0] ch_dout,
    output logic        ch_req,
    input  logic        ch_ready
);

    // port order: 0 = A.lo, 1 = A.hi, 2 = B.lo, 3 = B.hi
    wire  [3:0] req_raw = {b_hi_req, b_lo_req, a_hi_req, a_lo_req};
    logic [3:0] req_s, req_r;           // synchronised levels
    always_ff @(posedge clk_ram) begin
        req_s <= req_raw;
        req_r <= req_s;
    end

    logic       own;                    // a grant is being held
    logic [1:0] sel;                    // the granted port
    logic [1:0] rr;                     // the port with top priority
    logic [3:0] mask;                   // served, waiting for the level to drop

    wire  [3:0] want = req_r & ~mask;
    wire  [1:0] i0 = rr, i1 = rr + 2'd1, i2 = rr + 2'd2, i3 = rr + 2'd3;
    wire  [1:0] pick = want[i0] ? i0 : want[i1] ? i1 : want[i2] ? i2 : i3;
    wire        any  = |want;
    wire [26:1] pick_addr = (pick == 2'd0) ? a_lo_addr :
                            (pick == 2'd1) ? a_hi_addr :
                            (pick == 2'd2) ? b_lo_addr : b_hi_addr;

    always_ff @(posedge clk_ram) begin
        mask <= mask & req_r;           // release once the level has dropped

        if (!own) begin
            ch_req <= 1'b0;
            if (any) begin
                own     <= 1'b1;
                sel     <= pick;
                rr      <= pick + 2'd1;
                ch_addr <= pick_addr;
                ch_req  <= 1'b1;
            end
        end else if (ch_ready) begin
            own       <= 1'b0;
            ch_req    <= 1'b0;
            mask[sel] <= 1'b1;
        end
    end

    // ready is a one-cycle pulse; only the granted plane may see it
    assign a_lo_ready = ch_ready && own && (sel == 2'd0);
    assign a_hi_ready = ch_ready && own && (sel == 2'd1);
    assign b_lo_ready = ch_ready && own && (sel == 2'd2);
    assign b_hi_ready = ch_ready && own && (sel == 2'd3);
    assign a_lo_dout  = ch_dout;
    assign a_hi_dout  = ch_dout;
    assign b_lo_dout  = ch_dout;
    assign b_hi_dout  = ch_dout;

endmodule
