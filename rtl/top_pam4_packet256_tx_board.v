`timescale 1ns/1ps
//=============================================================
// top_pam4_packet256_tx_board.v
//
// PAM4 packet PHY TX over the same packet format used by the
// packet256 comparison test.
//
// Frame:
//   preamble : 55 55 D5 A5
//   header   : 01 04 01 00 SEQ3 SEQ2 SEQ1 SEQ0
//              version=1, mode=PAM4(4), PSDU length=256B
//   PSDU     : 256 deterministic bytes
//   FCS      : CRC-16/CCITT-FALSE over header + PSDU
//
// Log:
//   PAM4PTX PK=XXXXXXXX SA=XXXXXXXX DP=XXXXXXXX
//=============================================================
module top_pam4_packet256_tx_board #(
    parameter integer CLK_FREQ_HZ        = 125_000_000,
    parameter integer UART_BAUD          = 115_200,
    parameter integer SYMBOL_HOLD_CLKS   = 125,
    parameter integer STROBE_OFFSET_CLKS = 100,
    parameter integer STROBE_PULSE_CLKS  = 4
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
localparam integer PAYLOAD_LEN  = 256;
localparam integer CRC_LEN      = 2;
localparam integer FRAME_BYTES  = PREAMBLE_LEN + HEADER_LEN + PAYLOAD_LEN + CRC_LEN;

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

function [7:0] packet_byte_no_crc;
    input [8:0] idx;
    input [31:0] seq;
    begin
        case (idx)
            9'd0:  packet_byte_no_crc = 8'h55;
            9'd1:  packet_byte_no_crc = 8'h55;
            9'd2:  packet_byte_no_crc = 8'hD5;
            9'd3:  packet_byte_no_crc = 8'hA5;
            9'd4:  packet_byte_no_crc = 8'h01;
            9'd5:  packet_byte_no_crc = 8'h04;
            9'd6:  packet_byte_no_crc = 8'h01;
            9'd7:  packet_byte_no_crc = 8'h00;
            9'd8:  packet_byte_no_crc = seq[31:24];
            9'd9:  packet_byte_no_crc = seq[23:16];
            9'd10: packet_byte_no_crc = seq[15:8];
            9'd11: packet_byte_no_crc = seq[7:0];
            default: packet_byte_no_crc = payload_byte(idx - 9'd12, seq);
        endcase
    end
endfunction

reg [31:0] pkt_seq;
reg [31:0] cur_seq;
reg [8:0]  byte_idx;
reg [1:0]  sym_idx;
reg [31:0] hold_cnt;
reg [31:0] sample_cnt;
reg [31:0] pkt_cnt;
reg [31:0] tx_sample_dbg;
reg [3:0]  tx_dbg_count;
reg [15:0] crc_acc;

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

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        pkt_seq       <= 32'd0;
        cur_seq       <= 32'd0;
        byte_idx      <= 9'd0;
        sym_idx       <= 2'd0;
        hold_cnt      <= 32'd0;
        sample_cnt    <= 32'd0;
        pkt_cnt       <= 32'd0;
        tx_sample_dbg <= 32'd0;
        tx_dbg_count  <= 4'd0;
        crc_acc       <= 16'hFFFF;
        pam4_code     <= 2'b00;
        pam4_valid    <= 1'b0;
        pam4_sync     <= 1'b0;
    end else begin
        pam4_code  <= cur_sym;
        pam4_valid <= (hold_cnt >= STROBE_OFFSET_CLKS) &&
                      (hold_cnt < STROBE_OFFSET_CLKS + STROBE_PULSE_CLKS);
        pam4_sync  <= (hold_cnt < STROBE_PULSE_CLKS) &&
                      (byte_idx == 9'd0) && (sym_idx == 2'd0);

        if (hold_cnt == STROBE_OFFSET_CLKS) begin
            sample_cnt <= sample_cnt + 32'd1;
            if ((byte_idx == 9'd0) && (sym_idx == 2'd0)) begin
                tx_sample_dbg <= {28'd0, 2'd0, cur_sym};
                tx_dbg_count  <= 4'd1;
            end else if (tx_dbg_count < 4'd8) begin
                tx_sample_dbg <= {tx_sample_dbg[27:0], 2'd0, cur_sym};
                tx_dbg_count  <= tx_dbg_count + 4'd1;
            end
        end

        if (hold_cnt == SYMBOL_HOLD_CLKS - 1) begin
            hold_cnt <= 32'd0;
            if (sym_idx == 2'd3) begin
                sym_idx <= 2'd0;
                if ((byte_idx >= PREAMBLE_LEN) &&
                    (byte_idx < PREAMBLE_LEN + HEADER_LEN + PAYLOAD_LEN))
                    crc_acc <= crc16_byte(crc_acc, frame_byte);
                if (byte_idx == FRAME_BYTES - 1) begin
                    byte_idx <= 9'd0;
                    pkt_seq  <= pkt_seq + 32'd1;
                    cur_seq  <= pkt_seq + 32'd1;
                    pkt_cnt  <= pkt_cnt + 32'd1;
                    crc_acc  <= 16'hFFFF;
                end else begin
                    byte_idx <= byte_idx + 9'd1;
                end
            end else begin
                sym_idx <= sym_idx + 2'd1;
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

// "PAM4PTX PK=XXXXXXXX SA=XXXXXXXX DP=XXXXXXXX\r\n"
function [7:0] log_char;
    input [5:0] ptr;
    input [31:0] pk;
    input [31:0] sa;
    input [31:0] dbg;
    begin
        case (ptr)
            6'd0:  log_char = "P"; 6'd1:  log_char = "A"; 6'd2:  log_char = "M"; 6'd3:  log_char = "4";
            6'd4:  log_char = "P"; 6'd5:  log_char = "T"; 6'd6:  log_char = "X"; 6'd7:  log_char = " ";
            6'd8:  log_char = "P"; 6'd9:  log_char = "K"; 6'd10: log_char = "=";
            6'd11: log_char = nibble_ascii(pk[31:28]); 6'd12: log_char = nibble_ascii(pk[27:24]);
            6'd13: log_char = nibble_ascii(pk[23:20]); 6'd14: log_char = nibble_ascii(pk[19:16]);
            6'd15: log_char = nibble_ascii(pk[15:12]); 6'd16: log_char = nibble_ascii(pk[11:8]);
            6'd17: log_char = nibble_ascii(pk[7:4]);   6'd18: log_char = nibble_ascii(pk[3:0]);
            6'd19: log_char = " "; 6'd20: log_char = "S"; 6'd21: log_char = "A"; 6'd22: log_char = "=";
            6'd23: log_char = nibble_ascii(sa[31:28]); 6'd24: log_char = nibble_ascii(sa[27:24]);
            6'd25: log_char = nibble_ascii(sa[23:20]); 6'd26: log_char = nibble_ascii(sa[19:16]);
            6'd27: log_char = nibble_ascii(sa[15:12]); 6'd28: log_char = nibble_ascii(sa[11:8]);
            6'd29: log_char = nibble_ascii(sa[7:4]);   6'd30: log_char = nibble_ascii(sa[3:0]);
            6'd31: log_char = " "; 6'd32: log_char = "D"; 6'd33: log_char = "P"; 6'd34: log_char = "=";
            6'd35: log_char = nibble_ascii(dbg[31:28]); 6'd36: log_char = nibble_ascii(dbg[27:24]);
            6'd37: log_char = nibble_ascii(dbg[23:20]); 6'd38: log_char = nibble_ascii(dbg[19:16]);
            6'd39: log_char = nibble_ascii(dbg[15:12]); 6'd40: log_char = nibble_ascii(dbg[11:8]);
            6'd41: log_char = nibble_ascii(dbg[7:4]);   6'd42: log_char = nibble_ascii(dbg[3:0]);
            6'd43: log_char = 8'h0D; 6'd44: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_pkt_cnt, log_sample_cnt, log_dbg;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt <= 27'd0; log_pkt_cnt <= 32'd0; log_sample_cnt <= 32'd0; log_dbg <= 32'd0; log_req <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt <= 27'd0;
            log_pkt_cnt <= pkt_cnt;
            log_sample_cnt <= sample_cnt;
            log_dbg <= tx_sample_dbg;
            log_req <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
    end
end

reg [5:0] log_ptr;
reg       log_active;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr <= 6'd0; log_active <= 1'b0; uart_start <= 1'b0; uart_data <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (log_req && !log_active && !uart_busy) begin
            log_active <= 1'b1; log_ptr <= 6'd0;
        end else if (log_active && !uart_busy && !uart_start) begin
            uart_data <= log_char(log_ptr, log_pkt_cnt, log_sample_cnt, log_dbg);
            uart_start <= 1'b1;
            if (log_ptr == 6'd44) log_active <= 1'b0;
            else log_ptr <= log_ptr + 6'd1;
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
