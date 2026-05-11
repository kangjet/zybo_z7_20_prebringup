`timescale 1ns/1ps
//=============================================================
// top_ilc3_analog_compare_tx_board.v
//
// ILC3 TX adapted for PAM4 analog comparison.
// It does not drive the original 4-bit ILC3 PMOD amplitude bus.
// Instead it maps ILC3 ternary samples onto the same two-pin
// resistor-DAC node used by the PAM4 baseline TX.
//
// Mapping to PAM4 resistor-DAC code:
//   -1 -> 2'b00  low
//    0 -> 2'b01  middle
//   +1 -> 2'b10  high
//=============================================================
module top_ilc3_analog_compare_tx_board #(
    parameter integer CLK_FREQ_HZ   = 125_000_000,
    parameter integer UART_BAUD     = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 125
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

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

function [7:0] crc8_byte;
    input [7:0] crc;
    input [7:0] din;
    integer i;
    reg [7:0] c;
    begin
        c = crc ^ din;
        for (i = 0; i < 8; i = i + 1)
            c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
        crc8_byte = c;
    end
endfunction

reg [31:0] pkt_seq;
reg [31:0] cur_seq;
reg [3:0]  byte_cnt;
reg [1:0]  sym_cnt;
reg        sample_idx;
reg [31:0] hold_cnt;
reg [31:0] frame_cnt;

wire [7:0] cw0 = crc8_byte(8'h00, 8'h08);
wire [7:0] cw1 = crc8_byte(cw0,   cur_seq[31:24]);
wire [7:0] cw2 = crc8_byte(cw1,   cur_seq[23:16]);
wire [7:0] cw3 = crc8_byte(cw2,   cur_seq[15: 8]);
wire [7:0] cw4 = crc8_byte(cw3,   cur_seq[ 7: 0]);
wire [7:0] cw5 = crc8_byte(cw4,   8'hDE);
wire [7:0] cw6 = crc8_byte(cw5,   8'hAD);
wire [7:0] cw7 = crc8_byte(cw6,   8'hBE);
wire [7:0] frame_crc = crc8_byte(cw7, 8'hEF);

reg [7:0] frame_byte;
always @(*) begin
    case (byte_cnt)
        4'd0:  frame_byte = 8'hAA;
        4'd1:  frame_byte = 8'h55;
        4'd2:  frame_byte = 8'h08;
        4'd3:  frame_byte = cur_seq[31:24];
        4'd4:  frame_byte = cur_seq[23:16];
        4'd5:  frame_byte = cur_seq[15: 8];
        4'd6:  frame_byte = cur_seq[ 7: 0];
        4'd7:  frame_byte = 8'hDE;
        4'd8:  frame_byte = 8'hAD;
        4'd9:  frame_byte = 8'hBE;
        4'd10: frame_byte = 8'hEF;
        default: frame_byte = frame_crc;
    endcase
end

reg [1:0] cur_sym;
always @(*) begin
    case (sym_cnt)
        2'd0: cur_sym = frame_byte[7:6];
        2'd1: cur_sym = frame_byte[5:4];
        2'd2: cur_sym = frame_byte[3:2];
        default: cur_sym = frame_byte[1:0];
    endcase
end

reg signed [1:0] amp_sample;
always @(*) begin
    case (cur_sym)
        2'd0: amp_sample = sample_idx ? 2'sd0  : -2'sd1;
        2'd1: amp_sample = sample_idx ? -2'sd1 : 2'sd0;
        2'd2: amp_sample = sample_idx ? 2'sd0  : 2'sd1;
        default: amp_sample = sample_idx ? 2'sd1 : 2'sd0;
    endcase
end

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

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        pkt_seq    <= 32'd0;
        cur_seq    <= 32'd0;
        byte_cnt   <= 4'd0;
        sym_cnt    <= 2'd0;
        sample_idx <= 1'b0;
        hold_cnt   <= 32'd0;
        frame_cnt  <= 32'd0;
        pam4_code  <= 2'b00;
        pam4_valid <= 1'b0;
        pam4_sync  <= 1'b0;
    end else begin
        pam4_code  <= code_from_amp(amp_sample);
        pam4_valid <= 1'b1;
        pam4_sync  <= (byte_cnt == 4'd0) && (sym_cnt == 2'd0) && !sample_idx;

        if (hold_cnt == SYMBOL_HOLD_CLKS - 1) begin
            hold_cnt <= 32'd0;
            if (sample_idx) begin
                sample_idx <= 1'b0;
                if (sym_cnt == 2'd3) begin
                    sym_cnt <= 2'd0;
                    if (byte_cnt == 4'd11) begin
                        byte_cnt  <= 4'd0;
                        pkt_seq   <= pkt_seq + 32'd1;
                        cur_seq   <= pkt_seq + 32'd1;
                        frame_cnt <= frame_cnt + 32'd1;
                    end else begin
                        byte_cnt <= byte_cnt + 4'd1;
                    end
                end else begin
                    sym_cnt <= sym_cnt + 2'd1;
                end
            end else begin
                sample_idx <= 1'b1;
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

// "ILC3TX CNT=XXXXXXXX C=X\r\n"
function [7:0] log_char;
    input [4:0] ptr;
    input [31:0] cnt;
    input [1:0] code;
    begin
        case (ptr)
            5'd0:  log_char = "I";
            5'd1:  log_char = "L";
            5'd2:  log_char = "C";
            5'd3:  log_char = "3";
            5'd4:  log_char = "T";
            5'd5:  log_char = "X";
            5'd6:  log_char = " ";
            5'd7:  log_char = "C";
            5'd8:  log_char = "N";
            5'd9:  log_char = "T";
            5'd10: log_char = "=";
            5'd11: log_char = nibble_ascii(cnt[31:28]);
            5'd12: log_char = nibble_ascii(cnt[27:24]);
            5'd13: log_char = nibble_ascii(cnt[23:20]);
            5'd14: log_char = nibble_ascii(cnt[19:16]);
            5'd15: log_char = nibble_ascii(cnt[15:12]);
            5'd16: log_char = nibble_ascii(cnt[11: 8]);
            5'd17: log_char = nibble_ascii(cnt[ 7: 4]);
            5'd18: log_char = nibble_ascii(cnt[ 3: 0]);
            5'd19: log_char = " ";
            5'd20: log_char = "C";
            5'd21: log_char = "=";
            5'd22: log_char = nibble_ascii({2'b00, code});
            5'd23: log_char = 8'h0D;
            5'd24: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_cnt;
reg [1:0]  log_code;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt  <= 27'd0;
        log_cnt  <= 32'd0;
        log_code <= 2'd0;
        log_req  <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt  <= 27'd0;
            log_cnt  <= frame_cnt;
            log_code <= pam4_code;
            log_req  <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
    end
end

reg [4:0] log_ptr;
reg       log_active;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr    <= 5'd0;
        log_active <= 1'b0;
        uart_start <= 1'b0;
        uart_data  <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (!log_active) begin
            if (log_req) begin
                log_ptr    <= 5'd0;
                log_active <= 1'b1;
            end
        end else if (!uart_busy && !uart_start) begin
            uart_data  <= log_char(log_ptr, log_cnt, log_code);
            uart_start <= 1'b1;
            if (log_ptr == 5'd24)
                log_active <= 1'b0;
            else
                log_ptr <= log_ptr + 5'd1;
        end
    end
end

uart_tx_simple #(
    .CLKS_PER_BIT(CLKS_PER_BIT)
) u_uart_tx (
    .clk     (sys_clk),
    .rst_n   (rst_n),
    .start   (uart_start),
    .data_in (uart_data),
    .tx      (uart_tx),
    .busy    (uart_busy)
);

assign led[0] = rst_n;
assign led[1] = pam4_valid;
assign led[2] = pam4_code[0];
assign led[3] = pam4_code[1];

endmodule
