`timescale 1ns/1ps
//=============================================================
// top_ilc3_accuracy_tx_board.v
//
// ILC3 algorithm-test TX for the PAM4-comparison analog path.
// It sends the real ILC3 2-sample codebook over the resistor-DAC
// analog path, with JD7 as the per-sample strobe and JD8 as the
// first sample of each frame.
//
// Mapping to resistor-DAC code:
//   -1 -> 2'b00  low
//    0 -> 2'b01  middle
//   +1 -> 2'b10  high
//
// PMOD JD:
//   JD1/JD2 = pam4_code[0]/pam4_code[1]
//   JD7     = sample_strobe, one sys_clk pulse per ILC3 amplitude sample
//   JD8     = frame_sync, one pulse at the start of each frame
//=============================================================
module top_ilc3_accuracy_tx_board #(
    parameter integer CLK_FREQ_HZ      = 125_000_000,
    parameter integer UART_BAUD        = 115_200,
    parameter integer SYMBOL_HOLD_CLKS   = 125,
    parameter integer STROBE_OFFSET_CLKS = 62,
    parameter integer STROBE_PULSE_CLKS  = 16
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
reg [31:0] sample_cnt;
reg [31:0] frame_cnt;
reg [3:0]  pattern_phase;
reg [31:0] tx_sample_dbg;
reg [3:0]  tx_dbg_count;

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

function [1:0] alg_pattern_sym;
    input [3:0] phase;
    begin
        case (phase)
            4'd0:  alg_pattern_sym = 2'd0;
            4'd1:  alg_pattern_sym = 2'd1;
            4'd2:  alg_pattern_sym = 2'd2;
            4'd3:  alg_pattern_sym = 2'd3;
            4'd4:  alg_pattern_sym = 2'd3;
            4'd5:  alg_pattern_sym = 2'd2;
            4'd6:  alg_pattern_sym = 2'd1;
            4'd7:  alg_pattern_sym = 2'd0;
            4'd8:  alg_pattern_sym = 2'd0;
            4'd9:  alg_pattern_sym = 2'd2;
            4'd10: alg_pattern_sym = 2'd1;
            4'd11: alg_pattern_sym = 2'd3;
            4'd12: alg_pattern_sym = 2'd1;
            4'd13: alg_pattern_sym = 2'd0;
            4'd14: alg_pattern_sym = 2'd3;
            default: alg_pattern_sym = 2'd2;
        endcase
    end
endfunction

wire [1:0] cur_sym = alg_pattern_sym(pattern_phase);

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

function [1:0] accuracy_pattern_class;
    input [3:0] phase;
    begin
        case (phase)
            4'd0:  accuracy_pattern_class = 2'd0;
            4'd1:  accuracy_pattern_class = 2'd1;
            4'd2:  accuracy_pattern_class = 2'd2;
            4'd3:  accuracy_pattern_class = 2'd0;
            4'd4:  accuracy_pattern_class = 2'd2;
            4'd5:  accuracy_pattern_class = 2'd2;
            4'd6:  accuracy_pattern_class = 2'd1;
            4'd7:  accuracy_pattern_class = 2'd0;
            4'd8:  accuracy_pattern_class = 2'd1;
            4'd9:  accuracy_pattern_class = 2'd2;
            4'd10: accuracy_pattern_class = 2'd1;
            4'd11: accuracy_pattern_class = 2'd1;
            4'd12: accuracy_pattern_class = 2'd0;
            4'd13: accuracy_pattern_class = 2'd0;
            4'd14: accuracy_pattern_class = 2'd2;
            default: accuracy_pattern_class = 2'd1;
        endcase
    end
endfunction

function [1:0] code_from_class;
    input [1:0] cls;
    begin
        case (cls)
            2'd0: code_from_class = 2'b00;
            2'd1: code_from_class = 2'b01;
            2'd2: code_from_class = 2'b10;
            default: code_from_class = 2'b00;
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
        sample_cnt <= 32'd0;
            frame_cnt  <= 32'd0;
            pattern_phase <= 4'd0;
            tx_sample_dbg <= 32'd0;
            tx_dbg_count  <= 4'd0;
            pam4_code  <= 2'b00;
        pam4_valid <= 1'b0;
        pam4_sync  <= 1'b0;
    end else begin
        pam4_code  <= code_from_amp(amp_sample);
        pam4_valid <= (hold_cnt >= STROBE_OFFSET_CLKS) &&
                      (hold_cnt < STROBE_OFFSET_CLKS + STROBE_PULSE_CLKS);
        pam4_sync  <= (hold_cnt < STROBE_PULSE_CLKS) &&
                      (pattern_phase == 4'd0) && !sample_idx;

        if (hold_cnt == STROBE_OFFSET_CLKS) begin
            sample_cnt <= sample_cnt + 32'd1;
            if ((pattern_phase == 4'd0) && !sample_idx) begin
                tx_sample_dbg <= {28'd0, nibble_from_amp(amp_sample)};
                tx_dbg_count  <= 4'd1;
            end else if (tx_dbg_count < 4'd8) begin
                tx_sample_dbg <= {tx_sample_dbg[27:0], nibble_from_amp(amp_sample)};
                tx_dbg_count  <= tx_dbg_count + 4'd1;
            end
        end

        if (hold_cnt == SYMBOL_HOLD_CLKS - 1) begin
            hold_cnt <= 32'd0;
            if (sample_idx) begin
                sample_idx <= 1'b0;
                if (pattern_phase == 4'd15) begin
                    pattern_phase <= 4'd0;
                    pkt_seq   <= pkt_seq + 32'd1;
                    cur_seq   <= pkt_seq + 32'd1;
                    frame_cnt <= frame_cnt + 32'd1;
                end else begin
                    pattern_phase <= pattern_phase + 4'd1;
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

// "ILC3ATX FR=XXXXXXXX SA=XXXXXXXX C=X DP=XXXXXXXX\r\n"
function [7:0] log_char;
    input [5:0] ptr;
    input [31:0] fr;
    input [31:0] sa;
    input [1:0] code;
    input [31:0] dbg;
    begin
        case (ptr)
            6'd0:  log_char = "I";
            6'd1:  log_char = "L";
            6'd2:  log_char = "C";
            6'd3:  log_char = "3";
            6'd4:  log_char = "A";
            6'd5:  log_char = "T";
            6'd6:  log_char = "X";
            6'd7:  log_char = " ";
            6'd8:  log_char = "F";
            6'd9:  log_char = "R";
            6'd10: log_char = "=";
            6'd11: log_char = nibble_ascii(fr[31:28]);
            6'd12: log_char = nibble_ascii(fr[27:24]);
            6'd13: log_char = nibble_ascii(fr[23:20]);
            6'd14: log_char = nibble_ascii(fr[19:16]);
            6'd15: log_char = nibble_ascii(fr[15:12]);
            6'd16: log_char = nibble_ascii(fr[11: 8]);
            6'd17: log_char = nibble_ascii(fr[ 7: 4]);
            6'd18: log_char = nibble_ascii(fr[ 3: 0]);
            6'd19: log_char = " ";
            6'd20: log_char = "S";
            6'd21: log_char = "A";
            6'd22: log_char = "=";
            6'd23: log_char = nibble_ascii(sa[31:28]);
            6'd24: log_char = nibble_ascii(sa[27:24]);
            6'd25: log_char = nibble_ascii(sa[23:20]);
            6'd26: log_char = nibble_ascii(sa[19:16]);
            6'd27: log_char = nibble_ascii(sa[15:12]);
            6'd28: log_char = nibble_ascii(sa[11: 8]);
            6'd29: log_char = nibble_ascii(sa[ 7: 4]);
            6'd30: log_char = nibble_ascii(sa[ 3: 0]);
            6'd31: log_char = " ";
            6'd32: log_char = "C";
            6'd33: log_char = "=";
            6'd34: log_char = nibble_ascii({2'b00, code});
            6'd35: log_char = " ";
            6'd36: log_char = "D";
            6'd37: log_char = "P";
            6'd38: log_char = "=";
            6'd39: log_char = nibble_ascii(dbg[31:28]);
            6'd40: log_char = nibble_ascii(dbg[27:24]);
            6'd41: log_char = nibble_ascii(dbg[23:20]);
            6'd42: log_char = nibble_ascii(dbg[19:16]);
            6'd43: log_char = nibble_ascii(dbg[15:12]);
            6'd44: log_char = nibble_ascii(dbg[11: 8]);
            6'd45: log_char = nibble_ascii(dbg[ 7: 4]);
            6'd46: log_char = nibble_ascii(dbg[ 3: 0]);
            6'd47: log_char = 8'h0D;
            6'd48: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_frame_cnt;
reg [31:0] log_sample_cnt;
reg [31:0] log_dbg;
reg [1:0]  log_code;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt        <= 27'd0;
        log_frame_cnt  <= 32'd0;
        log_sample_cnt <= 32'd0;
        log_dbg        <= 32'd0;
        log_code       <= 2'd0;
        log_req        <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt        <= 27'd0;
            log_frame_cnt  <= frame_cnt;
            log_sample_cnt <= sample_cnt;
            log_dbg        <= tx_sample_dbg;
            log_code       <= pam4_code;
            log_req        <= 1'b1;
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
        log_ptr    <= 6'd0;
        log_active <= 1'b0;
        uart_start <= 1'b0;
        uart_data  <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (!log_active) begin
            if (log_req) begin
                log_ptr    <= 6'd0;
                log_active <= 1'b1;
            end
        end else if (!uart_busy && !uart_start) begin
            uart_data  <= log_char(log_ptr, log_frame_cnt, log_sample_cnt, log_code, log_dbg);
            uart_start <= 1'b1;
            if (log_ptr == 6'd48)
                log_active <= 1'b0;
            else
                log_ptr <= log_ptr + 6'd1;
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
assign led[2] = pam4_sync;
assign led[3] = pam4_code[1];

endmodule
