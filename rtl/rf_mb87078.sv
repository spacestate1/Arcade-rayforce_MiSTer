//============================================================================
//  MB87078 -- the volume control on the EN board, as taito_en.cpp uses it.
//
//  Two writes from the 68000 (en_volume_w -> data_w(offset ^ 1, byte)): the
//  control byte selects a channel and carries the EN/C0/C32 bits, the data
//  byte the 6-bit attenuation. mb87077.cpp: gain index = 65 (mute) if EN=0,
//  64 (-32 dB) if C32, 0 (0 dB) if C0, else ~data & 0x3f, in 0.5 dB steps.
//  taito_en's callback applies channel 2's gain to every LEFT output of the
//  ES5505 and channel 3's to every RIGHT one (channels 0/1 do nothing), as
//  percent / 32 -- i.e. x3.125 at 0 dB, which the coefficient table folds
//  in together with the route gains (0.18) and the pump's 0.5, and the
//  20-bit -> 16-bit scaling. Ray Force uses two settings: -7.5 dB (data
//  0x30) and -31.5 dB (data 0x00, the fade).
//
//  The multiply is on the 23-bit sum of the four pairs, which is the same
//  as gaining each pair (one gain per side).
//============================================================================

module rf_mb87078
(
    input  logic        clk,
    input  logic        reset,

    input  logic        we,             // rf_sound_main's vl_we
    input  logic        offset,         // data_w's offset: 1 = control, 0 = data
    input  logic  [7:0] data,

    input  logic        in_valid,       // one 8-channel sample
    input  logic signed [22:0] in_l,    // sum of the four left channels
    input  logic signed [22:0] in_r,

    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r
);
    logic [4:0] ctl;
    logic [8:0] latch [0:3];            // C32, C0, EN, data[5:0]

    function automatic logic [6:0] gain_index(input logic [8:0] l);
        if (!l[6])      gain_index = 7'd65;
        else if (l[8])  gain_index = 7'd64;
        else if (l[7])  gain_index = 7'd0;
        else            gain_index = {1'b0, ~l[5:0]};
    endfunction

    function automatic logic [15:0] coef(input logic [6:0] i);
        logic [15:0] c;
        case (i)
            7'd0: c = 16'd576;
            7'd1: c = 16'd544;
            7'd2: c = 16'd513;
            7'd3: c = 16'd485;
            7'd4: c = 16'd458;
            7'd5: c = 16'd432;
            7'd6: c = 16'd408;
            7'd7: c = 16'd385;
            7'd8: c = 16'd363;
            7'd9: c = 16'd343;
            7'd10: c = 16'd324;
            7'd11: c = 16'd306;
            7'd12: c = 16'd289;
            7'd13: c = 16'd273;
            7'd14: c = 16'd257;
            7'd15: c = 16'd243;
            7'd16: c = 16'd229;
            7'd17: c = 16'd216;
            7'd18: c = 16'd204;
            7'd19: c = 16'd193;
            7'd20: c = 16'd182;
            7'd21: c = 16'd172;
            7'd22: c = 16'd162;
            7'd23: c = 16'd153;
            7'd24: c = 16'd145;
            7'd25: c = 16'd137;
            7'd26: c = 16'd129;
            7'd27: c = 16'd122;
            7'd28: c = 16'd115;
            7'd29: c = 16'd108;
            7'd30: c = 16'd102;
            7'd31: c = 16'd97;
            7'd32: c = 16'd91;
            7'd33: c = 16'd86;
            7'd34: c = 16'd81;
            7'd35: c = 16'd77;
            7'd36: c = 16'd73;
            7'd37: c = 16'd68;
            7'd38: c = 16'd65;
            7'd39: c = 16'd61;
            7'd40: c = 16'd58;
            7'd41: c = 16'd54;
            7'd42: c = 16'd51;
            7'd43: c = 16'd48;
            7'd44: c = 16'd46;
            7'd45: c = 16'd43;
            7'd46: c = 16'd41;
            7'd47: c = 16'd38;
            7'd48: c = 16'd36;
            7'd49: c = 16'd34;
            7'd50: c = 16'd32;
            7'd51: c = 16'd31;
            7'd52: c = 16'd29;
            7'd53: c = 16'd27;
            7'd54: c = 16'd26;
            7'd55: c = 16'd24;
            7'd56: c = 16'd23;
            7'd57: c = 16'd22;
            7'd58: c = 16'd20;
            7'd59: c = 16'd19;
            7'd60: c = 16'd18;
            7'd61: c = 16'd17;
            7'd62: c = 16'd16;
            7'd63: c = 16'd15;
            7'd64: c = 16'd14;
            7'd65: c = 16'd0;
            default: c = 16'd0;
        endcase
        coef = c;
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            ctl <= 5'd0;
            for (int i = 0; i < 4; i++) latch[i] <= 9'h07F;   // reset: all enabled, 0 dB
        end else if (we) begin
            if (offset) ctl <= data[4:0];
            else        latch[ctl[1:0]] <= {ctl[4:2], data[5:0]};
        end
    end

    wire [15:0] g_l = coef(gain_index(latch[2]));
    wire [15:0] g_r = coef(gain_index(latch[3]));

    logic signed [39:0] p_l, p_r;
    always_ff @(posedge clk) if (in_valid) begin
        p_l <= 40'(in_l) * 40'($signed({1'b0, g_l}));
        p_r <= 40'(in_r) * 40'($signed({1'b0, g_r}));
    end
    wire signed [24:0] s_l = p_l >>> 15;
    wire signed [24:0] s_r = p_r >>> 15;
    assign out_l = (s_l > 25'sd32767) ? 16'sd32767 : (s_l < -25'sd32768) ? -16'sd32768 : s_l[15:0];
    assign out_r = (s_r > 25'sd32767) ? 16'sd32767 : (s_r < -25'sd32768) ? -16'sd32768 : s_r[15:0];

endmodule
