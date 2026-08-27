//============================================================================
//  68020 go/no-go spike -- TG68K.C in 020 mode running the real boot code
//
//  THE question this answers: is TG68K.C's "68020 (only some parts - yet)"
//  good enough to execute Ray Force's boot sequence exactly as MAME's 68020
//  does? No simulator is involved: the board runs the CPU against the real
//  ROM image in SDRAM, and the ARCHITECTURAL WRITE STREAM is compared
//  against MAME's, captured with a debugger watchpoint log.
//
//  Why writes and not PCs: TG68K prefetches, so its fetch addresses lead the
//  instruction stream and cannot be compared 1:1 against a trace. The
//  sequence of data writes (address, lanes, data) is prefetch-independent --
//  two correct 68020s must produce the identical stream from identical
//  inputs.
//
//  Memory model, from a MAME access profile of the first emulated second
//  (99.998% of early data reads are ROM; VRAM is written long before it is
//  read; palette IS read back early):
//     0x000000-0x0FFFFF  ROM, full 1 MB maincpu region, in SDRAM via
//                        rf_prog_bus (Phase 1); fetch/read wait-stated
//     0x400000-0x41FFFF  RAM 128 KB (+ mirror at 0x420000)
//     0x440000-0x447FFF  palette RAM 32 KB (boot reads it back)
//     0x4A0000-0x4A001F  control: reads return 0x00 (RMW targets only in the
//                        early window; refine against MAME when a divergence
//                        points here)
//     everything else    writes observed (that is the point), reads 0
//
//  Verdicts on screen: write count, rolling write-stream hash (the offline
//  tool prints the expected value), and the last code-fetch address. A trap
//  flag latches if the CPU fetches outside the modelled ROM/RAM -- the honest
//  "this window is over" marker, not an error.
//
//  BRAMs are EXPLICIT altsyncram instances (rf_bram*), not inferred arrays.
//  Inferred 128K-deep byte-sliced arrays sent quartus_map 17.0 past 6.6 GB
//  of memory without terminating (2026-08-10, Propcycle); the explicit
//  instances make the mapping a lookup instead of a search.
//============================================================================

module rf_cpu_spike
(
    input  logic        clk,           // 53.372 MHz
    input  logic        reset,         // hold high until the download is done

    // program ROM read port (rf_prog_bus client, line-cached SDRAM fetch)
    output logic [21:1] prog_addr,
    output logic        prog_req,      // one-cycle pulse
    input  logic [15:0] prog_data,
    input  logic        prog_valid,    // one-cycle pulse when data is good

    // live readouts for the diagnostic screen
    output logic [31:0] wr_count,
    output logic [31:0] wr_hash,
    output logic [31:0] last_pc,
    output logic        trap_oor,      // code fetch left the ROM/RAM windows

    // write-ring dump port (UART side)
    input  logic [11:0] ring_raddr,
    output logic [55:0] ring_rdata,
    output logic [11:0] ring_wptr,
    output logic        ring_full     // 4096 entries captured (wptr wrapped)
);

    // ---- CPU -------------------------------------------------------------
    logic        clkena;
    logic [31:0] cpu_addr;
    logic [15:0] cpu_din, cpu_dout;
    logic        nWr, nUDS, nLDS;
    logic [1:0]  busstate;              // 00 fetch, 10 read, 11 write, 01 none

    // Wait-state engine (ported from Propcycle's propcycle_main.sv): the CPU
    // runs 2-cycle ops for BRAM/stub targets; a ROM access (fetch or data
    // read) issues one prog_bus request and holds clkena low until the data
    // comes back. THE BOOT-BUG RULE: `a` is sampled ONLY while clkena is low
    // -- once clkena pulses, addr_out belongs to the next op.
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
            end else if (!clkena) begin
                // fresh-address cycle: `a` belongs to the op about to run
                if (sel_rom && (busstate == 2'b00 || busstate == 2'b10)) begin
                    prog_addr <= a[21:1];
                    prog_req  <= 1'b1;
                    rom_wait  <= 1'b1;
                end else begin
                    clkena <= 1'b1;        // BRAM/stub/idle: 2-cycle op
                end
            end
            // clkena high: `a` is stale, do nothing (the boot-bug rule)
        end
    end

    // prog_valid is a pulse; latch it (and the data) until consumed
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
        .IPL(3'b111),                   // no interrupts in the spike window
        .IPL_autovector(1'b0),
        .berr(1'b0),
        .CPU(2'b11),                    // 68020 mode -- the thing under test
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
        .VBR_out()
    );

    // ---- address decode --------------------------------------------------
    wire [23:0] a        = cpu_addr[23:0];
    wire        sel_rom  = (a < 24'h100000);   // full 1 MB maincpu, in SDRAM
    wire        sel_ram  = (a[23:17] == 7'b0100000) || (a[23:17] == 7'b0100001); // 0x400000+mirror
    wire        sel_pal  = (a[23:15] == 9'b010001000);                           // 0x440000-0x447FFF

    wire cpu_wr = !nWr && (busstate == 2'b11) && clkena;

    // ---- memories --------------------------------------------------------
    // RAM and palette stay in explicit BRAMs; the ROM is in SDRAM and comes
    // back through the prog_bus wait-state engine above.
    wire [15:0] ram_q, pal_q;

    rf_bram_be #(.AW(16)) u_ram (
        .clk(clk),
        .waddr(a[16:1]), .wdata(cpu_dout),
        .wren(cpu_wr && sel_ram), .be({~nUDS, ~nLDS}),
        .raddr(a[16:1]), .q(ram_q)
    );

    rf_bram_be #(.AW(14)) u_pal (
        .clk(clk),
        .waddr(a[14:1]), .wdata(cpu_dout),
        .wren(cpu_wr && sel_pal), .be({~nUDS, ~nLDS}),
        .raddr(a[14:1]), .q(pal_q)
    );

    // ---- read mux --------------------------------------------------------
    logic [1:0]  sel_q;                 // registered with the RAM outputs

    always_ff @(posedge clk) begin
        sel_q <= sel_rom ? 2'd0 : sel_ram ? 2'd1 : sel_pal ? 2'd2 : 2'd3;
    end

    always_comb begin
        case (sel_q)
            2'd0: cpu_din = prog_data_lat;   // ROM word from the prog_bus
            2'd1: cpu_din = ram_q;
            2'd2: cpu_din = pal_q;
            default: cpu_din = 16'h0000;   // control regs read as 0 for now
        endcase
    end

    // ---- write-stream capture -------------------------------------------
    // One entry per bus write cycle the kernel actually advanced through
    // (clkena high), which is exactly one entry per 16-bit bus operation.
    // 4096 entries: {lanes[1:0], addr[23:1]+pad, data} -> 56 bits.

    wire wr_frozen = wr_count[12];   // 4096 reached

    // At exactly 4096 writes the 12-bit ring_wptr wraps to 0; ring_full is
    // how the UART dumper tells "wrapped and full" apart from "empty".
    assign ring_full = wr_frozen;

    wire do_write = clkena && (busstate == 2'b11) && !nWr
                    && !wr_frozen;   // stop at exactly 4096 ops: the screen
                                     // hash is then a fixed, predictable value

    // Byte writes mirror the byte onto both bus halves; only the addressed
    // lane is architectural, so hash and ring see lane-MASKED data or the
    // comparison would depend on mirroring behaviour instead of the program.
    wire [15:0] wdat = {nUDS ? 8'h00 : cpu_dout[15:8],
                        nLDS ? 8'h00 : cpu_dout[7:0]};

    // Hash fold, mirrored bit-for-bit by tools/rf_write_compare.py:
    //   h = rotl1(h) + addr[15:0]
    //   h = rotl1(h) + {addr[23:16], 6'b0, UDS, LDS}
    //   h = rotl1(h) + data
    // Written as explicit wires, not a function: Quartus 17.0's quartus_map
    // crashes outright ("ended unexpectedly") elaborating nested automatic
    // function calls here. Same toolchain family as the known "cannot index
    // a function call" limitation.
    wire [31:0] f0 = {wr_hash[30:0], wr_hash[31]} + {16'd0, a[15:0]};
    wire [31:0] f1 = {f0[30:0], f0[31]} + {16'd0, a[23:16], 6'd0, ~nUDS, ~nLDS};
    wire [31:0] f2 = {f1[30:0], f1[31]} + {16'd0, wdat};

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_count <= 32'd0;
            wr_hash  <= 32'd0;
            ring_wptr<= 12'd0;
        end else if (do_write) begin
            ring_wptr <= ring_wptr + 12'd1;
            wr_count  <= wr_count + 32'd1;
            wr_hash   <= f2;
        end
    end

    rf_bram #(.WIDTH(56), .AW(12)) u_ring (
        .clk(clk),
        .waddr(ring_wptr),
        .wdata({~nUDS, ~nLDS, a[23:1], 15'd0, wdat}),
        .wren(do_write),
        .raddr(ring_raddr), .q(ring_rdata)
    );

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
