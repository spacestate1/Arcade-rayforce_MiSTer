//============================================================================
//  68020 go/no-go spike -- TG68K.C in 020 mode running the real boot code
//
//  THE question this answers: is TG68K.C's "68020 (only some parts - yet)"
//  good enough to execute Ray Force's boot sequence exactly as MAME's 68020
//  does? No simulator is involved: the board runs the CPU against BRAM
//  copies of the real ROM, and the ARCHITECTURAL WRITE STREAM is compared
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
//     0x000000-0x03FFFF  ROM, first 256 KB, captured from the ioctl download
//     0x400000-0x41FFFF  RAM 128 KB (+ mirror at 0x420000)
//     0x440000-0x447FFF  palette RAM 32 KB (boot reads it back)
//     0x4A0000-0x4A001F  control: reads return 0x00 (RMW targets only in the
//                        early window; refine against MAME when a divergence
//                        points here)
//     everything else    writes observed (that is the point), reads 0
//
//  Verdicts on screen: write count, rolling write-stream hash (the offline
//  tool prints the expected value), and the last code-fetch address. A trap
//  flag latches if the CPU fetches outside the modelled ROM -- the honest
//  "this window is over" marker, not an error.
//============================================================================

module rf_cpu_spike
(
    input  logic        clk,           // 53.372 MHz
    input  logic        reset,         // hold high until the download is done

    // ROM capture from the ioctl stream (index 0, bytes 0..0x3FFFF)
    input  logic        dl_wr,
    input  logic [26:0] dl_addr,
    input  logic [15:0] dl_data,       // [7:0]=even byte, [15:8]=odd byte

    // live readouts for the diagnostic screen
    output logic [31:0] wr_count,
    output logic [31:0] wr_hash,
    output logic [31:0] last_pc,
    output logic        trap_oor,      // code fetch left the 256 KB window

    // write-ring dump port (UART side)
    input  logic [11:0] ring_raddr,
    output logic [55:0] ring_rdata,
    output logic [11:0] ring_wptr
);

    // ---- memories --------------------------------------------------------
    // ROM as two byte lanes so the 68020's big-endian 16-bit bus reads
    // {even, odd} directly. The ioctl stream is the region image in address
    // order: dout[7:0] is the EVEN byte, which is the UPPER (big-endian)
    // half of the bus word.
    (* ramstyle = "no_rw_check" *) logic [15:0] rom  [0:131071];  // 256 KB
    (* ramstyle = "no_rw_check" *) logic [15:0] ram  [0:65535];   // 128 KB
    (* ramstyle = "no_rw_check" *) logic [15:0] pal  [0:16383];   // 32 KB

    always_ff @(posedge clk) begin
        if (dl_wr && dl_addr < 27'h40000)
            rom[dl_addr[17:1]] <= {dl_data[7:0], dl_data[15:8]};
    end

    // ---- CPU -------------------------------------------------------------
    logic        clkena;
    logic [31:0] cpu_addr;
    logic [15:0] cpu_din, cpu_dout;
    logic        nWr, nUDS, nLDS;
    logic [1:0]  busstate;              // 00 fetch, 10 read, 11 write, 01 none

    always_ff @(posedge clk) clkena <= reset ? 1'b0 : ~clkena;

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

    // ---- read mux --------------------------------------------------------
    wire [23:0] a        = cpu_addr[23:0];
    wire        sel_rom  = (a < 24'h040000);
    wire        sel_ram  = (a[23:17] == 7'b0100000) || (a[23:17] == 7'b0100001); // 0x400000+mirror
    wire        sel_pal  = (a[23:15] == 9'b010001000);                           // 0x440000-0x447FFF

    logic [15:0] rom_q, ram_q, pal_q;
    logic [1:0]  sel_q;                 // registered with the RAM outputs

    always_ff @(posedge clk) begin
        rom_q <= rom[a[17:1]];
        ram_q <= ram[a[16:1]];
        pal_q <= pal[a[14:1]];
        sel_q <= sel_rom ? 2'd0 : sel_ram ? 2'd1 : sel_pal ? 2'd2 : 2'd3;

        // byte-lane writes
        if (!nWr && busstate == 2'b11 && clkena) begin
            if (sel_ram) begin
                if (!nUDS) ram[a[16:1]][15:8] <= cpu_dout[15:8];
                if (!nLDS) ram[a[16:1]][7:0]  <= cpu_dout[7:0];
            end
            if (sel_pal) begin
                if (!nUDS) pal[a[14:1]][15:8] <= cpu_dout[15:8];
                if (!nLDS) pal[a[14:1]][7:0]  <= cpu_dout[7:0];
            end
        end
    end

    always_comb begin
        case (sel_q)
            2'd0: cpu_din = rom_q;
            2'd1: cpu_din = ram_q;
            2'd2: cpu_din = pal_q;
            default: cpu_din = 16'h0000;   // control regs read as 0 for now
        endcase
    end

    // ---- write-stream capture -------------------------------------------
    // One entry per bus write cycle the kernel actually advanced through
    // (clkena high), which is exactly one entry per 16-bit bus operation.
    // 4096 entries: {lanes[1:0], addr[23:1]+pad, data} -> 56 bits.
    (* ramstyle = "no_rw_check" *) logic [55:0] ring [0:4095];

    wire do_write = clkena && (busstate == 2'b11) && !nWr
                    && !wr_frozen;   // stop at exactly 4096 ops: the screen
                                     // hash is then a fixed, predictable value

    wire wr_frozen = wr_count[12];   // 4096 reached

    // Byte writes mirror the byte onto both bus halves; only the addressed
    // lane is architectural, so hash and ring see lane-MASKED data or the
    // comparison would depend on mirroring behaviour instead of the program.
    wire [15:0] wdat = {nUDS ? 8'h00 : cpu_dout[15:8],
                        nLDS ? 8'h00 : cpu_dout[7:0]};

    // Hash fold, mirrored bit-for-bit by tools/rf_write_compare.py:
    //   h = rotl1(h) + addr[15:0]
    //   h = rotl1(h) + {addr[23:16], 6'b0, UDS, LDS}
    //   h = rotl1(h) + data
    function automatic logic [31:0] fold(input logic [31:0] h, input logic [15:0] w);
        logic [31:0] r;
        r = {h[30:0], h[31]};
        fold = r + {16'd0, w};
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_count <= 32'd0;
            wr_hash  <= 32'd0;
            ring_wptr<= 12'd0;
        end else if (do_write) begin
            ring[ring_wptr] <= {~nUDS, ~nLDS, a[23:1], 15'd0, wdat};
            ring_wptr <= ring_wptr + 12'd1;
            wr_count  <= wr_count + 32'd1;
            wr_hash   <= fold(fold(fold(wr_hash, a[15:0]),
                                   {a[23:16], 6'd0, ~nUDS, ~nLDS}),
                              wdat);
        end
    end

    always_ff @(posedge clk) ring_rdata <= ring[ring_raddr];

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
