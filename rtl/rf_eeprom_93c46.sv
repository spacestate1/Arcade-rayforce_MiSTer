//============================================================================
//  93C46 serial EEPROM, 16-bit organisation (64 words x 16 bits)
//
//  The F3 board wires one of these to the control port at 0x4a0010: the CPU
//  drives CS/CLK/DI through the low byte there and reads DO back in bit 0 of
//  every control-port longword (taito_f3.cpp EEPROMOUT / EEPROMIN).
//
//  Why a real implementation and not a stub: the boot code reads the EEPROM
//  before it draws anything. A stub that answers wrong can send the program
//  into its "bad settings" path, or into a retry loop, and the failure looks
//  exactly like a broken CPU or a broken video chip. Sixty lines here removes
//  a whole class of false leads later.
//
//  Protocol (Microchip 93C46, ORG=1):
//      CS high, then on each rising CLK the chip shifts DI in.
//      A command is a leading 1, two opcode bits, six address bits:
//        10 aaaaaa           READ   -> DO = 0 (dummy) then 16 data bits
//        01 aaaaaa dddd...   WRITE  (needs a prior EWEN)
//        11 aaaaaa           ERASE  (needs a prior EWEN)
//        00 00xxxx           EWDS   write disable
//        00 01xxxx           WRAL   write all
//        00 10xxxx           ERAL   erase all
//        00 11xxxx           EWEN   write enable
//      DO is high when idle/ready, which is what the ready poll after a
//      write looks for.
//
//  NVRAM (2026-08-28): the array is loaded from and saved to MiSTer's
//  config/nvram/<mra>.nvm through hps_io's ioctl channel on index 254 (the
//  MRA's <nvram index="254" size="128"/>). Two ports for that:
//
//    ld_wr / ld_addr / ld_data   the load, during the download
//    sv_addr -> sv_data          the save, read back word by word
//    wrote                       a pulse whenever the GAME changes a word,
//                                which is what asks MiSTer for a save
//
//  The array is NOT cleared on reset any more. It could not be: the load
//  arrives while the core is held in reset by the download, so a reset
//  clear would wipe exactly the data being loaded. It powers up erased
//  (the initial block) and MiSTer's default file is FF FF anyway.
//============================================================================

module rf_eeprom_93c46
(
    input  logic        clk,
    input  logic        reset,

    input  logic        cs,
    input  logic        sk,          // clock, sampled for a rising edge here
    input  logic        di,
    output logic        do_out,

    // ---- NVRAM (hps_io ioctl index 254) ---------------------------------
    input  logic        ld_wr,       // load: one word from the download
    input  logic  [5:0] ld_addr,
    input  logic [15:0] ld_data,
    input  logic  [5:0] sv_addr,     // save: read back for the upload
    output logic [15:0] sv_data,
    output logic        wrote        // the game changed a word (pulse)
);
    assign sv_data = mem[sv_addr];

    /* verilator lint_off IMPLICITSTATIC */
    // Power-on value, once. The narrow documented exception (as in
    // rf_sdram.sv): there is no reset clear -- see the header.
    logic [15:0] mem [0:63] = '{default: 16'hFFFF};
    /* verilator lint_on IMPLICITSTATIC */
    logic [15:0] sr;                 // shift register, command then data
    logic  [5:0] bitcnt;
    logic        wen;                // set by EWEN, cleared by EWDS
    logic        cs_d, sk_d;
    logic        shifting_out;
    logic [16:0] dout_sr;            // {dummy 0, data}: READ emits a 0 first
    logic  [4:0] out_cnt;
    logic  [5:0] cmd_addr;
    logic  [1:0] cmd_op;
    logic        have_cmd;

    wire sk_rise = sk && !sk_d;
    wire cs_rise = cs && !cs_d;

    // The bit arriving on this clock is not in `sr` yet, so the completed
    // command / data word is the register plus that bit. Kept as wires, not
    // `automatic` locals: quartus_map 17.0 is unreliable with procedural
    // automatics in this design (see the note in rayforce_video.sv).
    wire [7:0]  cmd_w  = {sr[6:0],  di};
    wire [15:0] data_w = {sr[14:0], di};

    // A READ answers with a dummy 0 on the clock after the last address bit,
    // THEN the 16 data bits MSB first (93C46 datasheet, and eepromser.cpp).
    // Without the dummy the whole word arrives one bit early and reads back
    // rotated -- which the boot code would treat as corrupt settings.
    assign do_out = shifting_out ? dout_sr[16] : 1'b1;

    integer i;

    always_ff @(posedge clk) begin
        cs_d  <= cs;
        sk_d  <= sk;
        wrote <= 1'b0;

        if (reset) begin
            bitcnt       <= 6'd0;
            wen          <= 1'b0;
            have_cmd     <= 1'b0;
            shifting_out <= 1'b0;
        end else begin
            if (!cs) begin
                // deselect ends whatever was in flight
                bitcnt       <= 6'd0;
                have_cmd     <= 1'b0;
                shifting_out <= 1'b0;
            end else begin
                if (cs_rise) begin
                    bitcnt       <= 6'd0;
                    have_cmd     <= 1'b0;
                    shifting_out <= 1'b0;
                end

                if (sk_rise) begin
                    if (shifting_out) begin
                        // READ: one bit per clock, MSB first, then it wraps
                        dout_sr <= {dout_sr[15:0], 1'b0};
                    end else if (!have_cmd) begin
                        // hunt for the leading 1, then take 8 more bits
                        if (bitcnt == 6'd0) begin
                            if (di) bitcnt <= 6'd1;
                        end else begin
                            sr     <= {sr[14:0], di};
                            bitcnt <= bitcnt + 6'd1;
                            if (bitcnt == 6'd8) begin
                                // sr now holds op[1:0], addr[5:0] in bits 7:0
                                cmd_op   <= cmd_w[7:6];
                                cmd_addr <= cmd_w[5:0];
                                have_cmd <= 1'b1;
                                bitcnt   <= 6'd0;
                                case (cmd_w[7:6])
                                    2'b10: begin                 // READ
                                        dout_sr      <= {1'b0, mem[cmd_w[5:0]]};
                                        shifting_out <= 1'b1;
                                    end
                                    2'b11: begin                 // ERASE
                                        if (wen) begin
                                            mem[cmd_w[5:0]] <= 16'hFFFF;
                                            wrote <= 1'b1;
                                        end
                                    end
                                    2'b00: case (cmd_w[5:4])     // control group
                                        2'b00: wen <= 1'b0;      // EWDS
                                        2'b11: wen <= 1'b1;      // EWEN
                                        2'b10: if (wen) begin    // ERAL
                                            for (i = 0; i < 64; i = i + 1) mem[i] <= 16'hFFFF;
                                            wrote <= 1'b1;
                                        end
                                        default: ;               // WRAL handled on data
                                    endcase
                                    default: ;                   // WRITE: data follows
                                endcase
                            end
                        end
                    end else begin
                        // command taken; WRITE/WRAL clock in 16 data bits
                        sr     <= {sr[14:0], di};
                        bitcnt <= bitcnt + 6'd1;
                        if (bitcnt == 6'd15) begin
                            if (wen) begin
                                if (cmd_op == 2'b01) begin
                                    mem[cmd_addr] <= data_w;
                                    wrote <= 1'b1;
                                end else if (cmd_op == 2'b00 && cmd_addr[5:4] == 2'b01) begin
                                    for (i = 0; i < 64; i = i + 1) mem[i] <= data_w;
                                    wrote <= 1'b1;
                                end
                            end
                            bitcnt   <= 6'd0;
                            have_cmd <= 1'b0;
                        end
                    end
                end
            end
        end

        // The NVRAM load, last in the process so it wins: it only happens
        // while the core is held in reset by the download, when nothing
        // else drives the array.
        if (ld_wr) mem[ld_addr] <= ld_data;
    end

endmodule
