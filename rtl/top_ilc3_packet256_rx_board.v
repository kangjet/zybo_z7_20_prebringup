`timescale 1ns/1ps
//=============================================================
// top_ilc3_packet256_rx_board.v
//
// ILC3 packet PHY RX for 256B PSDU over the analog comparator
// path. It decodes ILC3 symbols, reconstructs packet bytes, checks
// preamble/header/payload, and verifies CRC-16/CCITT-FALSE.
//
// Log:
//   ILC3PKT SH=XXXX PK=XXXXXXXX OK=XXXXXXXX NG=XXXXXXXX
//           BE=XXXXXXXX CE=XXXXXXXX WI=XXXXXXXX FS=XXXXXXXX LB=XX
//=============================================================
module top_ilc3_packet256_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 85,
    parameter integer SAMPLE_DELAY_CLKS = 4
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

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        amp_sample_q <= 4'sd0;
        amp_valid_q <= 1'b0;
        frame_sync_q <= 1'b0;
        sample_delay_active <= 1'b0;
        sample_delay_cnt <= 8'd0;
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
            end else begin
                sample_delay_cnt <= sample_delay_cnt + 8'd1;
            end
        end
    end
end

wire [1:0]  sym_out_w;
wire        sym_out_valid_w;
wire [31:0] core_dbg_pairs;

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
    .dbg_pairs(core_dbg_pairs)
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
reg [31:0] frame_sync_cnt;
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
        frame_sync_cnt <= 32'd0;
        last_byte <= 8'd0;
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (sync_rise) begin
            frame_sync_cnt <= frame_sync_cnt + 32'd1;
            need_resync <= 1'b1;
        end

        if (sample_rise && !therm_valid(cmp_s2)) begin
            invalid_cnt <= invalid_cnt + 32'd1;
            packet_bad <= 1'b1;
            fail_pulse <= 1'b1;
        end

        if (sym_out_valid_w) begin
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
                            byte_err_cnt <= byte_err_cnt + 32'd1;
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
                        end else begin
                            pkt_ok_cnt <= pkt_ok_cnt + 32'd1;
                            pass_pulse <= 1'b1;
                        end
                        byte_idx <= 9'd0;
                        crc_acc <= 16'hFFFF;
                        rx_crc <= 16'd0;
                        packet_bad <= 1'b0;
                        crc_bad <= crc_bad_next;
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

// "ILC3PKT SH=XXXX PK=XXXXXXXX OK=XXXXXXXX NG=XXXXXXXX BE=XXXXXXXX CE=XXXXXXXX WI=XXXXXXXX FS=XXXXXXXX LB=XX\r\n"
function [7:0] log_char;
    input [7:0] ptr;
    input [31:0] pk;
    input [31:0] ok;
    input [31:0] ng;
    input [31:0] be;
    input [31:0] ce;
    input [31:0] wi;
    input [31:0] fs;
    input [7:0]  lb;
    begin
        case (ptr)
            8'd0: log_char="I"; 8'd1: log_char="L"; 8'd2: log_char="C"; 8'd3: log_char="3"; 8'd4: log_char="P"; 8'd5: log_char="K"; 8'd6: log_char="T"; 8'd7: log_char=" ";
            8'd8: log_char="S"; 8'd9: log_char="H"; 8'd10: log_char="="; 8'd11: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[15:12]); 8'd12: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[11:8]); 8'd13: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[7:4]); 8'd14: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[3:0]); 8'd15: log_char=" ";
            8'd16: log_char="P"; 8'd17: log_char="K"; 8'd18: log_char="="; 8'd19: log_char=nibble_ascii(pk[31:28]); 8'd20: log_char=nibble_ascii(pk[27:24]); 8'd21: log_char=nibble_ascii(pk[23:20]); 8'd22: log_char=nibble_ascii(pk[19:16]); 8'd23: log_char=nibble_ascii(pk[15:12]); 8'd24: log_char=nibble_ascii(pk[11:8]); 8'd25: log_char=nibble_ascii(pk[7:4]); 8'd26: log_char=nibble_ascii(pk[3:0]); 8'd27: log_char=" ";
            8'd28: log_char="O"; 8'd29: log_char="K"; 8'd30: log_char="="; 8'd31: log_char=nibble_ascii(ok[31:28]); 8'd32: log_char=nibble_ascii(ok[27:24]); 8'd33: log_char=nibble_ascii(ok[23:20]); 8'd34: log_char=nibble_ascii(ok[19:16]); 8'd35: log_char=nibble_ascii(ok[15:12]); 8'd36: log_char=nibble_ascii(ok[11:8]); 8'd37: log_char=nibble_ascii(ok[7:4]); 8'd38: log_char=nibble_ascii(ok[3:0]); 8'd39: log_char=" ";
            8'd40: log_char="N"; 8'd41: log_char="G"; 8'd42: log_char="="; 8'd43: log_char=nibble_ascii(ng[31:28]); 8'd44: log_char=nibble_ascii(ng[27:24]); 8'd45: log_char=nibble_ascii(ng[23:20]); 8'd46: log_char=nibble_ascii(ng[19:16]); 8'd47: log_char=nibble_ascii(ng[15:12]); 8'd48: log_char=nibble_ascii(ng[11:8]); 8'd49: log_char=nibble_ascii(ng[7:4]); 8'd50: log_char=nibble_ascii(ng[3:0]); 8'd51: log_char=" ";
            8'd52: log_char="B"; 8'd53: log_char="E"; 8'd54: log_char="="; 8'd55: log_char=nibble_ascii(be[31:28]); 8'd56: log_char=nibble_ascii(be[27:24]); 8'd57: log_char=nibble_ascii(be[23:20]); 8'd58: log_char=nibble_ascii(be[19:16]); 8'd59: log_char=nibble_ascii(be[15:12]); 8'd60: log_char=nibble_ascii(be[11:8]); 8'd61: log_char=nibble_ascii(be[7:4]); 8'd62: log_char=nibble_ascii(be[3:0]); 8'd63: log_char=" ";
            8'd64: log_char="C"; 8'd65: log_char="E"; 8'd66: log_char="="; 8'd67: log_char=nibble_ascii(ce[31:28]); 8'd68: log_char=nibble_ascii(ce[27:24]); 8'd69: log_char=nibble_ascii(ce[23:20]); 8'd70: log_char=nibble_ascii(ce[19:16]); 8'd71: log_char=nibble_ascii(ce[15:12]); 8'd72: log_char=nibble_ascii(ce[11:8]); 8'd73: log_char=nibble_ascii(ce[7:4]); 8'd74: log_char=nibble_ascii(ce[3:0]); 8'd75: log_char=" ";
            8'd76: log_char="W"; 8'd77: log_char="I"; 8'd78: log_char="="; 8'd79: log_char=nibble_ascii(wi[31:28]); 8'd80: log_char=nibble_ascii(wi[27:24]); 8'd81: log_char=nibble_ascii(wi[23:20]); 8'd82: log_char=nibble_ascii(wi[19:16]); 8'd83: log_char=nibble_ascii(wi[15:12]); 8'd84: log_char=nibble_ascii(wi[11:8]); 8'd85: log_char=nibble_ascii(wi[7:4]); 8'd86: log_char=nibble_ascii(wi[3:0]); 8'd87: log_char=" ";
            8'd88: log_char="F"; 8'd89: log_char="S"; 8'd90: log_char="="; 8'd91: log_char=nibble_ascii(fs[31:28]); 8'd92: log_char=nibble_ascii(fs[27:24]); 8'd93: log_char=nibble_ascii(fs[23:20]); 8'd94: log_char=nibble_ascii(fs[19:16]); 8'd95: log_char=nibble_ascii(fs[15:12]); 8'd96: log_char=nibble_ascii(fs[11:8]); 8'd97: log_char=nibble_ascii(fs[7:4]); 8'd98: log_char=nibble_ascii(fs[3:0]); 8'd99: log_char=" ";
            8'd100: log_char="L"; 8'd101: log_char="B"; 8'd102: log_char="="; 8'd103: log_char=nibble_ascii(lb[7:4]); 8'd104: log_char=nibble_ascii(lb[3:0]); 8'd105: log_char=8'h0D; 8'd106: log_char=8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_pk, log_ok, log_ng, log_be, log_ce, log_wi, log_fs;
reg [7:0]  log_lb;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt <= 27'd0; log_req <= 1'b0;
        log_pk <= 32'd0; log_ok <= 32'd0; log_ng <= 32'd0; log_be <= 32'd0; log_ce <= 32'd0; log_wi <= 32'd0; log_fs <= 32'd0; log_lb <= 8'd0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt <= 27'd0;
            log_pk <= pkt_cnt; log_ok <= pkt_ok_cnt; log_ng <= pkt_ng_cnt; log_be <= byte_err_cnt;
            log_ce <= crc_err_cnt; log_wi <= invalid_cnt; log_fs <= frame_sync_cnt; log_lb <= last_byte;
            log_req <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
    end
end

reg [7:0] log_ptr;
reg       log_active;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr <= 8'd0; log_active <= 1'b0; uart_start <= 1'b0; uart_data <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (log_req && !log_active && !uart_busy) begin
            log_active <= 1'b1; log_ptr <= 8'd0;
        end else if (log_active && !uart_busy) begin
            uart_data <= log_char(log_ptr, log_pk, log_ok, log_ng, log_be, log_ce, log_wi, log_fs, log_lb);
            uart_start <= 1'b1;
            if (log_ptr == 8'd106) log_active <= 1'b0;
            else log_ptr <= log_ptr + 8'd1;
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
