//============================================================================
//  Program bus bridge: TG68K-side 16-bit reads from the F3 program ROM in
//  SDRAM, through a one-line (4-word) burst cache, plus the download write
//  path. Sits between rf_main's bus FSM (clk_cpu) and the SDRAM controller
//  channel (clk_ram).
//
//  Ported from Arcade_propcycle_MiSTer/rtl/pc_prog_bus.sv.
//
//  Why a line cache from day one: the Raiden II core shipped discarding 48
//  of every 64 burst bits and the CPU stalled on fetch 54.9% of all cycles.
//  Instruction fetch is overwhelmingly sequential; keep the whole burst.
//
//  CDC, following the two proven raiden2 rules:
//    - the request is a LEVEL held by the cpu domain until completion; the
//      controller's own two-flop synchronizer edge-detects it. Address,
//      data and rnw are stable the whole time the level is up.
//    - completion comes back as a TOGGLE flipped in the ram domain on
//      ch_ready (a 1-cycle ram-clock pulse would be missed at cpu clock);
//      the cpu domain double-flops the toggle and edge-detects. The 64-bit
//      burst is latched in the ram domain at ready and is stable long
//      before the cpu-domain edge fires.
//
//  Requests are always LINE-ALIGNED (addr[2:1]=00 in the ch address), so
//  the SDRAM controller's burst fills dout[15:0]=word0 ... [63:48]=word3
//  in ascending address order.
//
//  F3 SDRAM map (from the MRA):
//     0x000000  maincpu   1 MB    4-way byte interleave
//     0x100000  audiocpu  512 KB  16-bit interleave
//     0x180000  sprites   2 MB    16-bit interleave
//     0x380000  sprites_hi 1 MB
//     0x480000  tilemap   2 MB    LOAD32_WORD pair
//     0x680000  tilemap_hi 1 MB
//     0x780000  ensoniq   4 MB
//============================================================================

module rf_prog_bus
(
    input  logic        clk_cpu,
    input  logic        reset,

    // CPU-side read port: one 16-bit program word per request
    input  logic [21:1] addr,
    input  logic        req,          // one-cycle pulse
    output logic [15:0] data,
    output logic        valid,        // one-cycle pulse when data is good

    // download write port (cpu domain; CPU is in reset while this runs)
    input  logic        dl_wr,        // one-cycle pulse
    input  logic [21:1] dl_addr,
    input  logic [15:0] dl_data,
    output logic        dl_busy,      // raise ioctl_wait while set
    output logic [21:0] dl_cnt,       // dispatched download writes

    // SDRAM channel (clk_ram domain)
    input  logic        clk_ram,
    output logic [26:1] ch_addr,
    input  logic [63:0] ch_dout,
    output logic [15:0] ch_din,
    output logic [1:0]  ch_be,
    output logic        ch_req,       // level, controller edge-detects
    output logic        ch_rnw,
    input  logic        ch_ready      // 1-cycle pulse, ram domain
);

    // ---- line cache (cpu domain) ----------------------------------------
    logic [63:0] line_data;
    logic [21:3] line_tag;
    logic        line_valid;

    // ---- ram-domain completion capture ----------------------------------
    // done_t lives in the ram domain with no reset; the declaration init is
    // the intended FPGA power-up value for the toggle protocol.
    /* verilator lint_off PROCASSINIT */
    logic        done_t = 1'b0;       // toggles on every completed transaction
    /* verilator lint_on PROCASSINIT */
    logic [63:0] ram_dout;
    always_ff @(posedge clk_ram) begin
        if (ch_ready) begin
            ram_dout <= ch_dout;
            done_t   <= ~done_t;
        end
    end

    // cpu-domain sync + edge detect. THREE stages before the edge, not two:
    // the done toggle is control, but consuming it also samples ram_dout,
    // whose routing from the ram domain is CUT from timing analysis by the
    // async clock groups -- its delay is whatever the router happened to do
    // that build. With a 2-deep chain the arrival budget was ~2 cpu cycles
    // and PASSED OR FAILED BY SEED. The third stage buys a full extra cycle
    // of arrival margin.
    logic done_s, done_1, done_2, done_3;
    always_ff @(posedge clk_cpu) begin
        done_s <= done_t;
        done_1 <= done_s;
        done_2 <= done_1;
        done_3 <= done_2;
    end
    wire done_edge = done_2 ^ done_3;

    // ---- request engine (cpu domain) ------------------------------------
    typedef enum logic [1:0] { IDLE, FETCH, STORE } st_t;
    st_t st;                          // reset drives it to IDLE

    logic [21:1] r_addr;              // requested word (for the serve mux)

    // download FIFO: the HPS skids 1-2 words past ioctl_wait, so a dl_wr
    // landing mid-STORE would be silently DROPPED without this buffer.
    // 8-deep proved sufficient on Propcycle; same here.
    logic [36:0] dlf [0:7];           // {addr[21:1], data[15:0]}
    logic [2:0]  dlf_wp, dlf_rp;
    wire         dl_pend = (dlf_wp != dlf_rp);
    always_ff @(posedge clk_cpu) begin
        if (reset) dlf_wp <= 3'd0;
        else if (dl_wr) begin
            dlf[dlf_wp] <= {dl_addr, dl_data};
            dlf_wp <= dlf_wp + 3'd1;
        end
    end
    wire [36:0] dlf_head = dlf[dlf_rp];

    // read requests latch here too: a req arriving while the engine is in
    // STORE was silently LOST on Propcycle (bench hang, 2026-08-10 night).
    logic        rd_pend;
    logic [21:1] rd_addr_l;

    always_ff @(posedge clk_cpu) begin
        valid   <= 1'b0;

        if (reset) begin
            st         <= IDLE;
            ch_req     <= 1'b0;
            line_valid <= 1'b0;
            dl_busy    <= 1'b0;
            dlf_rp     <= 3'd0;
            dl_cnt     <= 22'd0;
            rd_pend    <= 1'b0;
        end else begin
            if (req) begin rd_pend <= 1'b1; rd_addr_l <= addr; end
            dl_busy <= dl_pend || dl_wr;      // wait while anything queued
            case (st)
            IDLE: begin
                if (dl_pend) begin
                    // download word: write-through, invalidate the line
                    ch_addr    <= {5'd0, dlf_head[36:16]};
                    // ioctl words are little-endian ([7:0] = the even byte);
                    // the 68020 bus wants {even, odd}. The BRAM spike swapped
                    // here and the SDRAM path must match.
                    ch_din     <= {dlf_head[7:0], dlf_head[15:8]};
                    ch_be      <= 2'b11;
                    ch_rnw     <= 1'b0;
                    ch_req     <= 1'b1;
                    dlf_rp     <= dlf_rp + 3'd1;
                    dl_cnt     <= dl_cnt + 22'd1;
                    line_valid <= 1'b0;
                    st         <= STORE;
                end else if (rd_pend) begin
                    rd_pend <= req;             // same-cycle arrival queues
                    r_addr  <= rd_addr_l;
                    if (line_valid && line_tag == rd_addr_l[21:3]) begin
                        valid <= 1'b1;          // hit: serve next cycle
                    end else begin
                        ch_addr <= {5'd0, rd_addr_l[21:3], 2'b00};
                        ch_rnw  <= 1'b1;
                        ch_req  <= 1'b1;
                        st      <= FETCH;
                    end
                end
            end

            FETCH: if (done_edge) begin
                ch_req     <= 1'b0;             // drop on the consume cycle
                line_data  <= ram_dout;
                line_tag   <= r_addr[21:3];
                line_valid <= 1'b1;
                valid      <= 1'b1;
                st         <= IDLE;
            end

            STORE: if (done_edge) begin
                ch_req <= 1'b0;
                st     <= IDLE;
            end

            default: st <= IDLE;
            endcase
        end
    end

    // serve mux: line_data commits at the same edge that schedules `valid`,
    // so by the cycle valid is high the line is always the right one --
    // for a hit (unchanged) and for a miss-fill (just latched) alike
    always_comb begin
        case (r_addr[2:1])
            2'd0: data = line_data[15:0];
            2'd1: data = line_data[31:16];
            2'd2: data = line_data[47:32];
            2'd3: data = line_data[63:48];
        endcase
    end

endmodule
