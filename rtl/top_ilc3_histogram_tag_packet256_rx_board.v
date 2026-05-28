`timescale 1ns/1ps
//=============================================================
// top_ilc3_histogram_tag_packet256_rx_board.v
//
// ILC3 packet PHY RX for 256B PSDU over the analog comparator
// path. It decodes ILC3 symbols, reconstructs packet bytes, checks
// preamble/header/payload, verifies CRC-16/CCITT-FALSE, and logs
// RX-only level histogram counters.
//
// Log:
//   ILC3PKT SH=XXXX PK=XXXXXXXX OK=XXXXXXXX NG=XXXXXXXX
//           BE=XXXXXXXX CE=XXXXXXXX WI=XXXXXXXX FS=XXXXXXXX LB=XX
//=============================================================
module top_ilc3_histogram_tag_packet256_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 85,
    parameter integer SAMPLE_DELAY_CLKS = 4,
    parameter integer ENABLE_TAG = 0,
    parameter integer TAG_INTERVAL_SYMBOLS = 32,
    parameter integer TAG_PAIR_COUNT = 2
) (
    input  wire       sys_clk,
    input  wire       rst_btn_n,

    input  wire [2:0] cmp_in,
    input  wire       sample_strobe_in,
    input  wire       frame_sync_in,

    output wire       uart_tx,
    output wire [3:0] led
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;
localparam integer SEC_COUNTS   = CLK_FREQ_HZ;
localparam integer PREAMBLE_LEN = 4;
localparam integer HEADER_LEN   = 8;
localparam integer PAYLOAD_LEN  = 256;
localparam integer CRC_LEN      = 2;
localparam integer FRAME_BYTES  = PREAMBLE_LEN + HEADER_LEN + PAYLOAD_LEN + CRC_LEN;
localparam [31:0] DH_WARN_TH = 32'h0007_0000;
localparam [31:0] DH_HIGH_TH = 32'h0009_0000;
localparam [31:0] DM_WARN_TH = 32'h0009_0000;
localparam [31:0] DM_LOW_TH  = 32'h0007_5000;
localparam [31:0] DL_MIN_TH  = 32'h0002_0000;

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

(* ASYNC_REG = "TRUE" *) reg [2:0] cmp_s1, cmp_s2;
(* ASYNC_REG = "TRUE" *) reg       stb_s1, stb_s2, stb_s3;
(* ASYNC_REG = "TRUE" *) reg       fs_s1, fs_s2, fs_s3;

always @(posedge sys_clk) begin
    cmp_s1 <= cmp_in;
    cmp_s2 <= cmp_s1;
    stb_s1 <= sample_strobe_in;
    stb_s2 <= stb_s1;
    stb_s3 <= stb_s2;
    fs_s1 <= frame_sync_in;
    fs_s2 <= fs_s1;
    fs_s3 <= fs_s2;
end

wire sample_rise = stb_s2 && !stb_s3;
wire sync_rise   = fs_s2 && !fs_s3;

function therm_valid;
    input [2:0] raw;
    begin
        case (raw)
            3'b000, 3'b001, 3'b011, 3'b111: therm_valid = 1'b1;
            default:                         therm_valid = 1'b0;
        endcase
    end
endfunction

function signed [3:0] therm_to_amp;
    input [2:0] raw;
    begin
        case (raw)
            3'b000: therm_to_amp = -4'sd1;
            3'b001,
            3'b011: therm_to_amp =  4'sd0;
            3'b111: therm_to_amp =  4'sd1;
            default: therm_to_amp = 4'sd0;
        endcase
    end
endfunction

reg signed [3:0] amp_sample_q;
reg              amp_valid_q;
reg              frame_sync_q;
reg              sample_delay_active;
reg [7:0]        sample_delay_cnt;
reg [31:0]       hist_high_cnt;
reg [31:0]       hist_mid_cnt;
reg [31:0]       hist_low_cnt;
reg [31:0]       hist_invalid_cnt;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        amp_sample_q <= 4'sd0;
        amp_valid_q <= 1'b0;
        frame_sync_q <= 1'b0;
        sample_delay_active <= 1'b0;
        sample_delay_cnt <= 8'd0;
        hist_high_cnt <= 32'd0;
        hist_mid_cnt <= 32'd0;
        hist_low_cnt <= 32'd0;
        hist_invalid_cnt <= 32'd0;
    end else begin
        amp_valid_q <= 1'b0;
        frame_sync_q <= sync_rise;
        if (sample_rise) begin
            sample_delay_active <= 1'b1;
            sample_delay_cnt <= 8'd0;
        end else if (sample_delay_active) begin
            if (sample_delay_cnt == SAMPLE_DELAY_CLKS[7:0]) begin
                amp_sample_q <= therm_to_amp(cmp_s2);
                amp_valid_q <= 1'b1;
                sample_delay_active <= 1'b0;
                case (cmp_s2)
                    3'b000: hist_low_cnt <= hist_low_cnt + 32'd1;
                    3'b001,
                    3'b011: hist_mid_cnt <= hist_mid_cnt + 32'd1;
                    3'b111: hist_high_cnt <= hist_high_cnt + 32'd1;
                    default: hist_invalid_cnt <= hist_invalid_cnt + 32'd1;
                endcase
            end else begin
                sample_delay_cnt <= sample_delay_cnt + 8'd1;
            end
        end
    end
end

wire [1:0]  sym_out_w;
wire        sym_out_valid_w;
wire [31:0] core_dbg_pairs;
wire        pair_invalid_pulse_w;
wire [7:0]  pair_invalid_code_w;
wire        sample_phase_dbg_w;

ilc3_rx_core #(.SYMB_WIDTH(2), .AMP_WIDTH(4)) u_rx_core (
    .clk(sys_clk),
    .rst_n(rst_n),
    .frame_sync(frame_sync_q),
    .amp_in(amp_sample_q),
    .amp_in_valid(amp_valid_q),
    .amp_in_ready(),
    .sym_out(sym_out_w),
    .sym_out_valid(sym_out_valid_w),
    .sym_out_ready(1'b1),
    .dbg_pairs(core_dbg_pairs),
    .pair_invalid_pulse(pair_invalid_pulse_w),
    .pair_invalid_code(pair_invalid_code_w),
    .sample_phase_dbg(sample_phase_dbg_w)
);

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

function [7:0] expected_byte_no_crc;
    input [8:0] idx;
    input [31:0] seq;
    begin
        case (idx)
            9'd0:  expected_byte_no_crc = 8'h55;
            9'd1:  expected_byte_no_crc = 8'h55;
            9'd2:  expected_byte_no_crc = 8'hD5;
            9'd3:  expected_byte_no_crc = 8'hA5;
            9'd4:  expected_byte_no_crc = 8'h01;
            9'd5:  expected_byte_no_crc = 8'h03;
            9'd6:  expected_byte_no_crc = 8'h01;
            9'd7:  expected_byte_no_crc = 8'h00;
            9'd8:  expected_byte_no_crc = seq[31:24];
            9'd9:  expected_byte_no_crc = seq[23:16];
            9'd10: expected_byte_no_crc = seq[15:8];
            9'd11: expected_byte_no_crc = seq[7:0];
            default: expected_byte_no_crc = payload_byte(idx - 9'd12, seq);
        endcase
    end
endfunction

reg        need_resync;
reg [1:0]  sym_in_byte;
reg [5:0]  sym_in_byte_acc;
reg [8:0]  byte_idx;
reg [31:0] seq_rx;
reg [15:0] crc_acc;
reg [15:0] rx_crc;
reg        packet_bad;
reg        crc_bad;
reg [31:0] pkt_cnt;
reg [31:0] pkt_ok_cnt;
reg [31:0] pkt_ng_cnt;
reg [31:0] byte_err_cnt;
reg [31:0] crc_err_cnt;
reg [31:0] invalid_cnt;
reg [31:0] pair_invalid_cnt;
reg [31:0] tag_seen_cnt;
reg [31:0] tag_valid_cnt;
reg [31:0] tag_reject_cnt;
reg [31:0] tag_seq_error_cnt;
reg [31:0] tag_lock_cnt;
reg        tag_pending;
reg [1:0]  tag_pair_idx;
reg [15:0] data_sym_since_tag;
reg [31:0] frame_sync_cnt;
reg [31:0] resync_drop_cnt;
reg [31:0] partial_drop_cnt;
reg [31:0] pkt_byte_err;
reg [7:0]  last_byte;
reg        pass_pulse;
reg        fail_pulse;

reg [7:0] rx_byte;
reg [31:0] seq_next;
reg [15:0] crc_next;
reg [15:0] rx_crc_next;
reg        packet_bad_next;
reg        crc_bad_next;
reg [7:0]  exp_byte;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        need_resync <= 1'b1;
        sym_in_byte <= 2'd0;
        sym_in_byte_acc <= 6'd0;
        byte_idx <= 9'd0;
        seq_rx <= 32'd0;
        crc_acc <= 16'hFFFF;
        rx_crc <= 16'd0;
        packet_bad <= 1'b0;
        crc_bad <= 1'b0;
        pkt_cnt <= 32'd0;
        pkt_ok_cnt <= 32'd0;
        pkt_ng_cnt <= 32'd0;
        byte_err_cnt <= 32'd0;
        crc_err_cnt <= 32'd0;
        invalid_cnt <= 32'd0;
        pair_invalid_cnt <= 32'd0;
        tag_seen_cnt <= 32'd0;
        tag_valid_cnt <= 32'd0;
        tag_reject_cnt <= 32'd0;
        tag_seq_error_cnt <= 32'd0;
        tag_lock_cnt <= 32'd0;
        tag_pending <= 1'b0;
        tag_pair_idx <= 2'd0;
        data_sym_since_tag <= 16'd0;
        frame_sync_cnt <= 32'd0;
        resync_drop_cnt <= 32'd0;
        partial_drop_cnt <= 32'd0;
        pkt_byte_err <= 32'd0;
        last_byte <= 8'd0;
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (sync_rise) begin
            frame_sync_cnt <= frame_sync_cnt + 32'd1;
            if (!need_resync && ((byte_idx != 9'd0) || (sym_in_byte != 2'd0) || packet_bad || (pkt_byte_err != 32'd0))) begin
                resync_drop_cnt <= resync_drop_cnt + 32'd1;
                partial_drop_cnt <= partial_drop_cnt + 32'd1;
            end
            need_resync <= 1'b1;
            tag_pending <= 1'b0;
            tag_pair_idx <= 2'd0;
            data_sym_since_tag <= 16'd0;
        end

        if (sample_rise && !therm_valid(cmp_s2)) begin
            invalid_cnt <= invalid_cnt + 32'd1;
            packet_bad <= 1'b1;
            fail_pulse <= 1'b1;
        end

        if (pair_invalid_pulse_w) begin
            pair_invalid_cnt <= pair_invalid_cnt + 32'd1;
            tag_seen_cnt <= tag_seen_cnt + 32'd1;
            if ((ENABLE_TAG != 0) && tag_pending &&
                (pair_invalid_code_w == (tag_pair_idx[0] ? 8'hFF : 8'h11))) begin
                tag_valid_cnt <= tag_valid_cnt + 32'd1;
                if (tag_pair_idx == TAG_PAIR_COUNT - 1) begin
                    tag_pending <= 1'b0;
                    tag_pair_idx <= 2'd0;
                    data_sym_since_tag <= 16'd0;
                    tag_lock_cnt <= tag_lock_cnt + 32'd1;
                end else begin
                    tag_pair_idx <= tag_pair_idx + 2'd1;
                end
            end else begin
                tag_reject_cnt <= tag_reject_cnt + 32'd1;
            end
        end

        if (sym_out_valid_w) begin
            if (ENABLE_TAG != 0) begin
                if (tag_pending) begin
                    tag_seq_error_cnt <= tag_seq_error_cnt + 32'd1;
                    tag_pending <= 1'b0;
                    tag_pair_idx <= 2'd0;
                    data_sym_since_tag <= 16'd1;
                end else if (data_sym_since_tag == TAG_INTERVAL_SYMBOLS - 1) begin
                    tag_pending <= 1'b1;
                    tag_pair_idx <= 2'd0;
                end else begin
                    data_sym_since_tag <= data_sym_since_tag + 16'd1;
                end
            end
            if (need_resync) begin
                need_resync <= 1'b0;
                sym_in_byte <= 2'd1;
                sym_in_byte_acc <= {4'd0, sym_out_w};
                byte_idx <= 9'd0;
                seq_rx <= 32'd0;
                crc_acc <= 16'hFFFF;
                rx_crc <= 16'd0;
                packet_bad <= 1'b0;
                crc_bad <= 1'b0;
                pkt_byte_err <= 32'd0;
                tag_pending <= 1'b0;
                tag_pair_idx <= 2'd0;
                data_sym_since_tag <= 16'd1;
            end else begin
                sym_in_byte_acc <= {sym_in_byte_acc[3:0], sym_out_w};
                if (sym_in_byte == 2'd3) begin
                    rx_byte = {sym_in_byte_acc[5:0], sym_out_w};
                    seq_next = seq_rx;
                    crc_next = crc_acc;
                    rx_crc_next = rx_crc;
                    packet_bad_next = packet_bad;
                    crc_bad_next = 1'b0;
                    last_byte <= rx_byte;

                    case (byte_idx)
                        9'd8:  seq_next[31:24] = rx_byte;
                        9'd9:  seq_next[23:16] = rx_byte;
                        9'd10: seq_next[15:8]  = rx_byte;
                        9'd11: seq_next[7:0]   = rx_byte;
                        default: seq_next = seq_next;
                    endcase

                    if ((byte_idx >= PREAMBLE_LEN) && (byte_idx < PREAMBLE_LEN + HEADER_LEN + PAYLOAD_LEN))
                        crc_next = crc16_byte(crc_acc, rx_byte);

                    if (byte_idx < FRAME_BYTES - CRC_LEN) begin
                        exp_byte = expected_byte_no_crc(byte_idx, seq_next);
                        if (rx_byte != exp_byte) begin
                            pkt_byte_err <= pkt_byte_err + 32'd1;
                            packet_bad_next = 1'b1;
                            fail_pulse <= 1'b1;
                        end
                    end else if (byte_idx == FRAME_BYTES - 2) begin
                        rx_crc_next[15:8] = rx_byte;
                    end else begin
                        rx_crc_next[7:0] = rx_byte;
                        if ({rx_crc_next[15:8], rx_byte} != crc_acc) begin
                            crc_err_cnt <= crc_err_cnt + 32'd1;
                            packet_bad_next = 1'b1;
                            crc_bad_next = 1'b1;
                            fail_pulse <= 1'b1;
                        end
                    end

                    if (byte_idx == FRAME_BYTES - 1) begin
                        pkt_cnt <= pkt_cnt + 32'd1;
                        if (packet_bad_next) begin
                            pkt_ng_cnt <= pkt_ng_cnt + 32'd1;
                            byte_err_cnt <= byte_err_cnt + pkt_byte_err;
                        end else begin
                            pkt_ok_cnt <= pkt_ok_cnt + 32'd1;
                            pass_pulse <= 1'b1;
                        end
                        byte_idx <= 9'd0;
                        crc_acc <= 16'hFFFF;
                        rx_crc <= 16'd0;
                        packet_bad <= 1'b0;
                        crc_bad <= crc_bad_next;
                        pkt_byte_err <= 32'd0;
                    end else begin
                        byte_idx <= byte_idx + 9'd1;
                        crc_acc <= crc_next;
                        rx_crc <= rx_crc_next;
                        packet_bad <= packet_bad_next;
                        crc_bad <= crc_bad_next;
                    end

                    seq_rx <= seq_next;
                    sym_in_byte <= 2'd0;
                end else begin
                    sym_in_byte <= sym_in_byte + 2'd1;
                end
            end
        end
    end
end

function [7:0] nibble_ascii;
    input [3:0] n;
    begin
        nibble_ascii = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    end
endfunction

// "ILC3HST SH=XXXX PK=XXXXXXXX OK=XXXXXXXX NG=XXXXXXXX BE=XXXXXXXX CE=XXXXXXXX WI=XXXXXXXX FS=XXXXXXXX RS=XXXXXXXX DR=XXXXXXXX PI=XXXXXXXX TS=XXXXXXXX TV=XXXXXXXX TR=XXXXXXXX TE=XXXXXXXX TL=XXXXXXXX LB=XX HC=XXXXXXXX MC=XXXXXXXX LC=XXXXXXXX IC=XXXXXXXX DH=XXXXXXXX DM=XXXXXXXX DL=XXXXXXXX DI=XXXXXXXX FG=XX LV=X\r\n"
function [7:0] log_char;
    input [8:0] ptr;
    input [31:0] pk;
    input [31:0] ok;
    input [31:0] ng;
    input [31:0] be;
    input [31:0] ce;
    input [31:0] wi;
    input [31:0] fs;
    input [31:0] rs;
    input [31:0] dr;
    input [31:0] pi;
    input [31:0] ts;
    input [31:0] tv;
    input [31:0] tr;
    input [31:0] te;
    input [31:0] tl;
    input [7:0]  lb;
    input [31:0] hc;
    input [31:0] mc;
    input [31:0] lc;
    input [31:0] ic;
    input [31:0] dh;
    input [31:0] dm;
    input [31:0] dl;
    input [31:0] di;
    input [7:0]  fg;
    input [3:0]  lv;
    begin
        case (ptr)
            8'd0: log_char="I"; 8'd1: log_char="L"; 8'd2: log_char="C"; 8'd3: log_char="3"; 8'd4: log_char="H"; 8'd5: log_char="S"; 8'd6: log_char="T"; 8'd7: log_char=" ";
            8'd8: log_char="S"; 8'd9: log_char="H"; 8'd10: log_char="="; 8'd11: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[15:12]); 8'd12: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[11:8]); 8'd13: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[7:4]); 8'd14: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[3:0]); 8'd15: log_char=" ";
            8'd16: log_char="P"; 8'd17: log_char="K"; 8'd18: log_char="="; 8'd19: log_char=nibble_ascii(pk[31:28]); 8'd20: log_char=nibble_ascii(pk[27:24]); 8'd21: log_char=nibble_ascii(pk[23:20]); 8'd22: log_char=nibble_ascii(pk[19:16]); 8'd23: log_char=nibble_ascii(pk[15:12]); 8'd24: log_char=nibble_ascii(pk[11:8]); 8'd25: log_char=nibble_ascii(pk[7:4]); 8'd26: log_char=nibble_ascii(pk[3:0]); 8'd27: log_char=" ";
            8'd28: log_char="O"; 8'd29: log_char="K"; 8'd30: log_char="="; 8'd31: log_char=nibble_ascii(ok[31:28]); 8'd32: log_char=nibble_ascii(ok[27:24]); 8'd33: log_char=nibble_ascii(ok[23:20]); 8'd34: log_char=nibble_ascii(ok[19:16]); 8'd35: log_char=nibble_ascii(ok[15:12]); 8'd36: log_char=nibble_ascii(ok[11:8]); 8'd37: log_char=nibble_ascii(ok[7:4]); 8'd38: log_char=nibble_ascii(ok[3:0]); 8'd39: log_char=" ";
            8'd40: log_char="N"; 8'd41: log_char="G"; 8'd42: log_char="="; 8'd43: log_char=nibble_ascii(ng[31:28]); 8'd44: log_char=nibble_ascii(ng[27:24]); 8'd45: log_char=nibble_ascii(ng[23:20]); 8'd46: log_char=nibble_ascii(ng[19:16]); 8'd47: log_char=nibble_ascii(ng[15:12]); 8'd48: log_char=nibble_ascii(ng[11:8]); 8'd49: log_char=nibble_ascii(ng[7:4]); 8'd50: log_char=nibble_ascii(ng[3:0]); 8'd51: log_char=" ";
            8'd52: log_char="B"; 8'd53: log_char="E"; 8'd54: log_char="="; 8'd55: log_char=nibble_ascii(be[31:28]); 8'd56: log_char=nibble_ascii(be[27:24]); 8'd57: log_char=nibble_ascii(be[23:20]); 8'd58: log_char=nibble_ascii(be[19:16]); 8'd59: log_char=nibble_ascii(be[15:12]); 8'd60: log_char=nibble_ascii(be[11:8]); 8'd61: log_char=nibble_ascii(be[7:4]); 8'd62: log_char=nibble_ascii(be[3:0]); 8'd63: log_char=" ";
            8'd64: log_char="C"; 8'd65: log_char="E"; 8'd66: log_char="="; 8'd67: log_char=nibble_ascii(ce[31:28]); 8'd68: log_char=nibble_ascii(ce[27:24]); 8'd69: log_char=nibble_ascii(ce[23:20]); 8'd70: log_char=nibble_ascii(ce[19:16]); 8'd71: log_char=nibble_ascii(ce[15:12]); 8'd72: log_char=nibble_ascii(ce[11:8]); 8'd73: log_char=nibble_ascii(ce[7:4]); 8'd74: log_char=nibble_ascii(ce[3:0]); 8'd75: log_char=" ";
            8'd76: log_char="W"; 8'd77: log_char="I"; 8'd78: log_char="="; 8'd79: log_char=nibble_ascii(wi[31:28]); 8'd80: log_char=nibble_ascii(wi[27:24]); 8'd81: log_char=nibble_ascii(wi[23:20]); 8'd82: log_char=nibble_ascii(wi[19:16]); 8'd83: log_char=nibble_ascii(wi[15:12]); 8'd84: log_char=nibble_ascii(wi[11:8]); 8'd85: log_char=nibble_ascii(wi[7:4]); 8'd86: log_char=nibble_ascii(wi[3:0]); 8'd87: log_char=" ";
            8'd88: log_char="F"; 8'd89: log_char="S"; 8'd90: log_char="="; 8'd91: log_char=nibble_ascii(fs[31:28]); 8'd92: log_char=nibble_ascii(fs[27:24]); 8'd93: log_char=nibble_ascii(fs[23:20]); 8'd94: log_char=nibble_ascii(fs[19:16]); 8'd95: log_char=nibble_ascii(fs[15:12]); 8'd96: log_char=nibble_ascii(fs[11:8]); 8'd97: log_char=nibble_ascii(fs[7:4]); 8'd98: log_char=nibble_ascii(fs[3:0]); 8'd99: log_char=" ";
            8'd100: log_char="R"; 8'd101: log_char="S"; 8'd102: log_char="="; 8'd103: log_char=nibble_ascii(rs[31:28]); 8'd104: log_char=nibble_ascii(rs[27:24]); 8'd105: log_char=nibble_ascii(rs[23:20]); 8'd106: log_char=nibble_ascii(rs[19:16]); 8'd107: log_char=nibble_ascii(rs[15:12]); 8'd108: log_char=nibble_ascii(rs[11:8]); 8'd109: log_char=nibble_ascii(rs[7:4]); 8'd110: log_char=nibble_ascii(rs[3:0]); 8'd111: log_char=" ";
            8'd112: log_char="D"; 8'd113: log_char="R"; 8'd114: log_char="="; 8'd115: log_char=nibble_ascii(dr[31:28]); 8'd116: log_char=nibble_ascii(dr[27:24]); 8'd117: log_char=nibble_ascii(dr[23:20]); 8'd118: log_char=nibble_ascii(dr[19:16]); 8'd119: log_char=nibble_ascii(dr[15:12]); 8'd120: log_char=nibble_ascii(dr[11:8]); 8'd121: log_char=nibble_ascii(dr[7:4]); 8'd122: log_char=nibble_ascii(dr[3:0]); 8'd123: log_char=" ";
            8'd124: log_char="P"; 8'd125: log_char="I"; 8'd126: log_char="="; 8'd127: log_char=nibble_ascii(pi[31:28]); 8'd128: log_char=nibble_ascii(pi[27:24]); 8'd129: log_char=nibble_ascii(pi[23:20]); 8'd130: log_char=nibble_ascii(pi[19:16]); 8'd131: log_char=nibble_ascii(pi[15:12]); 8'd132: log_char=nibble_ascii(pi[11:8]); 8'd133: log_char=nibble_ascii(pi[7:4]); 8'd134: log_char=nibble_ascii(pi[3:0]); 8'd135: log_char=" ";
            8'd136: log_char="T"; 8'd137: log_char="S"; 8'd138: log_char="="; 8'd139: log_char=nibble_ascii(ts[31:28]); 8'd140: log_char=nibble_ascii(ts[27:24]); 8'd141: log_char=nibble_ascii(ts[23:20]); 8'd142: log_char=nibble_ascii(ts[19:16]); 8'd143: log_char=nibble_ascii(ts[15:12]); 8'd144: log_char=nibble_ascii(ts[11:8]); 8'd145: log_char=nibble_ascii(ts[7:4]); 8'd146: log_char=nibble_ascii(ts[3:0]); 8'd147: log_char=" ";
            8'd148: log_char="T"; 8'd149: log_char="V"; 8'd150: log_char="="; 8'd151: log_char=nibble_ascii(tv[31:28]); 8'd152: log_char=nibble_ascii(tv[27:24]); 8'd153: log_char=nibble_ascii(tv[23:20]); 8'd154: log_char=nibble_ascii(tv[19:16]); 8'd155: log_char=nibble_ascii(tv[15:12]); 8'd156: log_char=nibble_ascii(tv[11:8]); 8'd157: log_char=nibble_ascii(tv[7:4]); 8'd158: log_char=nibble_ascii(tv[3:0]); 8'd159: log_char=" ";
            8'd160: log_char="T"; 8'd161: log_char="R"; 8'd162: log_char="="; 8'd163: log_char=nibble_ascii(tr[31:28]); 8'd164: log_char=nibble_ascii(tr[27:24]); 8'd165: log_char=nibble_ascii(tr[23:20]); 8'd166: log_char=nibble_ascii(tr[19:16]); 8'd167: log_char=nibble_ascii(tr[15:12]); 8'd168: log_char=nibble_ascii(tr[11:8]); 8'd169: log_char=nibble_ascii(tr[7:4]); 8'd170: log_char=nibble_ascii(tr[3:0]); 8'd171: log_char=" ";
            8'd172: log_char="T"; 8'd173: log_char="E"; 8'd174: log_char="="; 8'd175: log_char=nibble_ascii(te[31:28]); 8'd176: log_char=nibble_ascii(te[27:24]); 8'd177: log_char=nibble_ascii(te[23:20]); 8'd178: log_char=nibble_ascii(te[19:16]); 8'd179: log_char=nibble_ascii(te[15:12]); 8'd180: log_char=nibble_ascii(te[11:8]); 8'd181: log_char=nibble_ascii(te[7:4]); 8'd182: log_char=nibble_ascii(te[3:0]); 8'd183: log_char=" ";
            8'd184: log_char="T"; 8'd185: log_char="L"; 8'd186: log_char="="; 8'd187: log_char=nibble_ascii(tl[31:28]); 8'd188: log_char=nibble_ascii(tl[27:24]); 8'd189: log_char=nibble_ascii(tl[23:20]); 8'd190: log_char=nibble_ascii(tl[19:16]); 8'd191: log_char=nibble_ascii(tl[15:12]); 8'd192: log_char=nibble_ascii(tl[11:8]); 8'd193: log_char=nibble_ascii(tl[7:4]); 8'd194: log_char=nibble_ascii(tl[3:0]); 8'd195: log_char=" ";
            8'd196: log_char="L"; 8'd197: log_char="B"; 8'd198: log_char="="; 8'd199: log_char=nibble_ascii(lb[7:4]); 8'd200: log_char=nibble_ascii(lb[3:0]); 8'd201: log_char=" ";
            8'd202: log_char="H"; 8'd203: log_char="C"; 8'd204: log_char="="; 8'd205: log_char=nibble_ascii(hc[31:28]); 8'd206: log_char=nibble_ascii(hc[27:24]); 8'd207: log_char=nibble_ascii(hc[23:20]); 8'd208: log_char=nibble_ascii(hc[19:16]); 8'd209: log_char=nibble_ascii(hc[15:12]); 8'd210: log_char=nibble_ascii(hc[11:8]); 8'd211: log_char=nibble_ascii(hc[7:4]); 8'd212: log_char=nibble_ascii(hc[3:0]); 8'd213: log_char=" ";
            8'd214: log_char="M"; 8'd215: log_char="C"; 8'd216: log_char="="; 8'd217: log_char=nibble_ascii(mc[31:28]); 8'd218: log_char=nibble_ascii(mc[27:24]); 8'd219: log_char=nibble_ascii(mc[23:20]); 8'd220: log_char=nibble_ascii(mc[19:16]); 8'd221: log_char=nibble_ascii(mc[15:12]); 8'd222: log_char=nibble_ascii(mc[11:8]); 8'd223: log_char=nibble_ascii(mc[7:4]); 8'd224: log_char=nibble_ascii(mc[3:0]); 8'd225: log_char=" ";
            8'd226: log_char="L"; 8'd227: log_char="C"; 8'd228: log_char="="; 8'd229: log_char=nibble_ascii(lc[31:28]); 8'd230: log_char=nibble_ascii(lc[27:24]); 8'd231: log_char=nibble_ascii(lc[23:20]); 8'd232: log_char=nibble_ascii(lc[19:16]); 8'd233: log_char=nibble_ascii(lc[15:12]); 8'd234: log_char=nibble_ascii(lc[11:8]); 8'd235: log_char=nibble_ascii(lc[7:4]); 8'd236: log_char=nibble_ascii(lc[3:0]); 8'd237: log_char=" ";
            8'd238: log_char="I"; 8'd239: log_char="C"; 8'd240: log_char="="; 8'd241: log_char=nibble_ascii(ic[31:28]); 8'd242: log_char=nibble_ascii(ic[27:24]); 8'd243: log_char=nibble_ascii(ic[23:20]); 8'd244: log_char=nibble_ascii(ic[19:16]); 8'd245: log_char=nibble_ascii(ic[15:12]); 8'd246: log_char=nibble_ascii(ic[11:8]); 8'd247: log_char=nibble_ascii(ic[7:4]); 8'd248: log_char=nibble_ascii(ic[3:0]); 8'd249: log_char=" ";
            9'd250: log_char="D"; 9'd251: log_char="H"; 9'd252: log_char="="; 9'd253: log_char=nibble_ascii(dh[31:28]); 9'd254: log_char=nibble_ascii(dh[27:24]); 9'd255: log_char=nibble_ascii(dh[23:20]); 9'd256: log_char=nibble_ascii(dh[19:16]); 9'd257: log_char=nibble_ascii(dh[15:12]); 9'd258: log_char=nibble_ascii(dh[11:8]); 9'd259: log_char=nibble_ascii(dh[7:4]); 9'd260: log_char=nibble_ascii(dh[3:0]); 9'd261: log_char=" ";
            9'd262: log_char="D"; 9'd263: log_char="M"; 9'd264: log_char="="; 9'd265: log_char=nibble_ascii(dm[31:28]); 9'd266: log_char=nibble_ascii(dm[27:24]); 9'd267: log_char=nibble_ascii(dm[23:20]); 9'd268: log_char=nibble_ascii(dm[19:16]); 9'd269: log_char=nibble_ascii(dm[15:12]); 9'd270: log_char=nibble_ascii(dm[11:8]); 9'd271: log_char=nibble_ascii(dm[7:4]); 9'd272: log_char=nibble_ascii(dm[3:0]); 9'd273: log_char=" ";
            9'd274: log_char="D"; 9'd275: log_char="L"; 9'd276: log_char="="; 9'd277: log_char=nibble_ascii(dl[31:28]); 9'd278: log_char=nibble_ascii(dl[27:24]); 9'd279: log_char=nibble_ascii(dl[23:20]); 9'd280: log_char=nibble_ascii(dl[19:16]); 9'd281: log_char=nibble_ascii(dl[15:12]); 9'd282: log_char=nibble_ascii(dl[11:8]); 9'd283: log_char=nibble_ascii(dl[7:4]); 9'd284: log_char=nibble_ascii(dl[3:0]); 9'd285: log_char=" ";
            9'd286: log_char="D"; 9'd287: log_char="I"; 9'd288: log_char="="; 9'd289: log_char=nibble_ascii(di[31:28]); 9'd290: log_char=nibble_ascii(di[27:24]); 9'd291: log_char=nibble_ascii(di[23:20]); 9'd292: log_char=nibble_ascii(di[19:16]); 9'd293: log_char=nibble_ascii(di[15:12]); 9'd294: log_char=nibble_ascii(di[11:8]); 9'd295: log_char=nibble_ascii(di[7:4]); 9'd296: log_char=nibble_ascii(di[3:0]); 9'd297: log_char=" ";
            9'd298: log_char="F"; 9'd299: log_char="G"; 9'd300: log_char="="; 9'd301: log_char=nibble_ascii(fg[7:4]); 9'd302: log_char=nibble_ascii(fg[3:0]); 9'd303: log_char=" ";
            9'd304: log_char="L"; 9'd305: log_char="V"; 9'd306: log_char="="; 9'd307: log_char=nibble_ascii(lv); 9'd308: log_char=8'h0D; 9'd309: log_char=8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_pk, log_ok, log_ng, log_be, log_ce, log_wi, log_fs, log_rs, log_dr, log_pi;
reg [31:0] log_ts, log_tv, log_tr, log_te, log_tl;
reg [31:0] log_hc, log_mc, log_lc, log_ic;
reg [31:0] log_dh, log_dm, log_dl, log_di;
reg [31:0] prev_hc, prev_mc, prev_lc, prev_ic;
reg [31:0] prev_pkt_cnt, prev_resync_drop_cnt, prev_partial_drop_cnt;
reg [7:0]  log_fg;
reg [3:0]  log_lv;
reg [7:0]  log_lb;
reg        log_req;

wire [31:0] next_dh = hist_high_cnt - prev_hc;
wire [31:0] next_dm = hist_mid_cnt - prev_mc;
wire [31:0] next_dl = hist_low_cnt - prev_lc;
wire [31:0] next_di = hist_invalid_cnt - prev_ic;
wire        flag_invalid = (next_di != 32'd0);
wire        flag_collapse = (next_dl == 32'd0) || (next_dl < DL_MIN_TH);
wire        flag_high_shift = (next_dh > DH_HIGH_TH);
wire        flag_mid_loss = (next_dm < DM_LOW_TH);
wire        flag_stall = (pkt_cnt == prev_pkt_cnt) &&
                         ((resync_drop_cnt != prev_resync_drop_cnt) ||
                          (partial_drop_cnt != prev_partial_drop_cnt));
wire        flag_packet_error = (pkt_ng_cnt != 32'd0) ||
                                (byte_err_cnt != 32'd0) ||
                                (crc_err_cnt != 32'd0);
wire        flag_warning = (next_dh > DH_WARN_TH) || (next_dm < DM_WARN_TH);
wire [7:0]  next_fg = {1'b0, flag_warning, flag_packet_error, flag_stall, flag_mid_loss, flag_high_shift, flag_collapse, flag_invalid};
wire [3:0]  next_lv =
    (flag_packet_error || flag_invalid) ? 4'd4 :
    (flag_collapse || (flag_stall && flag_high_shift)) ? 4'd3 :
    (flag_stall || (flag_high_shift && flag_mid_loss)) ? 4'd2 :
    (flag_warning || flag_high_shift || flag_mid_loss) ? 4'd1 : 4'd0;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt <= 27'd0; log_req <= 1'b0;
        log_pk <= 32'd0; log_ok <= 32'd0; log_ng <= 32'd0; log_be <= 32'd0; log_ce <= 32'd0; log_wi <= 32'd0; log_fs <= 32'd0; log_rs <= 32'd0; log_dr <= 32'd0; log_pi <= 32'd0; log_ts <= 32'd0; log_tv <= 32'd0; log_tr <= 32'd0; log_te <= 32'd0; log_tl <= 32'd0; log_lb <= 8'd0;
        log_hc <= 32'd0; log_mc <= 32'd0; log_lc <= 32'd0; log_ic <= 32'd0;
        log_dh <= 32'd0; log_dm <= 32'd0; log_dl <= 32'd0; log_di <= 32'd0;
        prev_hc <= 32'd0; prev_mc <= 32'd0; prev_lc <= 32'd0; prev_ic <= 32'd0;
        prev_pkt_cnt <= 32'd0; prev_resync_drop_cnt <= 32'd0; prev_partial_drop_cnt <= 32'd0;
        log_fg <= 8'd0; log_lv <= 4'd0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt <= 27'd0;
            log_pk <= pkt_cnt; log_ok <= pkt_ok_cnt; log_ng <= pkt_ng_cnt; log_be <= byte_err_cnt;
            log_ce <= crc_err_cnt; log_wi <= invalid_cnt; log_fs <= frame_sync_cnt; log_rs <= resync_drop_cnt; log_dr <= partial_drop_cnt; log_pi <= pair_invalid_cnt; log_lb <= last_byte;
            log_ts <= tag_seen_cnt; log_tv <= tag_valid_cnt; log_tr <= tag_reject_cnt; log_te <= tag_seq_error_cnt; log_tl <= tag_lock_cnt;
            log_hc <= hist_high_cnt; log_mc <= hist_mid_cnt; log_lc <= hist_low_cnt; log_ic <= hist_invalid_cnt;
            log_dh <= next_dh;
            log_dm <= next_dm;
            log_dl <= next_dl;
            log_di <= next_di;
            log_fg <= next_fg;
            log_lv <= next_lv;
            prev_hc <= hist_high_cnt;
            prev_mc <= hist_mid_cnt;
            prev_lc <= hist_low_cnt;
            prev_ic <= hist_invalid_cnt;
            prev_pkt_cnt <= pkt_cnt;
            prev_resync_drop_cnt <= resync_drop_cnt;
            prev_partial_drop_cnt <= partial_drop_cnt;
            log_req <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
    end
end

reg [8:0] log_ptr;
reg       log_active;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr <= 9'd0; log_active <= 1'b0; uart_start <= 1'b0; uart_data <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (log_req && !log_active && !uart_busy) begin
            log_active <= 1'b1; log_ptr <= 9'd0;
        end else if (log_active && !uart_busy && !uart_start) begin
            uart_data <= log_char(log_ptr, log_pk, log_ok, log_ng, log_be, log_ce, log_wi, log_fs, log_rs, log_dr, log_pi, log_ts, log_tv, log_tr, log_te, log_tl, log_lb, log_hc, log_mc, log_lc, log_ic, log_dh, log_dm, log_dl, log_di, log_fg, log_lv);
            uart_start <= 1'b1;
            if (log_ptr == 9'd309) log_active <= 1'b0;
            else log_ptr <= log_ptr + 9'd1;
        end
    end
end

uart_tx_simple #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
    .clk(sys_clk), .rst_n(rst_n), .start(uart_start),
    .data_in(uart_data), .tx(uart_tx), .busy(uart_busy)
);

assign led[0] = pass_pulse;
assign led[1] = fail_pulse;
assign led[2] = pkt_ok_cnt[0];
assign led[3] = uart_busy;

endmodule
