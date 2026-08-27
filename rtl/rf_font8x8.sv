//==========================================================================
//  Ray Force - 8x8 text font for the core self-test page
//
//  GENERATED FILE -- do not edit by hand.
//  Produced by tools/make_font.py from /usr/share/kbd/consolefonts/cp850-8x8.psfu.gz
//
//  Covers ASCII 0x20-0x5F (space, punctuation, digits, uppercase), which
//  is everything the self-test page prints. Address is {code, row} where
//  code = ascii - 0x20. Rows are MSB-left, so pixel x is bits[7 - x].
//==========================================================================

module rf_font8x8 (
    input  logic       clk,
    input  logic [5:0] code,   // ascii - 0x20
    input  logic [2:0] row,
    output logic [7:0] bits
);

    logic [7:0] rom [0:511];

    initial begin
        // 0x20 space
        rom[  0] = 8'h00;
        rom[  1] = 8'h00;
        rom[  2] = 8'h00;
        rom[  3] = 8'h00;
        rom[  4] = 8'h00;
        rom[  5] = 8'h00;
        rom[  6] = 8'h00;
        rom[  7] = 8'h00;
        // 0x21 !
        rom[  8] = 8'h18;
        rom[  9] = 8'h3C;
        rom[ 10] = 8'h3C;
        rom[ 11] = 8'h18;
        rom[ 12] = 8'h18;
        rom[ 13] = 8'h00;
        rom[ 14] = 8'h18;
        rom[ 15] = 8'h00;
        // 0x22 "
        rom[ 16] = 8'h66;
        rom[ 17] = 8'h66;
        rom[ 18] = 8'h24;
        rom[ 19] = 8'h00;
        rom[ 20] = 8'h00;
        rom[ 21] = 8'h00;
        rom[ 22] = 8'h00;
        rom[ 23] = 8'h00;
        // 0x23 #
        rom[ 24] = 8'h6C;
        rom[ 25] = 8'h6C;
        rom[ 26] = 8'hFE;
        rom[ 27] = 8'h6C;
        rom[ 28] = 8'hFE;
        rom[ 29] = 8'h6C;
        rom[ 30] = 8'h6C;
        rom[ 31] = 8'h00;
        // 0x24 $
        rom[ 32] = 8'h18;
        rom[ 33] = 8'h3E;
        rom[ 34] = 8'h60;
        rom[ 35] = 8'h3C;
        rom[ 36] = 8'h06;
        rom[ 37] = 8'h7C;
        rom[ 38] = 8'h18;
        rom[ 39] = 8'h00;
        // 0x25 %
        rom[ 40] = 8'h00;
        rom[ 41] = 8'hC6;
        rom[ 42] = 8'hCC;
        rom[ 43] = 8'h18;
        rom[ 44] = 8'h30;
        rom[ 45] = 8'h66;
        rom[ 46] = 8'hC6;
        rom[ 47] = 8'h00;
        // 0x26 &
        rom[ 48] = 8'h38;
        rom[ 49] = 8'h6C;
        rom[ 50] = 8'h38;
        rom[ 51] = 8'h76;
        rom[ 52] = 8'hDC;
        rom[ 53] = 8'hCC;
        rom[ 54] = 8'h76;
        rom[ 55] = 8'h00;
        // 0x27 '
        rom[ 56] = 8'h18;
        rom[ 57] = 8'h18;
        rom[ 58] = 8'h30;
        rom[ 59] = 8'h00;
        rom[ 60] = 8'h00;
        rom[ 61] = 8'h00;
        rom[ 62] = 8'h00;
        rom[ 63] = 8'h00;
        // 0x28 (
        rom[ 64] = 8'h0C;
        rom[ 65] = 8'h18;
        rom[ 66] = 8'h30;
        rom[ 67] = 8'h30;
        rom[ 68] = 8'h30;
        rom[ 69] = 8'h18;
        rom[ 70] = 8'h0C;
        rom[ 71] = 8'h00;
        // 0x29 )
        rom[ 72] = 8'h30;
        rom[ 73] = 8'h18;
        rom[ 74] = 8'h0C;
        rom[ 75] = 8'h0C;
        rom[ 76] = 8'h0C;
        rom[ 77] = 8'h18;
        rom[ 78] = 8'h30;
        rom[ 79] = 8'h00;
        // 0x2A *
        rom[ 80] = 8'h00;
        rom[ 81] = 8'h66;
        rom[ 82] = 8'h3C;
        rom[ 83] = 8'hFF;
        rom[ 84] = 8'h3C;
        rom[ 85] = 8'h66;
        rom[ 86] = 8'h00;
        rom[ 87] = 8'h00;
        // 0x2B +
        rom[ 88] = 8'h00;
        rom[ 89] = 8'h18;
        rom[ 90] = 8'h18;
        rom[ 91] = 8'h7E;
        rom[ 92] = 8'h18;
        rom[ 93] = 8'h18;
        rom[ 94] = 8'h00;
        rom[ 95] = 8'h00;
        // 0x2C ,
        rom[ 96] = 8'h00;
        rom[ 97] = 8'h00;
        rom[ 98] = 8'h00;
        rom[ 99] = 8'h00;
        rom[100] = 8'h00;
        rom[101] = 8'h18;
        rom[102] = 8'h18;
        rom[103] = 8'h30;
        // 0x2D -
        rom[104] = 8'h00;
        rom[105] = 8'h00;
        rom[106] = 8'h00;
        rom[107] = 8'h7E;
        rom[108] = 8'h00;
        rom[109] = 8'h00;
        rom[110] = 8'h00;
        rom[111] = 8'h00;
        // 0x2E .
        rom[112] = 8'h00;
        rom[113] = 8'h00;
        rom[114] = 8'h00;
        rom[115] = 8'h00;
        rom[116] = 8'h00;
        rom[117] = 8'h18;
        rom[118] = 8'h18;
        rom[119] = 8'h00;
        // 0x2F /
        rom[120] = 8'h06;
        rom[121] = 8'h0C;
        rom[122] = 8'h18;
        rom[123] = 8'h30;
        rom[124] = 8'h60;
        rom[125] = 8'hC0;
        rom[126] = 8'h80;
        rom[127] = 8'h00;
        // 0x30 0
        rom[128] = 8'h38;
        rom[129] = 8'h6C;
        rom[130] = 8'hC6;
        rom[131] = 8'hD6;
        rom[132] = 8'hC6;
        rom[133] = 8'h6C;
        rom[134] = 8'h38;
        rom[135] = 8'h00;
        // 0x31 1
        rom[136] = 8'h18;
        rom[137] = 8'h38;
        rom[138] = 8'h18;
        rom[139] = 8'h18;
        rom[140] = 8'h18;
        rom[141] = 8'h18;
        rom[142] = 8'h7E;
        rom[143] = 8'h00;
        // 0x32 2
        rom[144] = 8'h7C;
        rom[145] = 8'hC6;
        rom[146] = 8'h06;
        rom[147] = 8'h1C;
        rom[148] = 8'h30;
        rom[149] = 8'h66;
        rom[150] = 8'hFE;
        rom[151] = 8'h00;
        // 0x33 3
        rom[152] = 8'h7C;
        rom[153] = 8'hC6;
        rom[154] = 8'h06;
        rom[155] = 8'h3C;
        rom[156] = 8'h06;
        rom[157] = 8'hC6;
        rom[158] = 8'h7C;
        rom[159] = 8'h00;
        // 0x34 4
        rom[160] = 8'h1C;
        rom[161] = 8'h3C;
        rom[162] = 8'h6C;
        rom[163] = 8'hCC;
        rom[164] = 8'hFE;
        rom[165] = 8'h0C;
        rom[166] = 8'h1E;
        rom[167] = 8'h00;
        // 0x35 5
        rom[168] = 8'hFE;
        rom[169] = 8'hC0;
        rom[170] = 8'hC0;
        rom[171] = 8'hFC;
        rom[172] = 8'h06;
        rom[173] = 8'hC6;
        rom[174] = 8'h7C;
        rom[175] = 8'h00;
        // 0x36 6
        rom[176] = 8'h38;
        rom[177] = 8'h60;
        rom[178] = 8'hC0;
        rom[179] = 8'hFC;
        rom[180] = 8'hC6;
        rom[181] = 8'hC6;
        rom[182] = 8'h7C;
        rom[183] = 8'h00;
        // 0x37 7
        rom[184] = 8'hFE;
        rom[185] = 8'hC6;
        rom[186] = 8'h0C;
        rom[187] = 8'h18;
        rom[188] = 8'h30;
        rom[189] = 8'h30;
        rom[190] = 8'h30;
        rom[191] = 8'h00;
        // 0x38 8
        rom[192] = 8'h7C;
        rom[193] = 8'hC6;
        rom[194] = 8'hC6;
        rom[195] = 8'h7C;
        rom[196] = 8'hC6;
        rom[197] = 8'hC6;
        rom[198] = 8'h7C;
        rom[199] = 8'h00;
        // 0x39 9
        rom[200] = 8'h7C;
        rom[201] = 8'hC6;
        rom[202] = 8'hC6;
        rom[203] = 8'h7E;
        rom[204] = 8'h06;
        rom[205] = 8'h0C;
        rom[206] = 8'h78;
        rom[207] = 8'h00;
        // 0x3A :
        rom[208] = 8'h00;
        rom[209] = 8'h18;
        rom[210] = 8'h18;
        rom[211] = 8'h00;
        rom[212] = 8'h00;
        rom[213] = 8'h18;
        rom[214] = 8'h18;
        rom[215] = 8'h00;
        // 0x3B ;
        rom[216] = 8'h00;
        rom[217] = 8'h18;
        rom[218] = 8'h18;
        rom[219] = 8'h00;
        rom[220] = 8'h00;
        rom[221] = 8'h18;
        rom[222] = 8'h18;
        rom[223] = 8'h30;
        // 0x3C <
        rom[224] = 8'h06;
        rom[225] = 8'h0C;
        rom[226] = 8'h18;
        rom[227] = 8'h30;
        rom[228] = 8'h18;
        rom[229] = 8'h0C;
        rom[230] = 8'h06;
        rom[231] = 8'h00;
        // 0x3D =
        rom[232] = 8'h00;
        rom[233] = 8'h00;
        rom[234] = 8'h7E;
        rom[235] = 8'h00;
        rom[236] = 8'h00;
        rom[237] = 8'h7E;
        rom[238] = 8'h00;
        rom[239] = 8'h00;
        // 0x3E >
        rom[240] = 8'h60;
        rom[241] = 8'h30;
        rom[242] = 8'h18;
        rom[243] = 8'h0C;
        rom[244] = 8'h18;
        rom[245] = 8'h30;
        rom[246] = 8'h60;
        rom[247] = 8'h00;
        // 0x3F ?
        rom[248] = 8'h7C;
        rom[249] = 8'hC6;
        rom[250] = 8'h0C;
        rom[251] = 8'h18;
        rom[252] = 8'h18;
        rom[253] = 8'h00;
        rom[254] = 8'h18;
        rom[255] = 8'h00;
        // 0x40 @
        rom[256] = 8'h7C;
        rom[257] = 8'hC6;
        rom[258] = 8'hDE;
        rom[259] = 8'hDE;
        rom[260] = 8'hDE;
        rom[261] = 8'hC0;
        rom[262] = 8'h78;
        rom[263] = 8'h00;
        // 0x41 A
        rom[264] = 8'h38;
        rom[265] = 8'h6C;
        rom[266] = 8'hC6;
        rom[267] = 8'hFE;
        rom[268] = 8'hC6;
        rom[269] = 8'hC6;
        rom[270] = 8'hC6;
        rom[271] = 8'h00;
        // 0x42 B
        rom[272] = 8'hFC;
        rom[273] = 8'h66;
        rom[274] = 8'h66;
        rom[275] = 8'h7C;
        rom[276] = 8'h66;
        rom[277] = 8'h66;
        rom[278] = 8'hFC;
        rom[279] = 8'h00;
        // 0x43 C
        rom[280] = 8'h3C;
        rom[281] = 8'h66;
        rom[282] = 8'hC0;
        rom[283] = 8'hC0;
        rom[284] = 8'hC0;
        rom[285] = 8'h66;
        rom[286] = 8'h3C;
        rom[287] = 8'h00;
        // 0x44 D
        rom[288] = 8'hF8;
        rom[289] = 8'h6C;
        rom[290] = 8'h66;
        rom[291] = 8'h66;
        rom[292] = 8'h66;
        rom[293] = 8'h6C;
        rom[294] = 8'hF8;
        rom[295] = 8'h00;
        // 0x45 E
        rom[296] = 8'hFE;
        rom[297] = 8'h62;
        rom[298] = 8'h68;
        rom[299] = 8'h78;
        rom[300] = 8'h68;
        rom[301] = 8'h62;
        rom[302] = 8'hFE;
        rom[303] = 8'h00;
        // 0x46 F
        rom[304] = 8'hFE;
        rom[305] = 8'h62;
        rom[306] = 8'h68;
        rom[307] = 8'h78;
        rom[308] = 8'h68;
        rom[309] = 8'h60;
        rom[310] = 8'hF0;
        rom[311] = 8'h00;
        // 0x47 G
        rom[312] = 8'h3C;
        rom[313] = 8'h66;
        rom[314] = 8'hC0;
        rom[315] = 8'hC0;
        rom[316] = 8'hCE;
        rom[317] = 8'h66;
        rom[318] = 8'h3A;
        rom[319] = 8'h00;
        // 0x48 H
        rom[320] = 8'hC6;
        rom[321] = 8'hC6;
        rom[322] = 8'hC6;
        rom[323] = 8'hFE;
        rom[324] = 8'hC6;
        rom[325] = 8'hC6;
        rom[326] = 8'hC6;
        rom[327] = 8'h00;
        // 0x49 I
        rom[328] = 8'h3C;
        rom[329] = 8'h18;
        rom[330] = 8'h18;
        rom[331] = 8'h18;
        rom[332] = 8'h18;
        rom[333] = 8'h18;
        rom[334] = 8'h3C;
        rom[335] = 8'h00;
        // 0x4A J
        rom[336] = 8'h1E;
        rom[337] = 8'h0C;
        rom[338] = 8'h0C;
        rom[339] = 8'h0C;
        rom[340] = 8'hCC;
        rom[341] = 8'hCC;
        rom[342] = 8'h78;
        rom[343] = 8'h00;
        // 0x4B K
        rom[344] = 8'hE6;
        rom[345] = 8'h66;
        rom[346] = 8'h6C;
        rom[347] = 8'h78;
        rom[348] = 8'h6C;
        rom[349] = 8'h66;
        rom[350] = 8'hE6;
        rom[351] = 8'h00;
        // 0x4C L
        rom[352] = 8'hF0;
        rom[353] = 8'h60;
        rom[354] = 8'h60;
        rom[355] = 8'h60;
        rom[356] = 8'h62;
        rom[357] = 8'h66;
        rom[358] = 8'hFE;
        rom[359] = 8'h00;
        // 0x4D M
        rom[360] = 8'hC6;
        rom[361] = 8'hEE;
        rom[362] = 8'hFE;
        rom[363] = 8'hFE;
        rom[364] = 8'hD6;
        rom[365] = 8'hC6;
        rom[366] = 8'hC6;
        rom[367] = 8'h00;
        // 0x4E N
        rom[368] = 8'hC6;
        rom[369] = 8'hE6;
        rom[370] = 8'hF6;
        rom[371] = 8'hDE;
        rom[372] = 8'hCE;
        rom[373] = 8'hC6;
        rom[374] = 8'hC6;
        rom[375] = 8'h00;
        // 0x4F O
        rom[376] = 8'h7C;
        rom[377] = 8'hC6;
        rom[378] = 8'hC6;
        rom[379] = 8'hC6;
        rom[380] = 8'hC6;
        rom[381] = 8'hC6;
        rom[382] = 8'h7C;
        rom[383] = 8'h00;
        // 0x50 P
        rom[384] = 8'hFC;
        rom[385] = 8'h66;
        rom[386] = 8'h66;
        rom[387] = 8'h7C;
        rom[388] = 8'h60;
        rom[389] = 8'h60;
        rom[390] = 8'hF0;
        rom[391] = 8'h00;
        // 0x51 Q
        rom[392] = 8'h7C;
        rom[393] = 8'hC6;
        rom[394] = 8'hC6;
        rom[395] = 8'hC6;
        rom[396] = 8'hC6;
        rom[397] = 8'hCE;
        rom[398] = 8'h7C;
        rom[399] = 8'h0E;
        // 0x52 R
        rom[400] = 8'hFC;
        rom[401] = 8'h66;
        rom[402] = 8'h66;
        rom[403] = 8'h7C;
        rom[404] = 8'h6C;
        rom[405] = 8'h66;
        rom[406] = 8'hE6;
        rom[407] = 8'h00;
        // 0x53 S
        rom[408] = 8'h3C;
        rom[409] = 8'h66;
        rom[410] = 8'h30;
        rom[411] = 8'h18;
        rom[412] = 8'h0C;
        rom[413] = 8'h66;
        rom[414] = 8'h3C;
        rom[415] = 8'h00;
        // 0x54 T
        rom[416] = 8'h7E;
        rom[417] = 8'h7E;
        rom[418] = 8'h5A;
        rom[419] = 8'h18;
        rom[420] = 8'h18;
        rom[421] = 8'h18;
        rom[422] = 8'h3C;
        rom[423] = 8'h00;
        // 0x55 U
        rom[424] = 8'hC6;
        rom[425] = 8'hC6;
        rom[426] = 8'hC6;
        rom[427] = 8'hC6;
        rom[428] = 8'hC6;
        rom[429] = 8'hC6;
        rom[430] = 8'h7C;
        rom[431] = 8'h00;
        // 0x56 V
        rom[432] = 8'hC6;
        rom[433] = 8'hC6;
        rom[434] = 8'hC6;
        rom[435] = 8'hC6;
        rom[436] = 8'hC6;
        rom[437] = 8'h6C;
        rom[438] = 8'h38;
        rom[439] = 8'h00;
        // 0x57 W
        rom[440] = 8'hC6;
        rom[441] = 8'hC6;
        rom[442] = 8'hC6;
        rom[443] = 8'hD6;
        rom[444] = 8'hD6;
        rom[445] = 8'hFE;
        rom[446] = 8'h6C;
        rom[447] = 8'h00;
        // 0x58 X
        rom[448] = 8'hC6;
        rom[449] = 8'hC6;
        rom[450] = 8'h6C;
        rom[451] = 8'h38;
        rom[452] = 8'h6C;
        rom[453] = 8'hC6;
        rom[454] = 8'hC6;
        rom[455] = 8'h00;
        // 0x59 Y
        rom[456] = 8'h66;
        rom[457] = 8'h66;
        rom[458] = 8'h66;
        rom[459] = 8'h3C;
        rom[460] = 8'h18;
        rom[461] = 8'h18;
        rom[462] = 8'h3C;
        rom[463] = 8'h00;
        // 0x5A Z
        rom[464] = 8'hFE;
        rom[465] = 8'hC6;
        rom[466] = 8'h8C;
        rom[467] = 8'h18;
        rom[468] = 8'h32;
        rom[469] = 8'h66;
        rom[470] = 8'hFE;
        rom[471] = 8'h00;
        // 0x5B [
        rom[472] = 8'h3C;
        rom[473] = 8'h30;
        rom[474] = 8'h30;
        rom[475] = 8'h30;
        rom[476] = 8'h30;
        rom[477] = 8'h30;
        rom[478] = 8'h3C;
        rom[479] = 8'h00;
        // 0x5C \
        rom[480] = 8'hC0;
        rom[481] = 8'h60;
        rom[482] = 8'h30;
        rom[483] = 8'h18;
        rom[484] = 8'h0C;
        rom[485] = 8'h06;
        rom[486] = 8'h02;
        rom[487] = 8'h00;
        // 0x5D ]
        rom[488] = 8'h3C;
        rom[489] = 8'h0C;
        rom[490] = 8'h0C;
        rom[491] = 8'h0C;
        rom[492] = 8'h0C;
        rom[493] = 8'h0C;
        rom[494] = 8'h3C;
        rom[495] = 8'h00;
        // 0x5E ^
        rom[496] = 8'h10;
        rom[497] = 8'h38;
        rom[498] = 8'h6C;
        rom[499] = 8'hC6;
        rom[500] = 8'h00;
        rom[501] = 8'h00;
        rom[502] = 8'h00;
        rom[503] = 8'h00;
        // 0x5F _
        rom[504] = 8'h00;
        rom[505] = 8'h00;
        rom[506] = 8'h00;
        rom[507] = 8'h00;
        rom[508] = 8'h00;
        rom[509] = 8'h00;
        rom[510] = 8'h00;
        rom[511] = 8'hFF;
    end

    always_ff @(posedge clk) bits <= rom[{code, row}];

endmodule
