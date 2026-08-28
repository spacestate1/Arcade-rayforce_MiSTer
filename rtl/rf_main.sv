//============================================================================
//  Ray Force / Gunlock -- Taito F3 main board
//
//  This replaces rf_cpu_spike. The spike answered one question (does TG68K.C
//  in 020 mode execute this program the way a 68020 does -- yes, write hash
//  0x10620931) with a deliberately fake memory map: everything outside
//  ROM/RAM/palette read back as zero and no interrupt was ever delivered, so
//  the boot code ran to its vblank wait at ~0x4060 and stopped there.
//
//  Phase 2 needs the program actually running, so this is the real map from
//  taito_f3.cpp f3_map, plus the two interrupts and the control port:
//
//    000000-0FFFFF  program ROM, 1 MB, SDRAM via rf_prog_bus (wait-stated)
//    100000-1FFFFF  rest of the mapped ROM window, unpopulated -> 0x0000
//    300000-30007F  sound bankswitch (KIRAMEKI only; ignored, write-only)
//    400000-41FFFF  main RAM 128 KB, mirrored at 420000-43FFFF
//    440000-447FFF  palette RAM 32 KB = 8192 x 24-bit entries
//    4A0000-4A001F  control: inputs, coin counters, EEPROM, watchdog
//    4C0000-4C0003  timer control (gunlock writes 0x0000; ignored)
//    600000-60FFFF  sprite RAM 64 KB
//    610000-617FFF  playfield RAM, the tilemap window (4 x 0x2000, extend)
//    618000-61BFFF  playfield RAM, upper half -- RAM, not used as tilemaps
//    61C000-61DFFF  text RAM 8 KB   (64x64 char codes + palette)
//    61E000-61FFFF  char RAM 8 KB   (256 4bpp 8x8 characters, CPU generated)
//    620000-62FFFF  line RAM 64 KB  (the per-scanline effect engine)
//    630000-63FFFF  pivot RAM 64 KB (512x256 4bpp pixel layer)
//    660000-66001F  video control: playfield scroll, pivot scroll, extend
//    C00000-C007FF  dual-port RAM to the sound 68000 (MB8421)
//    C80000/C80100  sound CPU reset (ignored until Phase 3)
//
//  Interrupts, from taito_f3.cpp:
//    level 2  vblank, HOLD_LINE
//    level 3  10000 68020 cycles (625 us at 16 MHz) after the vblank IRQ.
//             "some signal from video hardware?" -- the vblank handler waits
//             for it, so it must be delivered or the game hangs in vblank.
//  Both are autovectored (68EC020 AVEC), so the CPU fetches its handler from
//  VBR+0x68 / VBR+0x6C. That fetch IS the acknowledge: TG68K.C exposes no
//  IACK strobe, and the vector read is the one bus cycle that can only mean
//  "the exception is being taken". irq2_cnt/irq3_cnt are on the diagnostic
//  screen so a missed acknowledge shows up as a counter running away from
//  the frame count instead of as a mystery hang.
//
//  The write-stream capture from the spike is kept verbatim -- same ring,
//  same rotl1+add fold -- because it is still the regression oracle against
//  MAME's rf_acc.tr. The first 4096 writes are boot clear loops that finish
//  long before the first vblank, so adding real memory and real interrupts
//  must NOT change the hash. If it does, something here is wrong.
//
//  BRAMs are EXPLICIT altsyncram instances (rf_bram*), never inferred
//  arrays: quartus_map 17.0 does not terminate inferring large byte-sliced
//  arrays (Propcycle, 2026-08-10).
//============================================================================

module rf_main
(
    input  logic        clk,             // 53.372 MHz
    input  logic        reset,

    // program ROM read port (rf_prog_bus client, line-cached SDRAM fetch)
    output logic [21:1] prog_addr,
    output logic        prog_req,
    input  logic [15:0] prog_data,
    input  logic        prog_valid,

    // raster interface: one clk pulse on the first line of vblank
    input  logic        vbl_rise,

    // player inputs, MiSTer joystick words (active high)
    //   [0]=right [1]=left [2]=down [3]=up, buttons from [4],
    //   Start=[10] Coin=[11] Service=[12]
    input  logic [15:0] j0,
    input  logic        pause,          // hold the CPU (MiSTer Pause button)
    input  logic [15:0] j1,
    input  logic        test_sw,        // cabinet TEST switch (OSD toggle)

    // ---- NVRAM: the settings EEPROM, loaded from and saved to the SD card
    // through hps_io's ioctl index 254 (see Rayforce.sv)
    input  logic        nv_wr,
    input  logic  [5:0] nv_addr,
    input  logic [15:0] nv_data,
    input  logic  [5:0] nv_sv_addr,
    output logic [15:0] nv_sv_data,
    output logic        nv_wrote,

    // ---- video side ----------------------------------------------------
    // Playfield / pivot / sprite scroll and the 1024x512 "extend" bit.
    // ctrl0 = 0x660000-0F (words 0-7), ctrl1 = 0x660010-1F (words 8-15).
    output logic [7:0][15:0] ctrl0,
    output logic [7:0][15:0] ctrl1,

    // Read ports into the video RAMs. Every one is the B side of a true
    // dual-port BRAM; the CPU owns the A side. Address in, data out one
    // clock later, held until the address changes.
    input  logic [13:0] v_pal_addr,   output logic [15:0] v_pal_q,
    input  logic [13:0] v_pf_addr,    output logic [15:0] v_pf_q,
    input  logic [11:0] v_text_addr,  output logic [15:0] v_text_q,
    input  logic [11:0] v_char_addr,  output logic [15:0] v_char_q,
    input  logic [14:0] v_line_addr,  output logic [15:0] v_line_q,
    input  logic [14:0] v_pivot_addr, output logic [15:0] v_pivot_q,
    input  logic [14:0] v_spr_addr,   output logic [15:0] v_spr_q,

    // ---- instrumentation -------------------------------------------------
    output logic [31:0] wr_count,
    output logic [31:0] wr_hash,
    output logic [31:0] last_pc,
    output logic        trap_oor,
    output logic [15:0] frame_cnt,
    output logic [15:0] irq2_cnt,
    output logic [15:0] irq3_cnt,
    output logic [15:0] pf_wr_cnt,
    output logic [15:0] spr_wr_cnt,
    output logic [15:0] pal_wr_cnt,
    output logic [15:0] line_wr_cnt,
    output logic [15:0] txt_wr_cnt,
    // Interrupt acknowledges in the last 64 frames. A running game takes
    // exactly one vblank interrupt per frame, so 64 here is the pass
    // condition -- a raw counter cannot tell "acknowledged every frame" from
    // "acknowledged twice on half of them".
    output logic [15:0] irq2_rate,
    output logic [15:0] irq3_rate,
    output logic        irq_rate_valid,

    // ---- sound board (Phase 3) -------------------------------------------
    // the MB8421's other side, driven by rf_sound_main
    input  logic  [9:0] snd_dp_addr,
    input  logic [15:0] snd_dp_wdata,
    input  logic        snd_dp_wren,
    input  logic  [1:0] snd_dp_be,
    output logic [15:0] snd_dp_q,
    // C80100 asserts the sound CPU's reset, C80000 releases it; held from
    // boot (taito_f3.cpp machine_reset asserts it)
    output logic        snd_reset,
    // when ring_ext_sel, the write ring records ring_ext_* (the sound
    // CPU's chip writes) instead of this CPU's writes
    input  logic        ring_ext_sel,
    input  logic        ring_ext_we,
    input  logic [55:0] ring_ext_data,
    // pivot RAM is a stub (Ray Force only ever CLEARS it -- one 64 KB
    // write of zeros at boot, and all 30 dumped frames are zero -- and its
    // 64 M10Ks are the sound RAM's); this counts non-zero writes to it so
    // that assumption is checked on every run
    output logic [15:0] pivot_wr_cnt,

    // write-ring dump port (UART side)
    input  logic [10:0] ring_raddr,
    output logic [55:0] ring_rdata,
    output logic [10:0] ring_wptr,
    output logic        ring_full
);

    // ---- CPU -------------------------------------------------------------
    logic        clkena;
    logic [31:0] cpu_addr;
    logic [15:0] cpu_din, cpu_dout;
    logic        nWr, nUDS, nLDS;
    logic [1:0]  busstate;              // 00 fetch, 10 read, 11 write, 01 none
    logic [31:0] vbr;
    logic  [2:0] ipl;

    // Wait-state engine, unchanged from the spike (it is the validated part):
    // BRAM and register targets are 2-cycle ops; a ROM access issues one
    // prog_bus request and holds clkena low until the data returns.
    // THE BOOT-BUG RULE: `a` is sampled ONLY while clkena is low -- once
    // clkena pulses, addr_out already belongs to the next operation.
    logic        rom_wait;
    logic        prog_valid_lat;
    logic [15:0] prog_data_lat;

    always_ff @(posedge clk) begin
        if (reset) begin
            clkena    <= 1'b0;
            rom_wait  <= 1'b0;
            prog_req  <= 1'b0;
        end else begin
            prog_req <= 1'b0;
            clkena   <= 1'b0;

            if (rom_wait) begin
                if (prog_valid_lat) begin
                    rom_wait <= 1'b0;
                    clkena   <= 1'b1;
                end
            end else if (!clkena && !pause) begin
                // pause: no further clock enables, so the CPU freezes between
                // bus cycles (a ROM fetch in flight still completes above)
                if (sel_rom && (busstate == 2'b00 || busstate == 2'b10)) begin
                    prog_addr <= a[21:1];
                    prog_req  <= 1'b1;
                    rom_wait  <= 1'b1;
                end else begin
                    clkena <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset || clkena) prog_valid_lat <= 1'b0;
        else if (prog_valid) begin
            prog_valid_lat <= 1'b1;
            prog_data_lat  <= prog_data;
        end
    end

    TG68KdotC_Kernel #(
        .SR_Read(2), .VBR_Stackframe(2), .extAddr_Mode(2),
        .MUL_Mode(2), .DIV_Mode(2), .BitField(2),
        .BarrelShifter(1), .MUL_Hardware(1)
    ) cpu (
        .clk(clk),
        .nReset(~reset),
        .clkena_in(clkena),
        .data_in(cpu_din),
        .IPL(ipl),
        .IPL_autovector(1'b1),          // 68EC020 AVEC: vector = 0x18 | level
        .berr(1'b0),
        .CPU(2'b11),                    // 68020 mode
        .addr_out(cpu_addr),
        .data_write(cpu_dout),
        .nWr(nWr),
        .nUDS(nUDS),
        .nLDS(nLDS),
        .busstate(busstate),
        .longword(),
        .nResetOut(),
        .FC(),
        .clr_berr(),
        .skipFetch(),
        .regin_out(),
        .CACR_out(),
        .VBR_out(vbr)
    );

    // ---- address decode --------------------------------------------------
    wire [23:0] a = cpu_addr[23:0];

    // The program ROM window is the full 2 MB the F3 map gives it: Ray Force
    // populates 1 MB and the MRA pads the rest with zeros, which reads the
    // same as the unpopulated window did. Elevator Action Returns fills it.
    wire sel_rom   = (a[23:21] == 3'b000);                          // 000000-1FFFFF
    wire sel_romhi = 1'b0;                                          // (folded into sel_rom)
    wire sel_ram   = (a[23:18] == 6'b010000);                       // 400000-43FFFF (+mirror)
    wire sel_pal   = (a[23:15] == 9'b010001000);                    // 440000-447FFF
    wire sel_ctrl  = (a[23:16] == 8'h4A);
    wire sel_spr   = (a[23:16] == 8'h60);                           // 600000-60FFFF
    wire sel_61    = (a[23:16] == 8'h61);
    wire sel_pf    = sel_61 && !a[15];                              // 610000-617FFF
    wire sel_pfx   = sel_61 && (a[15:14] == 2'b10);                 // 618000-61BFFF
    wire sel_text  = sel_61 && (a[15:13] == 3'b110);                // 61C000-61DFFF
    wire sel_char  = sel_61 && (a[15:13] == 3'b111);                // 61E000-61FFFF
    wire sel_line  = (a[23:16] == 8'h62);                           // 620000-62FFFF
    wire sel_pivot = (a[23:16] == 8'h63);                           // 630000-63FFFF
    wire sel_vctrl = (a[23:16] == 8'h66) && (a[15:5] == 11'd0);     // 660000-66001F
    wire sel_dpram = (a[23:11] == 13'b1100000000000);               // C00000-C007FF

    wire cpu_wr = !nWr && (busstate == 2'b11) && clkena;
    wire [1:0] be = {~nUDS, ~nLDS};

    // ---- interrupts ------------------------------------------------------
    // 625 us after the vblank IRQ, in clk_sys ticks: 10000 cycles of a 16 MHz
    // 68020 = 625.0 us; 625 us x 53.372 MHz = 33358.
    localparam int INT3_DELAY = 33358;

    logic        irq2, irq3;
    logic [15:0] int3_tmr;

    // The autovector handler fetch is the acknowledge (see the header note).
    //
    // KNOWN LIMITATION: any data READ of VBR+0x68 / +0x6C while the IRQ is
    // pending also counts. The one place that happens is the boot ROM
    // checksum, which sweeps the vector table while interrupts are masked --
    // it drops a pending IRQ2 the game was not going to service anyway, and
    // is where the constant 380-frame offset between frame_cnt and irq2_cnt
    // comes from. Once the game is running nothing reads the vector table as
    // data, and the hardware acknowledge rate is exactly one per frame.
    wire vec_rd = clkena && (busstate == 2'b10);
    wire ack2   = irq2 && vec_rd && (a == (vbr[23:0] + 24'h68));
    wire ack3   = irq3 && vec_rd && (a == (vbr[23:0] + 24'h6C));

    always_ff @(posedge clk) begin
        if (reset) begin
            irq2 <= 1'b0; irq3 <= 1'b0; int3_tmr <= 16'd0;
            frame_cnt <= 16'd0; irq2_cnt <= 16'd0; irq3_cnt <= 16'd0;
        end else begin
            if (vbl_rise) begin
                irq2      <= 1'b1;
                int3_tmr  <= INT3_DELAY[15:0];
                frame_cnt <= frame_cnt + 16'd1;
            end else if (int3_tmr != 16'd0) begin
                int3_tmr <= int3_tmr - 16'd1;
                if (int3_tmr == 16'd1) irq3 <= 1'b1;
            end
            if (ack2) begin irq2 <= 1'b0; irq2_cnt <= irq2_cnt + 16'd1; end
            if (ack3) begin irq3 <= 1'b0; irq3_cnt <= irq3_cnt + 16'd1; end
        end
    end

    // Acknowledge rate over a 64-frame window.
    logic  [5:0] rate_win;
    logic [15:0] i2_mark, i3_mark;

    always_ff @(posedge clk) begin
        if (reset) begin
            rate_win <= 6'd0; i2_mark <= 16'd0; i3_mark <= 16'd0;
            irq2_rate <= 16'd0; irq3_rate <= 16'd0; irq_rate_valid <= 1'b0;
        end else if (vbl_rise) begin
            rate_win <= rate_win + 6'd1;
            if (rate_win == 6'd63) begin
                irq2_rate <= irq2_cnt - i2_mark;
                irq3_rate <= irq3_cnt - i3_mark;
                i2_mark   <= irq2_cnt;
                i3_mark   <= irq3_cnt;
                irq_rate_valid <= 1'b1;
            end
        end
    end

    // IPL is active low on this core; level 3 wins over level 2.
    always_comb begin
        if      (irq3) ipl = 3'b100;    // ~3
        else if (irq2) ipl = 3'b101;    // ~2
        else           ipl = 3'b111;
    end

    // ---- control port 0x4A0000 ------------------------------------------
    logic [15:0] coin_word0, coin_word1;
    logic        ee_cs, ee_sk, ee_di;
    wire         ee_do;

    rf_eeprom_93c46 eeprom
    (
        .clk(clk), .reset(reset),
        .cs(ee_cs), .sk(ee_sk), .di(ee_di), .do_out(ee_do),
        .ld_wr(nv_wr), .ld_addr(nv_addr), .ld_data(nv_data),
        .sv_addr(nv_sv_addr), .sv_data(nv_sv_data), .wrote(nv_wrote)
    );

    // EEPROMIN: bit0 EEPROM data out, bit1 TEST switch (active low),
    // bits 4-7 coin inputs (active low), the rest pulled high.
    wire [7:0] ee_in = {2'b11, ~j1[11], ~j0[11], 2'b11, ~test_sw, ee_do};

    // IN.0 low word, all active low.
    //  15..12 start 4/3/2/1   11..8 service 3/2/1, tilt
    //   7.. 4 P2 buttons 4..1  3..0 P1 buttons 4..1
    wire [15:0] in0_lo = { 1'b1, 1'b1, ~j1[10], ~j0[10],
                           1'b1, 1'b1, ~(j0[12] | j1[12]), 1'b1,
                           ~j1[7], ~j1[6], ~j1[5], ~j1[4],
                           ~j0[7], ~j0[6], ~j0[5], ~j0[4] };

    // IN.1 low word: joysticks, active low, bit order up/down/left/right from
    // bit 0 up. MiSTer's joystick word is right/left/down/up from bit 0, so
    // the nibbles are reversed here. Bits 8-15 must read high.
    wire [15:0] in1_lo = { 8'hFF,
                           ~j1[0], ~j1[1], ~j1[2], ~j1[3],
                           ~j0[0], ~j0[1], ~j0[2], ~j0[3] };

    logic [15:0] ctrl_q;
    always_comb begin
        case (a[4:1])
            4'h0: ctrl_q = {ee_in, ee_in};      // IN.0 high word (EEPROM byte x2)
            4'h1: ctrl_q = in0_lo;              // IN.0 low  word
            4'h2: ctrl_q = coin_word0;          // IN.1 high word
            4'h3: ctrl_q = in1_lo;              // IN.1 low  word
            4'h4: ctrl_q = 16'hFFFF;            // IN.2 analog, high word
            4'h5: ctrl_q = 16'h0000;            // IN.2 analog, no dial fitted
            4'h6: ctrl_q = 16'hFFFF;            // IN.3 analog, high word
            4'h7: ctrl_q = 16'h0000;            // IN.3 analog
            4'h8: ctrl_q = 16'hFFFF;            // IN.4 P3/P4 buttons
            4'h9: ctrl_q = 16'hFFFF;
            4'hA: ctrl_q = coin_word1;          // IN.5 high word
            4'hB: ctrl_q = 16'hFFFF;            // IN.5 P3/P4 joysticks
            default: ctrl_q = 16'hFFFF;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            coin_word0 <= 16'd0; coin_word1 <= 16'd0;
            {ee_cs, ee_sk, ee_di} <= 3'b000;
        end else if (cpu_wr && sel_ctrl) begin
            case (a[4:1])
                4'h2: coin_word0 <= cpu_dout;               // 4A0004, upper half
                4'hA: coin_word1 <= cpu_dout;               // 4A0014, upper half
                4'h9: if (!nLDS) begin                      // 4A0012 low byte
                    ee_di <= cpu_dout[2];
                    ee_sk <= cpu_dout[3];
                    ee_cs <= cpu_dout[4];
                end
                default: ;                                  // 4A0000 watchdog etc.
            endcase
        end
    end

    // ---- video control registers 0x660000 -------------------------------
    // Held in unpacked arrays and flattened onto the packed output ports:
    // a variable index into an unpacked array of vectors is the shape
    // Quartus handles best, and the ports stay plain vectors.
    logic [15:0] c0 [0:7];
    logic [15:0] c1 [0:7];
    integer ci;

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_vctrl
            assign ctrl0[gi] = c0[gi];
            assign ctrl1[gi] = c1[gi];
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (reset) begin
            for (ci = 0; ci < 8; ci = ci + 1) begin
                c0[ci] <= 16'd0;
                c1[ci] <= 16'd0;
            end
        end else if (cpu_wr && sel_vctrl) begin
            if (!a[4]) begin
                if (be[1]) c0[a[3:1]][15:8] <= cpu_dout[15:8];
                if (be[0]) c0[a[3:1]][7:0]  <= cpu_dout[7:0];
            end else begin
                if (be[1]) c1[a[3:1]][15:8] <= cpu_dout[15:8];
                if (be[0]) c1[a[3:1]][7:0]  <= cpu_dout[7:0];
            end
        end
    end

    // ---- memories --------------------------------------------------------
    wire [15:0] ram_q, pal_q, spr_q, pf_q, pfx_q, text_q, char_q,
                line_q, pivot_q, dpram_q;

    // Each CPU write fires ONCE, on the clock-enable cycle. busstate stays
    // 2'b11 for both cycles of a 2-cycle bus op, so without a qualifier the
    // write is performed twice; the one that commits at the end of the
    // clock-enable cycle is the one carrying valid address and data, which
    // build 28154550 established the hard way -- qualifying with !clkena
    // instead (rf_sound_main's rule, which does not transfer: different
    // TG68K mode and speed divider) broke Ray Force outright.
    //
    // The control and video-control registers are left unqualified: writing
    // the same value twice to a latch is idempotent, and the EEPROM lines
    // hang off those, so they are not worth disturbing.

    // CPU-only memories: simple dual port is enough.
    rf_bram_be #(.AW(16)) u_ram (
        .clk(clk), .waddr(a[16:1]), .wdata(cpu_dout),
        .wren(cpu_wr && sel_ram && clkena), .be(be), .raddr(a[16:1]), .q(ram_q));

    rf_bram_be #(.AW(13)) u_pfx (
        .clk(clk), .waddr(a[13:1]), .wdata(cpu_dout),
        .wren(cpu_wr && sel_pfx && clkena), .be(be), .raddr(a[13:1]), .q(pfx_q));

    // MB8421: this CPU on port A, the sound CPU on port B (byte lanes)
    rf_bram_tdp #(.AW(10)) u_dpram (
        .clk(clk),
        .a_addr(a[10:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_dpram && clkena),
        .a_be(be), .a_q(dpram_q),
        .b_addr(snd_dp_addr), .b_wdata(snd_dp_wdata), .b_wren(snd_dp_wren),
        .b_be(snd_dp_be), .b_q(snd_dp_q));

    // sound CPU reset, from the two write-only addresses
    wire sel_sndrst_on  = (a[23:8] == 16'hC801);
    wire sel_sndrst_off = (a[23:8] == 16'hC800);
    always_ff @(posedge clk) begin
        if (reset) snd_reset <= 1'b1;
        else if (cpu_wr && clkena) begin
            if (sel_sndrst_on)  snd_reset <= 1'b1;
            if (sel_sndrst_off) snd_reset <= 1'b0;
        end
    end

    // Video-visible memories: true dual port, CPU on A, renderer on B.
    rf_bram_tdp #(.AW(14)) u_pal (
        .clk(clk),
        .a_addr(a[14:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_pal && clkena),
        .a_be(be), .a_q(pal_q),
        .b_addr(v_pal_addr), .b_wdata(16'd0), .b_wren(1'b0), .b_be(2'b00),
        .b_q(v_pal_q));

    rf_bram_tdp #(.AW(15)) u_spr (
        .clk(clk),
        .a_addr(a[15:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_spr && clkena),
        .a_be(be), .a_q(spr_q),
        .b_addr(v_spr_addr), .b_wdata(16'd0), .b_wren(1'b0), .b_be(2'b00),
        .b_q(v_spr_q));

    rf_bram_tdp #(.AW(14)) u_pf (
        .clk(clk),
        .a_addr(a[14:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_pf && clkena),
        .a_be(be), .a_q(pf_q),
        .b_addr(v_pf_addr), .b_wdata(16'd0), .b_wren(1'b0), .b_be(2'b00),
        .b_q(v_pf_q));

    rf_bram_tdp #(.AW(12)) u_text (
        .clk(clk),
        .a_addr(a[12:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_text && clkena),
        .a_be(be), .a_q(text_q),
        .b_addr(v_text_addr), .b_wdata(16'd0), .b_wren(1'b0), .b_be(2'b00),
        .b_q(v_text_q));

    rf_bram_tdp #(.AW(12)) u_char (
        .clk(clk),
        .a_addr(a[12:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_char && clkena),
        .a_be(be), .a_q(char_q),
        .b_addr(v_char_addr), .b_wdata(16'd0), .b_wren(1'b0), .b_be(2'b00),
        .b_q(v_char_q));

    rf_bram_tdp #(.AW(15)) u_line (
        .clk(clk),
        .a_addr(a[15:1]), .a_wdata(cpu_dout), .a_wren(cpu_wr && sel_line && clkena),
        .a_be(be), .a_q(line_q),
        .b_addr(v_line_addr), .b_wdata(16'd0), .b_wren(1'b0), .b_be(2'b00),
        .b_q(v_line_q));

    // pivot RAM stub: reads as zero on both sides (see pivot_wr_cnt above)
    assign pivot_q   = 16'h0000;
    assign v_pivot_q = 16'h0000;

    // ---- read mux --------------------------------------------------------
    // Registered one cycle to line up with the BRAM output, exactly like the
    // spike: the address is presented while clkena is low, the RAM registers
    // it, and the CPU samples data_in on the clkena pulse a cycle later.
    localparam [3:0] SRC_ROM=0, SRC_RAM=1, SRC_PAL=2, SRC_SPR=3, SRC_PF=4,
                     SRC_PFX=5, SRC_TEXT=6, SRC_CHAR=7, SRC_LINE=8,
                     SRC_PIVOT=9, SRC_DPRAM=10, SRC_CTRL=11, SRC_VCTRL=12,
                     SRC_ZERO=13;

    logic [3:0]  src;
    logic [3:0]  src_q;
    logic [15:0] ctrl_hold, vctrl_hold;

    always_comb begin
        if      (sel_rom)   src = SRC_ROM;
        else if (sel_ram)   src = SRC_RAM;
        else if (sel_pal)   src = SRC_PAL;
        else if (sel_spr)   src = SRC_SPR;
        else if (sel_pf)    src = SRC_PF;
        else if (sel_pfx)   src = SRC_PFX;
        else if (sel_text)  src = SRC_TEXT;
        else if (sel_char)  src = SRC_CHAR;
        else if (sel_line)  src = SRC_LINE;
        else if (sel_pivot) src = SRC_PIVOT;
        else if (sel_dpram) src = SRC_DPRAM;
        else if (sel_ctrl)  src = SRC_CTRL;
        else if (sel_vctrl) src = SRC_VCTRL;
        else                src = SRC_ZERO;   // romhi and everything unmapped
    end

    always_ff @(posedge clk) begin
        src_q      <= src;
        ctrl_hold  <= ctrl_q;
        vctrl_hold <= a[4] ? c1[a[3:1]] : c0[a[3:1]];
    end

    always_comb begin
        case (src_q)
            SRC_ROM:   cpu_din = prog_data_lat;
            SRC_RAM:   cpu_din = ram_q;
            SRC_PAL:   cpu_din = pal_q;
            SRC_SPR:   cpu_din = spr_q;
            SRC_PF:    cpu_din = pf_q;
            SRC_PFX:   cpu_din = pfx_q;
            SRC_TEXT:  cpu_din = text_q;
            SRC_CHAR:  cpu_din = char_q;
            SRC_LINE:  cpu_din = line_q;
            SRC_PIVOT: cpu_din = pivot_q;
            SRC_DPRAM: cpu_din = dpram_q;
            SRC_CTRL:  cpu_din = ctrl_hold;
            SRC_VCTRL: cpu_din = vctrl_hold;
            default:   cpu_din = 16'h0000;
        endcase
    end

    // ---- write-stream capture (unchanged -- the MAME oracle) -------------
    wire wr_frozen = wr_count[12];      // 4096 reached
    assign ring_full = ring_ext_sel ? snd_frozen : wr_frozen;

    wire do_write = clkena && (busstate == 2'b11) && !nWr && !wr_frozen;

    wire [15:0] wdat = {nUDS ? 8'h00 : cpu_dout[15:8],
                        nLDS ? 8'h00 : cpu_dout[7:0]};

    wire [31:0] f0 = {wr_hash[30:0], wr_hash[31]} + {16'd0, a[15:0]};
    wire [31:0] f1 = {f0[30:0], f0[31]} + {16'd0, a[23:16], 6'd0, ~nUDS, ~nLDS};
    wire [31:0] f2 = {f1[30:0], f1[31]} + {16'd0, wdat};

    // the ring records this CPU's writes, or the sound CPU's chip writes
    // (ring_ext_*) when the UART option selects the sound ring; the write
    // count and hash (the Phase 1 proof) always follow this CPU
    // the sound ring freezes on ITS 4096th entry (the init sequence, which
    // is deterministic and so the best thing to compare), not the main
    // CPU's, which passed 4096 during boot long before the sound CPU ran
    logic [12:0] snd_wr_count;
    wire         snd_frozen = snd_wr_count[12];
    always_ff @(posedge clk) begin
        if (reset) snd_wr_count <= 13'd0;
        else if (ring_ext_sel && ring_ext_we && !snd_frozen) snd_wr_count <= snd_wr_count + 13'd1;
    end
    wire        ring_adv  = ring_ext_sel ? (ring_ext_we && !snd_frozen) : do_write;
    wire [55:0] ring_wdat = ring_ext_sel ? ring_ext_data
                                         : {~nUDS, ~nLDS, a[23:1], 15'd0, wdat};

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_count <= 32'd0;
            wr_hash  <= 32'd0;
            ring_wptr<= 11'd0;
        end else begin
            if (ring_adv) ring_wptr <= ring_wptr + 11'd1;
            if (do_write) begin
                wr_count  <= wr_count + 32'd1;
                wr_hash   <= f2;
            end
        end
    end

    // 2048 entries, not 4096: a 56-bit x 4096 ring is 24 M10Ks -- more than
    // the whole sprite line-buffer ring -- for a debug feature, and M10K is
    // the binding resource on this device (539 of 553 in B13). Halving it
    // frees 12 and still holds a 2048-write comparison against MAME and a
    // 69 ms audio capture, both far more than any check has needed.
    rf_bram #(.WIDTH(56), .AW(11)) u_ring (
        .clk(clk),
        .waddr(ring_wptr),
        .wdata(ring_wdat),
        .wren(ring_adv),
        .raddr(ring_raddr), .q(ring_rdata)
    );

    // ---- per-region write counters --------------------------------------
    // These are the "is the game actually rendering" readout: a running
    // program rewrites playfield and sprite RAM every frame, a hung one
    // does not. They saturate rather than wrap so a stall is visible.
    always_ff @(posedge clk) begin
        if (reset) begin
            pf_wr_cnt <= 0; spr_wr_cnt <= 0; pal_wr_cnt <= 0; line_wr_cnt <= 0;
            txt_wr_cnt <= 0; pivot_wr_cnt <= 0;
        end else if (cpu_wr) begin
            // the game clears pivot RAM at boot (32768 word writes of zero,
            // seen on build 27230527); a zero written to the zero stub is
            // nothing, so only NON-ZERO writes count against the assumption
            if (sel_pivot && cpu_dout != 16'd0 && pivot_wr_cnt != 16'hFFFF) pivot_wr_cnt <= pivot_wr_cnt + 16'd1;
            if (sel_pf   && pf_wr_cnt   != 16'hFFFF) pf_wr_cnt   <= pf_wr_cnt   + 16'd1;
            if (sel_spr  && spr_wr_cnt  != 16'hFFFF) spr_wr_cnt  <= spr_wr_cnt  + 16'd1;
            if (sel_pal  && pal_wr_cnt  != 16'hFFFF) pal_wr_cnt  <= pal_wr_cnt  + 16'd1;
            if (sel_line && line_wr_cnt != 16'hFFFF) line_wr_cnt <= line_wr_cnt + 16'd1;
            if ((sel_text || sel_char) && txt_wr_cnt != 16'hFFFF)
                txt_wr_cnt <= txt_wr_cnt + 16'd1;
        end
    end

    // ---- fetch monitor ---------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            last_pc  <= 32'd0;
            trap_oor <= 1'b0;
        end else if (clkena && busstate == 2'b00) begin
            last_pc <= cpu_addr;
            if (!sel_rom && !sel_ram) trap_oor <= 1'b1;
        end
    end

endmodule
