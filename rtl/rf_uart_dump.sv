//============================================================================
//  Write-ring UART dumper: 115200 8N1 on the HPS debug UART (/dev/ttyS1)
//
//  Loops forever over the captured write ring, one line per entry:
//
//      ===== 0FA3 <hash8>            header: entry count, hash at freeze
//      W 60D2C4 0000 3               addr(hex6) data(hex4) lanes(hex1: UDS/LDS)
//
//  ~14 chars/line at 115200 baud puts a full 4096-entry pass at ~5 s, so
//  capturing /dev/ttyS1 for ten seconds on the board always yields at least
//  one complete pass framed by two headers.
//============================================================================

module rf_uart_dump
(
    input  logic        clk,          // 53.372 MHz
    input  logic        reset,

    input  logic [11:0] ring_wptr,    // entries valid: 0 .. ring_wptr-1
    input  logic        ring_full,    // wptr wrapped: ALL 4096 entries valid
    output logic [11:0] ring_raddr,
    input  logic [55:0] ring_rdata,   // {UDS, LDS, addr[23:1], pad, data[15:0]}
    input  logic [31:0] wr_hash,

    output logic        txd
);

    // 53.372 MHz / 115200 = 463.3
    localparam int DIV = 463;

    logic [8:0]  baud_cnt;
    logic        baud_tick;
    always_ff @(posedge clk) begin
        if (baud_cnt == DIV[8:0] - 1) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 9'd1;
            baud_tick <= 1'b0;
        end
    end

    // ---- byte serialiser -------------------------------------------------
    logic [9:0] shifter;               // {stop, data[7:0], start}
    logic [3:0] bits_left;
    logic       busy;
    logic [7:0] tx_byte;
    logic       tx_go;

    always_ff @(posedge clk) begin
        if (reset) begin
            shifter   <= '1;
            bits_left <= '0;
            busy      <= 1'b0;
        end else begin
            if (tx_go && !busy) begin
                shifter   <= {1'b1, tx_byte, 1'b0};
                bits_left <= 4'd10;
                busy      <= 1'b1;
            end else if (busy && baud_tick) begin
                shifter <= {1'b1, shifter[9:1]};
                if (bits_left == 4'd1) busy <= 1'b0;
                else bits_left <= bits_left - 4'd1;
            end
        end
    end
    assign txd = shifter[0];

    // ---- line builder ----------------------------------------------------
    function automatic logic [7:0] hexc(input logic [3:0] n);
        hexc = (n < 10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    endfunction

    wire        e_uds  = ring_rdata[55];
    wire        e_lds  = ring_rdata[54];
    wire [23:0] e_addr = {ring_rdata[53:31], 1'b0};
    wire [15:0] e_data = ring_rdata[15:0];

    typedef enum logic [1:0] { L_HDR, L_ENTRY } line_t;
    line_t       line_kind;
    logic [4:0]  pos;
    logic [11:0] idx;

    // header:  "=" "=" "=" cnt[4] " " hash[8] "\n"          (17 chars)
    // entry :  "W" " " addr[6] " " data[4] " " lanes "\n"   (15 chars)
    logic [7:0] ch;
    always_comb begin
        ch = 8'h00;
        if (line_kind == L_HDR) begin
            case (pos)
                0,1,2:  ch = "=";
                3:      ch = hexc(ring_wptr[11:8]);
                4:      ch = hexc(ring_wptr[7:4]);
                5:      ch = hexc(ring_wptr[3:0]);
                6:      ch = " ";
                7,8,9,10,11,12,13,14:
                        ch = hexc(wr_hash[4*(14-pos) +: 4]);
                15:     ch = "\n";
                default: ch = 8'h00;
            endcase
        end else begin
            case (pos)
                0:      ch = "W";
                1:      ch = " ";
                2,3,4,5,6,7:
                        ch = hexc(e_addr[4*(7-pos) +: 4]);
                8:      ch = " ";
                9,10,11,12:
                        ch = hexc(e_data[4*(12-pos) +: 4]);
                13:     ch = " ";
                14:     ch = hexc({2'b00, e_uds, e_lds});
                15:     ch = "\n";
                default: ch = 8'h00;
            endcase
        end
    end

    localparam int LINE_LEN = 16;

    assign ring_raddr = idx;

    always_ff @(posedge clk) begin
        if (reset) begin
            line_kind <= L_HDR;
            pos <= '0; idx <= '0;
            tx_go <= 1'b0; tx_byte <= 8'h00;
        end else begin
            tx_go <= 1'b0;
            if (!busy && !tx_go) begin
                tx_byte <= ch;
                tx_go   <= 1'b1;
                if (pos == LINE_LEN - 1) begin
                    pos <= '0;
                    if (line_kind == L_HDR) begin
                        idx       <= '0;
                        line_kind <= (ring_wptr == 0 && !ring_full) ? L_HDR : L_ENTRY;
                    end else if (idx == ring_wptr - 12'd1) begin
                        line_kind <= L_HDR;
                    end else begin
                        idx <= idx + 12'd1;
                    end
                end else pos <= pos + 5'd1;
            end
        end
    end

endmodule
