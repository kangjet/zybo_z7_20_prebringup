`timescale 1ns/1ps
//=============================================================
// top_ilc3_txref_packet256_tx_board.v
//
// ILC3 packet PHY TX over the same analog resistor-DAC path used
// by the ILC3ALG noise-boundary test.
//
// Frame:
//   preamble : 55 55 D5 A5
//   header   : 02 03 01 00 SEQ3 SEQ2 SEQ1 SEQ0
//   meta     : TH_H TH_L TT_H TT_L
//              TH = TX payload DH sample count
//              TT = TX inserted TAG sample count per frame
//              version=1, mode=ILC3(3), PSDU length=256B
//   PSDU     : 256 deterministic bytes, byte[i] = i ^ seq[7:0] ^ A5
//   FCS      : CRC-16/CCITT-FALSE over header + PSDU
//              Meta bytes are kept outside the FCS in this latency-test
//              variant to preserve the packet CRC contract.
//
// Log:
//   ILC3PTX PK=XXXXXXXX SA=XXXXXXXX DP=XXXXXXXX TH=XXXXXXXX TM=XXXXXXXX TL=XXXXXXXX TT=XXXXXXXX
//=============================================================
module top_ilc3_txref_packet256_tx_board #(
    parameter integer CLK_FREQ_HZ        = 125_000_000,
    parameter integer UART_BAUD          = 115_200,
    parameter integer SYMBOL_HOLD_CLKS   = 85,
    parameter integer STROBE_OFFSET_CLKS = 68,
    parameter integer STROBE_PULSE_CLKS  = 4,
    parameter integer ENABLE_TAG         = 0,
    parameter integer TAG_INTERVAL_SYMBOLS = 32,
    parameter integer TAG_PAIR_COUNT     = 2
) (
    input  wire       sys_clk,
    input  wire       rst_btn_n,

    output reg  [1:0] pam4_code,
    output reg        pam4_valid,
    output reg        pam4_sync,

    output wire       uart_tx,
    output wire [3:0] led
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;
localparam integer SEC_COUNTS   = CLK_FREQ_HZ;
localparam integer PREAMBLE_LEN = 4;
localparam integer HEADER_LEN   = 8;
localparam integer META_LEN     = 4;
localparam integer PAYLOAD_LEN  = 256;
localparam integer CRC_LEN      = 2;
localparam integer FRAME_BYTES  = PREAMBLE_LEN + HEADER_LEN + META_LEN + PAYLOAD_LEN + CRC_LEN;
localparam integer DATA_SYMBOLS_PER_FRAME = FRAME_BYTES * 4;
localparam integer TAG_GROUPS_PER_FRAME =
    (ENABLE_TAG != 0) ? ((DATA_SYMBOLS_PER_FRAME - 1) / TAG_INTERVAL_SYMBOLS) : 0;
localparam integer TAG_SAMPLES_PER_FRAME = TAG_GROUPS_PER_FRAME * TAG_PAIR_COUNT * 2;
localparam [15:0] TX_TAG_SAMPLES_PER_FRAME = TAG_SAMPLES_PER_FRAME;

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

function [15:0] crc16_byte;
    input [15:0] crc;
    input [7:0]  din;
    integer i;
    reg [15:0] c;
    begin
        c = crc ^ {din, 8'h00};
        for (i = 0; i < 8; i = i + 1)
            c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
        crc16_byte = c;
    end
endfunction

function [7:0] payload_byte;
    input [7:0] idx;
    input [31:0] seq;
    begin
        payload_byte = idx ^ seq[7:0] ^ 8'hA5;
    end
endfunction

function [15:0] payload_dh_count;
    input [31:0] seq;
    integer i;
    reg [7:0] b;
    reg [15:0] c;
    begin
        c = 16'd0;
        for (i = 0; i < PAYLOAD_LEN; i = i + 1) begin
            b = payload_byte(i[7:0], seq);
            c = c + b[7] + b[5] + b[3] + b[1];
        end
        payload_dh_count = c;
    end
endfunction

function [7:0] packet_byte_no_crc;
    input [8:0] idx;
    input [31:0] seq;
    reg [15:0] th;
    begin
        th = payload_dh_count(seq);
        case (idx)
            9'd0:  packet_byte_no_crc = 8'h55;
            9'd1:  packet_byte_no_crc = 8'h55;
            9'd2:  packet_byte_no_crc = 8'hD5;
            9'd3:  packet_byte_no_crc = 8'hA5;
            9'd4:  packet_byte_no_crc = 8'h02;
            9'd5:  packet_byte_no_crc = 8'h03;
            9'd6:  packet_byte_no_crc = 8'h01;
            9'd7:  packet_byte_no_crc = 8'h00;
            9'd8:  packet_byte_no_crc = seq[31:24];
            9'd9:  packet_byte_no_crc = seq[23:16];
            9'd10: packet_byte_no_crc = seq[15:8];
            9'd11: packet_byte_no_crc = seq[7:0];
            9'd12: packet_byte_no_crc = th[15:8];
            9'd13: packet_byte_no_crc = th[7:0];
            9'd14: packet_byte_no_crc = TX_TAG_SAMPLES_PER_FRAME[15:8];
            9'd15: packet_byte_no_crc = TX_TAG_SAMPLES_PER_FRAME[7:0];
            default: packet_byte_no_crc = payload_byte(idx - 9'd16, seq);
        endcase
    end
endfunction

reg [31:0] pkt_seq;
reg [31:0] cur_seq;
reg [8:0]  byte_idx;
reg [1:0]  sym_idx;
reg        sample_idx;
reg [31:0] hold_cnt;
reg [31:0] sample_cnt;
reg [31:0] pkt_cnt;
reg [31:0] tx_sample_dbg;
reg [3:0]  tx_dbg_count;
reg [15:0] crc_acc;
reg [31:0] tx_high_cnt;
reg [31:0] tx_mid_cnt;
reg [31:0] tx_low_cnt;
reg [31:0] tx_tag_sample_cnt;

reg [7:0] frame_byte;
always @(*) begin
    if (byte_idx == FRAME_BYTES - 2)
        frame_byte = crc_acc[15:8];
    else if (byte_idx == FRAME_BYTES - 1)
        frame_byte = crc_acc[7:0];
    else
        frame_byte = packet_byte_no_crc(byte_idx, cur_seq);
end

reg [1:0] cur_sym;
always @(*) begin
    case (sym_idx)
        2'd0: cur_sym = frame_byte[7:6];
        2'd1: cur_sym = frame_byte[5:4];
        2'd2: cur_sym = frame_byte[3:2];
        default: cur_sym = frame_byte[1:0];
    endcase
end

reg signed [1:0] data_amp_sample;
always @(*) begin
    case (cur_sym)
        2'd0: data_amp_sample = sample_idx ? 2'sd0  : -2'sd1;
        2'd1: data_amp_sample = sample_idx ? -2'sd1 : 2'sd0;
        2'd2: data_amp_sample = sample_idx ? 2'sd0  : 2'sd1;
        default: data_amp_sample = sample_idx ? 2'sd1 : 2'sd0;
    endcase
end

reg        tag_active;
reg [1:0]  tag_pair_idx;
reg        tag_sample_idx;
reg [15:0] data_sym_since_tag;

wire signed [1:0] tag_amp_sample = tag_pair_idx[0] ? -2'sd1 : 2'sd1;
wire signed [1:0] amp_sample = tag_active ? tag_amp_sample : data_amp_sample;

function [1:0] code_from_amp;
    input signed [1:0] amp;
    begin
        case (amp)
            -2'sd1: code_from_amp = 2'b00;
             2'sd0: code_from_amp = 2'b01;
             2'sd1: code_from_amp = 2'b10;
            default: code_from_amp = 2'b00;
        endcase
    end
endfunction

function [3:0] nibble_from_amp;
    input signed [1:0] amp;
    begin
        case (amp)
            -2'sd1: nibble_from_amp = 4'hF;
             2'sd0: nibble_from_amp = 4'h0;
             2'sd1: nibble_from_amp = 4'h1;
            default: nibble_from_amp = 4'h0;
        endcase
    end
endfunction

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        pkt_seq       <= 32'd0;
        cur_seq       <= 32'd0;
        byte_idx      <= 9'd0;
        sym_idx       <= 2'd0;
        sample_idx    <= 1'b0;
        hold_cnt      <= 32'd0;
        sample_cnt    <= 32'd0;
        pkt_cnt       <= 32'd0;
        tx_sample_dbg <= 32'd0;
        tx_dbg_count  <= 4'd0;
        crc_acc       <= 16'hFFFF;
        tx_high_cnt   <= 32'd0;
        tx_mid_cnt    <= 32'd0;
        tx_low_cnt    <= 32'd0;
        tx_tag_sample_cnt <= 32'd0;
        tag_active    <= 1'b0;
        tag_pair_idx  <= 2'd0;
        tag_sample_idx <= 1'b0;
        data_sym_since_tag <= 16'd0;
        pam4_code     <= 2'b00;
        pam4_valid    <= 1'b0;
        pam4_sync     <= 1'b0;
    end else begin
        pam4_code  <= code_from_amp(amp_sample);
        pam4_valid <= (hold_cnt >= STROBE_OFFSET_CLKS) &&
                      (hold_cnt < STROBE_OFFSET_CLKS + STROBE_PULSE_CLKS);
        pam4_sync  <= (hold_cnt < STROBE_PULSE_CLKS) &&
                      (byte_idx == 9'd0) && (sym_idx == 2'd0) && !sample_idx;

        if (hold_cnt == STROBE_OFFSET_CLKS) begin
            sample_cnt <= sample_cnt + 32'd1;
            if (amp_sample == 2'sd1)
                tx_high_cnt <= tx_high_cnt + 32'd1;
            else if (amp_sample == 2'sd0)
                tx_mid_cnt <= tx_mid_cnt + 32'd1;
            else
                tx_low_cnt <= tx_low_cnt + 32'd1;
            if (tag_active)
                tx_tag_sample_cnt <= tx_tag_sample_cnt + 32'd1;
            if ((byte_idx == 9'd0) && (sym_idx == 2'd0) && !sample_idx) begin
                tx_sample_dbg <= {28'd0, nibble_from_amp(amp_sample)};
                tx_dbg_count  <= 4'd1;
            end else if (tx_dbg_count < 4'd8) begin
                tx_sample_dbg <= {tx_sample_dbg[27:0], nibble_from_amp(amp_sample)};
                tx_dbg_count  <= tx_dbg_count + 4'd1;
            end
        end

        if (hold_cnt == SYMBOL_HOLD_CLKS - 1) begin
            hold_cnt <= 32'd0;
            if (tag_active) begin
                sample_idx <= 1'b0;
                if (tag_sample_idx) begin
                    tag_sample_idx <= 1'b0;
                    if (tag_pair_idx == TAG_PAIR_COUNT - 1) begin
                        tag_active <= 1'b0;
                        tag_pair_idx <= 2'd0;
                        data_sym_since_tag <= 16'd0;
                    end else begin
                        tag_pair_idx <= tag_pair_idx + 2'd1;
                    end
                end else begin
                    tag_sample_idx <= 1'b1;
                end
            end else begin
                if (sample_idx) begin
                    sample_idx <= 1'b0;
                    if ((ENABLE_TAG != 0) && (data_sym_since_tag == TAG_INTERVAL_SYMBOLS - 1) &&
                        !((byte_idx == FRAME_BYTES - 1) && (sym_idx == 2'd3))) begin
                        tag_active <= 1'b1;
                        tag_pair_idx <= 2'd0;
                        tag_sample_idx <= 1'b0;
                    end else begin
                        data_sym_since_tag <= data_sym_since_tag + 16'd1;
                    end
                    if (sym_idx == 2'd3) begin
                        sym_idx <= 2'd0;
                        if (((byte_idx >= PREAMBLE_LEN) &&
                             (byte_idx < PREAMBLE_LEN + HEADER_LEN)) ||
                            ((byte_idx >= PREAMBLE_LEN + HEADER_LEN + META_LEN) &&
                             (byte_idx < PREAMBLE_LEN + HEADER_LEN + META_LEN + PAYLOAD_LEN)))
                            crc_acc <= crc16_byte(crc_acc, frame_byte);
                        if (byte_idx == FRAME_BYTES - 1) begin
                            byte_idx <= 9'd0;
                            pkt_seq  <= pkt_seq + 32'd1;
                            cur_seq  <= pkt_seq + 32'd1;
                            pkt_cnt  <= pkt_cnt + 32'd1;
                            crc_acc  <= 16'hFFFF;
                            data_sym_since_tag <= 16'd0;
                        end else begin
                            byte_idx <= byte_idx + 9'd1;
                        end
                    end else begin
                        sym_idx <= sym_idx + 2'd1;
                    end
                end else begin
                    sample_idx <= 1'b1;
                end
            end
        end else begin
            hold_cnt <= hold_cnt + 32'd1;
        end
    end
end

function [7:0] nibble_ascii;
    input [3:0] n;
    begin
        nibble_ascii = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    end
endfunction

// "ILC3PTX PK=XXXXXXXX SA=XXXXXXXX DP=XXXXXXXX TH=XXXXXXXX TM=XXXXXXXX TL=XXXXXXXX TT=XXXXXXXX\r\n"
function [7:0] log_char;
    input [6:0] ptr;
    input [31:0] pk;
    input [31:0] sa;
    input [31:0] dbg;
    input [31:0] th;
    input [31:0] tm;
    input [31:0] tl;
    input [31:0] tt;
    begin
        case (ptr)
            7'd0:  log_char = "I"; 7'd1:  log_char = "L"; 7'd2:  log_char = "C"; 7'd3:  log_char = "3";
            7'd4:  log_char = "P"; 7'd5:  log_char = "T"; 7'd6:  log_char = "X"; 7'd7:  log_char = " ";
            7'd8:  log_char = "P"; 7'd9:  log_char = "K"; 7'd10: log_char = "=";
            7'd11: log_char = nibble_ascii(pk[31:28]); 7'd12: log_char = nibble_ascii(pk[27:24]);
            7'd13: log_char = nibble_ascii(pk[23:20]); 7'd14: log_char = nibble_ascii(pk[19:16]);
            7'd15: log_char = nibble_ascii(pk[15:12]); 7'd16: log_char = nibble_ascii(pk[11:8]);
            7'd17: log_char = nibble_ascii(pk[7:4]);   7'd18: log_char = nibble_ascii(pk[3:0]);
            7'd19: log_char = " "; 7'd20: log_char = "S"; 7'd21: log_char = "A"; 7'd22: log_char = "=";
            7'd23: log_char = nibble_ascii(sa[31:28]); 7'd24: log_char = nibble_ascii(sa[27:24]);
            7'd25: log_char = nibble_ascii(sa[23:20]); 7'd26: log_char = nibble_ascii(sa[19:16]);
            7'd27: log_char = nibble_ascii(sa[15:12]); 7'd28: log_char = nibble_ascii(sa[11:8]);
            7'd29: log_char = nibble_ascii(sa[7:4]);   7'd30: log_char = nibble_ascii(sa[3:0]);
            7'd31: log_char = " "; 7'd32: log_char = "D"; 7'd33: log_char = "P"; 7'd34: log_char = "=";
            7'd35: log_char = nibble_ascii(dbg[31:28]); 7'd36: log_char = nibble_ascii(dbg[27:24]);
            7'd37: log_char = nibble_ascii(dbg[23:20]); 7'd38: log_char = nibble_ascii(dbg[19:16]);
            7'd39: log_char = nibble_ascii(dbg[15:12]); 7'd40: log_char = nibble_ascii(dbg[11:8]);
            7'd41: log_char = nibble_ascii(dbg[7:4]);   7'd42: log_char = nibble_ascii(dbg[3:0]);
            7'd43: log_char = " "; 7'd44: log_char = "T"; 7'd45: log_char = "H"; 7'd46: log_char = "=";
            7'd47: log_char = nibble_ascii(th[31:28]); 7'd48: log_char = nibble_ascii(th[27:24]);
            7'd49: log_char = nibble_ascii(th[23:20]); 7'd50: log_char = nibble_ascii(th[19:16]);
            7'd51: log_char = nibble_ascii(th[15:12]); 7'd52: log_char = nibble_ascii(th[11:8]);
            7'd53: log_char = nibble_ascii(th[7:4]);   7'd54: log_char = nibble_ascii(th[3:0]);
            7'd55: log_char = " "; 7'd56: log_char = "T"; 7'd57: log_char = "M"; 7'd58: log_char = "=";
            7'd59: log_char = nibble_ascii(tm[31:28]); 7'd60: log_char = nibble_ascii(tm[27:24]);
            7'd61: log_char = nibble_ascii(tm[23:20]); 7'd62: log_char = nibble_ascii(tm[19:16]);
            7'd63: log_char = nibble_ascii(tm[15:12]); 7'd64: log_char = nibble_ascii(tm[11:8]);
            7'd65: log_char = nibble_ascii(tm[7:4]);   7'd66: log_char = nibble_ascii(tm[3:0]);
            7'd67: log_char = " "; 7'd68: log_char = "T"; 7'd69: log_char = "L"; 7'd70: log_char = "=";
            7'd71: log_char = nibble_ascii(tl[31:28]); 7'd72: log_char = nibble_ascii(tl[27:24]);
            7'd73: log_char = nibble_ascii(tl[23:20]); 7'd74: log_char = nibble_ascii(tl[19:16]);
            7'd75: log_char = nibble_ascii(tl[15:12]); 7'd76: log_char = nibble_ascii(tl[11:8]);
            7'd77: log_char = nibble_ascii(tl[7:4]);   7'd78: log_char = nibble_ascii(tl[3:0]);
            7'd79: log_char = " "; 7'd80: log_char = "T"; 7'd81: log_char = "T"; 7'd82: log_char = "=";
            7'd83: log_char = nibble_ascii(tt[31:28]); 7'd84: log_char = nibble_ascii(tt[27:24]);
            7'd85: log_char = nibble_ascii(tt[23:20]); 7'd86: log_char = nibble_ascii(tt[19:16]);
            7'd87: log_char = nibble_ascii(tt[15:12]); 7'd88: log_char = nibble_ascii(tt[11:8]);
            7'd89: log_char = nibble_ascii(tt[7:4]);   7'd90: log_char = nibble_ascii(tt[3:0]);
            7'd91: log_char = 8'h0D; 7'd92: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_pkt_cnt, log_sample_cnt, log_dbg;
reg [31:0] log_th, log_tm, log_tl, log_tt;
reg [31:0] prev_tx_high_cnt, prev_tx_mid_cnt, prev_tx_low_cnt, prev_tx_tag_sample_cnt;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt <= 27'd0; log_pkt_cnt <= 32'd0; log_sample_cnt <= 32'd0; log_dbg <= 32'd0;
        log_th <= 32'd0; log_tm <= 32'd0; log_tl <= 32'd0; log_tt <= 32'd0;
        prev_tx_high_cnt <= 32'd0; prev_tx_mid_cnt <= 32'd0; prev_tx_low_cnt <= 32'd0; prev_tx_tag_sample_cnt <= 32'd0;
        log_req <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt <= 27'd0;
            log_pkt_cnt <= pkt_cnt;
            log_sample_cnt <= sample_cnt;
            log_dbg <= tx_sample_dbg;
            log_th <= tx_high_cnt - prev_tx_high_cnt;
            log_tm <= tx_mid_cnt - prev_tx_mid_cnt;
            log_tl <= tx_low_cnt - prev_tx_low_cnt;
            log_tt <= tx_tag_sample_cnt - prev_tx_tag_sample_cnt;
            prev_tx_high_cnt <= tx_high_cnt;
            prev_tx_mid_cnt <= tx_mid_cnt;
            prev_tx_low_cnt <= tx_low_cnt;
            prev_tx_tag_sample_cnt <= tx_tag_sample_cnt;
            log_req <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
    end
end

reg [6:0] log_ptr;
reg       log_active;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr <= 7'd0; log_active <= 1'b0; uart_start <= 1'b0; uart_data <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (log_req && !log_active && !uart_busy) begin
            log_active <= 1'b1; log_ptr <= 7'd0;
        end else if (log_active && !uart_busy && !uart_start) begin
            uart_data <= log_char(log_ptr, log_pkt_cnt, log_sample_cnt, log_dbg, log_th, log_tm, log_tl, log_tt);
            uart_start <= 1'b1;
            if (log_ptr == 7'd92) log_active <= 1'b0;
            else log_ptr <= log_ptr + 7'd1;
        end
    end
end

uart_tx_simple #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
    .clk(sys_clk), .rst_n(rst_n), .start(uart_start),
    .data_in(uart_data), .tx(uart_tx), .busy(uart_busy)
);

assign led[0] = pam4_valid;
assign led[1] = pam4_sync;
assign led[2] = pkt_cnt[0];
assign led[3] = uart_busy;

endmodule
