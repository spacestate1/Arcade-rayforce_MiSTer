//============================================================================
//  ES5510 host port -- the DSP as the sound 68000 sees it, without the DSP.
//
//  Ray Force's driver talks to the ES5510 at boot: it checks the chip is
//  there by storing a value through the latches (host regs 0-2 -> GPR
//  latch, write-select 0xA0 -> a register, read-select 0x80 -> the latch,
//  read it back), then uploads its program and constants the same way. If
//  those reads do not answer as MAME's es5510.cpp does, the driver loops
//  forever on the presence check (build 27230527 did exactly that, on a
//  stub that aliased the select commands onto latch 0).
//
//  So this is es5510.cpp's host_r/host_w, read_reg/write_reg, with real
//  storage for the GPR file (0xC0 x 24 bits), the instruction memory (0xA0
//  x 48 bits) and the special registers 0xEA-0xFF -- and NO execution: the
//  DSP program never runs, the delay DRAM does not exist (reads give 0),
//  and the audio takes the pump's dry path (a sum) in TaitoF3.sv. Running
//  the DSP is Phase 3 stage 4, if the reverb is ever missed.
//============================================================================

module rf_es5510_host
(
    input  logic        clk,
    input  logic        reset,

    input  logic  [7:0] reg_a,          // host register (address bits [8:1])
    input  logic        we,             // one pulse per bus write
    input  logic  [7:0] wdata,
    output logic  [7:0] rdata           // combinational
);
    logic [23:0] gpr_latch, dil_latch, dol_latch, dadr_latch;
    logic [47:0] instr_latch;
    logic  [2:0] host_control;
    logic        ram_sel, halted;
    logic  [7:0] host_serial;

    (* ramstyle = "MLAB, no_rw_check" *) logic [23:0] gpr   [0:191];
    (* ramstyle = "MLAB, no_rw_check" *) logic [47:0] instr [0:159];

    // special registers 234..251 (read_reg/write_reg); 252-255 are constants
    logic [23:0] spr [0:17];            // index = reg - 234

    function automatic logic [23:0] spr_read(input logic [7:0] r);
        case (r)
            8'd244:  spr_read = dil_latch;                 // DIL when reading
            8'd250, 8'd251: spr_read = {spr[r - 8'd234][7:0], 16'd0};   // ccr/cmr << 16
            8'd252:  spr_read = 24'h00FFFF;                // minus_one
            8'd253:  spr_read = 24'h800000;                // min
            8'd254:  spr_read = 24'h7FFFFF;                // max
            8'd255:  spr_read = 24'd0;                     // zero
            default: spr_read = (r >= 8'd234 && r <= 8'd251) ? spr[r - 8'd234] : 24'd0;
        endcase
    endfunction

    // the write-select value for a special register, as write_reg stores it
    function automatic logic [23:0] spr_store(input logic [7:0] r, input logic [23:0] v);
        case (r)
            8'd234, 8'd235, 8'd236, 8'd237, 8'd238, 8'd239, 8'd240, 8'd241:
                     spr_store = {8'd0, v[23:8]};          // WRITE_REG16: value >> 8, read back << 8
            8'd250, 8'd251: spr_store = {16'd0, v[23:16]}; // ccr/cmr: top byte
            default: spr_store = v;
        endcase
    endfunction

    wire [23:0] gpr_rd = gpr[wdata[7:0]];      // read-select target (data < 0xC0)
    wire [47:0] ins_rd = instr[wdata[7:0]];

    always_ff @(posedge clk) begin
        if (reset) begin
            gpr_latch <= '0; dil_latch <= '0; dol_latch <= '0; dadr_latch <= '0; instr_latch <= '0;
            host_control <= 3'b100;         // "Host Access not OK"
            ram_sel <= 1'b0; halted <= 1'b1; host_serial <= 8'd0;
        end else if (we) begin
            case (reg_a)
                8'h00: gpr_latch[23:16]   <= wdata;
                8'h01: gpr_latch[15:8]    <= wdata;
                8'h02: gpr_latch[7:0]     <= wdata;
                8'h03: instr_latch[47:40] <= wdata;
                8'h04: instr_latch[39:32] <= wdata;
                8'h05: instr_latch[31:24] <= wdata;
                8'h06: instr_latch[23:16] <= wdata;
                8'h07: instr_latch[15:8]  <= wdata;
                8'h08: instr_latch[7:0]   <= wdata;
                8'h0C: dol_latch[23:16]   <= wdata;
                8'h0D: dol_latch[15:8]    <= wdata;
                8'h0E: dol_latch[7:0]     <= wdata;
                8'h0F: begin
                    dadr_latch[23:16] <= wdata;
                    if (ram_sel) dil_latch <= 24'd0;       // dram_r << 8: no DRAM here
                end
                8'h10: dadr_latch[15:8]   <= wdata;
                8'h11: dadr_latch[7:0]    <= wdata;
                8'h12: host_control <= {host_control[2], 1'b0, wdata[0]};   // RAM clear self-clears
                8'h14: ram_sel <= wdata[7];
                8'h18: host_serial <= wdata;
                8'h1F: halted <= 1'b1;
                8'h80: begin                               // read select
                    if (wdata < 8'hA0) instr_latch <= ins_rd;
                    if (wdata < 8'hC0) gpr_latch <= gpr_rd;
                    else if (wdata >= 8'hEA) gpr_latch <= spr_read(wdata);
                end
                8'hA0, 8'hE0: begin                        // write select GPR (+INSTR)
                    if (wdata < 8'hC0) gpr[wdata] <= gpr_latch;
                    else if (wdata >= 8'hEA && wdata <= 8'hFB) spr[wdata - 8'd234] <= spr_store(wdata, gpr_latch);
                    if (reg_a == 8'hE0 && wdata < 8'hA0) instr[wdata] <= instr_latch;
                end
                8'hC0: if (wdata < 8'hA0) instr[wdata] <= instr_latch;
                default: ;
            endcase
        end
    end

    always_comb begin
        case (reg_a)
            8'h00: rdata = gpr_latch[23:16];
            8'h01: rdata = gpr_latch[15:8];
            8'h02: rdata = gpr_latch[7:0];
            8'h03: rdata = instr_latch[47:40];
            8'h04: rdata = instr_latch[39:32];
            8'h05: rdata = instr_latch[31:24];
            8'h06: rdata = instr_latch[23:16];
            8'h07: rdata = instr_latch[15:8];
            8'h08: rdata = instr_latch[7:0];
            8'h09: rdata = dil_latch[23:16];
            8'h0A: rdata = dil_latch[15:8];
            8'h0B: rdata = 8'h00;
            8'h0C: rdata = dol_latch[23:16];
            8'h0D: rdata = dol_latch[15:8];
            8'h0E: rdata = 8'hFF;
            8'h0F: rdata = dadr_latch[23:16];
            8'h10: rdata = dadr_latch[15:8];
            8'h11: rdata = dadr_latch[7:0];
            8'h12: rdata = 8'h00;                          // host control
            8'h16: rdata = 8'h27;                          // PC, "for test purposes"
            default: rdata = 8'h00;
        endcase
    end

endmodule
