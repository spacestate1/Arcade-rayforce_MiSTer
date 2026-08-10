//============================================================================
//  Ray Force skeleton -- F3 video timing + diagnostic test screen
//
//  Timing is the real machine's, from MAME taito_f3.cpp set_raw:
//      pixel clock 26.686 MHz / 4 = 6.6715 MHz  (clk / 8 here, clk = 53.372)
//      H: 432 total, visible 46..365  (320 wide)
//      V: 262 total, visible 24..247  (224 tall)
//      => 58.94 Hz, which a display/scaler will report -- that number on the
//         OSD is itself part of the acceptance test.
//
//  The picture is a diagnostic page, not a game: colour bands, a moving
//  column that proves the frame counter advances, and three live hex
//  readouts of the ROM download (byte count, rolling checksum, index/flags).
//  The checksum is rotate-left-1-then-add per 16-bit word, the same fold the
//  Raiden BIST uses, so the expected value can be computed offline from the
//  same zip.
//============================================================================

module rayforce_video
(
    input  logic        clk,          // 53.372 MHz
    input  logic        reset,

    input  logic        dl_active,
    input  logic        dl_seen,
    input  logic [31:0] dl_bytes,
    input  logic [31:0] dl_sum,
    input  logic  [7:0] dl_index,

    output logic        ce_pix,       // clk / 8
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,        // active high, straight into arcade_video
    output logic        vsync
);

    // ---- counters --------------------------------------------------------
    localparam int H_TOTAL = 432, H_START = 46, H_END = 366;   // 320 visible
    localparam int V_TOTAL = 262, V_START = 24, V_END = 248;   // 224 visible
    localparam int HS_BEG  = 388, HS_WID  = 32;
    localparam int VS_BEG  = 254, VS_WID  = 3;

    logic [2:0] div;
    logic [8:0] hcnt;
    logic [8:0] vcnt;
    logic [7:0] frame;

    always_ff @(posedge clk) begin
        div    <= div + 3'd1;
        ce_pix <= (div == 3'd7);
        if (reset) begin
            div <= '0; hcnt <= '0; vcnt <= '0; frame <= '0;
        end else if (div == 3'd7) begin
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= '0;
                if (vcnt == V_TOTAL - 1) begin
                    vcnt  <= '0;
                    frame <= frame + 8'd1;
                end else vcnt <= vcnt + 9'd1;
            end else hcnt <= hcnt + 9'd1;
        end
    end

    assign hblank = (hcnt < H_START) || (hcnt >= H_END);
    assign vblank = (vcnt < V_START) || (vcnt >= V_END);
    assign hsync  = (hcnt >= HS_BEG) && (hcnt < HS_BEG + HS_WID);
    assign vsync  = (vcnt >= VS_BEG) && (vcnt < VS_BEG + VS_WID);

    wire [8:0] x = hcnt - H_START[8:0];   // 0..319 when visible
    wire [8:0] y = vcnt - V_START[8:0];   // 0..223 when visible

    // ---- 8x8 hex font, 16 glyphs ----------------------------------------
    function automatic logic [7:0] glyph(input logic [3:0] n, input logic [2:0] row);
        case ({n, row})
            {4'h0,3'd0}:glyph=8'h3C; {4'h0,3'd1}:glyph=8'h66; {4'h0,3'd2}:glyph=8'h6E; {4'h0,3'd3}:glyph=8'h76;
            {4'h0,3'd4}:glyph=8'h66; {4'h0,3'd5}:glyph=8'h66; {4'h0,3'd6}:glyph=8'h3C; {4'h0,3'd7}:glyph=8'h00;
            {4'h1,3'd0}:glyph=8'h18; {4'h1,3'd1}:glyph=8'h38; {4'h1,3'd2}:glyph=8'h18; {4'h1,3'd3}:glyph=8'h18;
            {4'h1,3'd4}:glyph=8'h18; {4'h1,3'd5}:glyph=8'h18; {4'h1,3'd6}:glyph=8'h7E; {4'h1,3'd7}:glyph=8'h00;
            {4'h2,3'd0}:glyph=8'h3C; {4'h2,3'd1}:glyph=8'h66; {4'h2,3'd2}:glyph=8'h06; {4'h2,3'd3}:glyph=8'h0C;
            {4'h2,3'd4}:glyph=8'h30; {4'h2,3'd5}:glyph=8'h60; {4'h2,3'd6}:glyph=8'h7E; {4'h2,3'd7}:glyph=8'h00;
            {4'h3,3'd0}:glyph=8'h3C; {4'h3,3'd1}:glyph=8'h66; {4'h3,3'd2}:glyph=8'h06; {4'h3,3'd3}:glyph=8'h1C;
            {4'h3,3'd4}:glyph=8'h06; {4'h3,3'd5}:glyph=8'h66; {4'h3,3'd6}:glyph=8'h3C; {4'h3,3'd7}:glyph=8'h00;
            {4'h4,3'd0}:glyph=8'h0C; {4'h4,3'd1}:glyph=8'h1C; {4'h4,3'd2}:glyph=8'h3C; {4'h4,3'd3}:glyph=8'h6C;
            {4'h4,3'd4}:glyph=8'h7E; {4'h4,3'd5}:glyph=8'h0C; {4'h4,3'd6}:glyph=8'h0C; {4'h4,3'd7}:glyph=8'h00;
            {4'h5,3'd0}:glyph=8'h7E; {4'h5,3'd1}:glyph=8'h60; {4'h5,3'd2}:glyph=8'h7C; {4'h5,3'd3}:glyph=8'h06;
            {4'h5,3'd4}:glyph=8'h06; {4'h5,3'd5}:glyph=8'h66; {4'h5,3'd6}:glyph=8'h3C; {4'h5,3'd7}:glyph=8'h00;
            {4'h6,3'd0}:glyph=8'h3C; {4'h6,3'd1}:glyph=8'h60; {4'h6,3'd2}:glyph=8'h7C; {4'h6,3'd3}:glyph=8'h66;
            {4'h6,3'd4}:glyph=8'h66; {4'h6,3'd5}:glyph=8'h66; {4'h6,3'd6}:glyph=8'h3C; {4'h6,3'd7}:glyph=8'h00;
            {4'h7,3'd0}:glyph=8'h7E; {4'h7,3'd1}:glyph=8'h06; {4'h7,3'd2}:glyph=8'h0C; {4'h7,3'd3}:glyph=8'h18;
            {4'h7,3'd4}:glyph=8'h30; {4'h7,3'd5}:glyph=8'h30; {4'h7,3'd6}:glyph=8'h30; {4'h7,3'd7}:glyph=8'h00;
            {4'h8,3'd0}:glyph=8'h3C; {4'h8,3'd1}:glyph=8'h66; {4'h8,3'd2}:glyph=8'h3C; {4'h8,3'd3}:glyph=8'h66;
            {4'h8,3'd4}:glyph=8'h66; {4'h8,3'd5}:glyph=8'h66; {4'h8,3'd6}:glyph=8'h3C; {4'h8,3'd7}:glyph=8'h00;
            {4'h9,3'd0}:glyph=8'h3C; {4'h9,3'd1}:glyph=8'h66; {4'h9,3'd2}:glyph=8'h66; {4'h9,3'd3}:glyph=8'h3E;
            {4'h9,3'd4}:glyph=8'h06; {4'h9,3'd5}:glyph=8'h0C; {4'h9,3'd6}:glyph=8'h38; {4'h9,3'd7}:glyph=8'h00;
            {4'hA,3'd0}:glyph=8'h18; {4'hA,3'd1}:glyph=8'h3C; {4'hA,3'd2}:glyph=8'h66; {4'hA,3'd3}:glyph=8'h66;
            {4'hA,3'd4}:glyph=8'h7E; {4'hA,3'd5}:glyph=8'h66; {4'hA,3'd6}:glyph=8'h66; {4'hA,3'd7}:glyph=8'h00;
            {4'hB,3'd0}:glyph=8'h7C; {4'hB,3'd1}:glyph=8'h66; {4'hB,3'd2}:glyph=8'h7C; {4'hB,3'd3}:glyph=8'h66;
            {4'hB,3'd4}:glyph=8'h66; {4'hB,3'd5}:glyph=8'h66; {4'hB,3'd6}:glyph=8'h7C; {4'hB,3'd7}:glyph=8'h00;
            {4'hC,3'd0}:glyph=8'h3C; {4'hC,3'd1}:glyph=8'h66; {4'hC,3'd2}:glyph=8'h60; {4'hC,3'd3}:glyph=8'h60;
            {4'hC,3'd4}:glyph=8'h60; {4'hC,3'd5}:glyph=8'h66; {4'hC,3'd6}:glyph=8'h3C; {4'hC,3'd7}:glyph=8'h00;
            {4'hD,3'd0}:glyph=8'h78; {4'hD,3'd1}:glyph=8'h6C; {4'hD,3'd2}:glyph=8'h66; {4'hD,3'd3}:glyph=8'h66;
            {4'hD,3'd4}:glyph=8'h66; {4'hD,3'd5}:glyph=8'h6C; {4'hD,3'd6}:glyph=8'h78; {4'hD,3'd7}:glyph=8'h00;
            {4'hE,3'd0}:glyph=8'h7E; {4'hE,3'd1}:glyph=8'h60; {4'hE,3'd2}:glyph=8'h7C; {4'hE,3'd3}:glyph=8'h60;
            {4'hE,3'd4}:glyph=8'h60; {4'hE,3'd5}:glyph=8'h60; {4'hE,3'd6}:glyph=8'h7E; {4'hE,3'd7}:glyph=8'h00;
            {4'hF,3'd0}:glyph=8'h7E; {4'hF,3'd1}:glyph=8'h60; {4'hF,3'd2}:glyph=8'h7C; {4'hF,3'd3}:glyph=8'h60;
            {4'hF,3'd4}:glyph=8'h60; {4'hF,3'd5}:glyph=8'h60; {4'hF,3'd6}:glyph=8'h60; {4'hF,3'd7}:glyph=8'h00;
            default: glyph = 8'h00;
        endcase
    endfunction

    // ---- three hex readouts, 8 digits each, glyphs doubled to 16x16 ------
    localparam int RX = 96;     // left edge of the readout block
    localparam int RY = 56;     // top of row 0
    localparam int RP = 32;     // row pitch

    wire [31:0] row_val [0:2];
    assign row_val[0] = dl_bytes;
    assign row_val[1] = dl_sum;
    assign row_val[2] = {8'h00, dl_index, 6'd0, dl_seen, dl_active};

    logic       text_on;
    always_comb begin
        text_on = 1'b0;
        for (int rrow = 0; rrow < 3; rrow++) begin
            automatic int ty = RY + rrow * RP;
            if (y >= ty && y < ty + 16 && x >= RX && x < RX + 128) begin
                automatic logic [8:0] cx = x - RX[8:0];
                automatic logic [3:0] nib = row_val[rrow] >> (4 * (7 - cx[8:4]));
                automatic logic [7:0] bits = glyph(nib, 3'((y - ty) >> 1));
                if (bits[3'd7 - cx[3:1]]) text_on = 1'b1;
            end
        end
    end

    // ---- compose ---------------------------------------------------------
    // Colour bands top and bottom, dark field behind the text, and a moving
    // column so a frozen frame is distinguishable from a live one.
    always_comb begin
        logic [7:0] br, bg, bb;
        // bands: 8 colours across the top 32 and bottom 32 lines
        if (y < 32 || y >= 192) begin
            br = {8{x[7]}} | 8'h20;
            bg = {8{x[6]}} | 8'h20;
            bb = {8{x[5]}} | 8'h20;
        end else begin
            br = 8'h10; bg = 8'h18; bb = 8'h28;         // dark blue field
        end
        // life column sweeping the middle band
        if (y >= 176 && y < 190 && x[8:1] == frame) begin
            br = 8'hFF; bg = 8'hA0; bb = 8'h00;
        end
        // download activity: left margin strip lights while ioctl writes come in
        if (dl_active && x < 8) begin
            br = 8'h00; bg = 8'hFF; bb = 8'h00;
        end
        if (text_on) begin
            br = 8'hFF; bg = 8'hFF; bb = 8'hFF;
        end
        r = (hblank | vblank) ? 8'h00 : br;
        g = (hblank | vblank) ? 8'h00 : bg;
        b = (hblank | vblank) ? 8'h00 : bb;
    end

endmodule
