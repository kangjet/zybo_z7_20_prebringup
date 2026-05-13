`timescale 1ns/1ps
//=============================================================
// top_pam4_accuracy_tx_board.v
//
// PAM4 accuracy-test TX for direct comparison with ILC3BER.
// JD7 is a one-clock sample strobe and JD8 is a frame-start strobe.
//
// PAM4 class/code mapping:
//   0 -> 2'b00
//   1 -> 2'b01
//   2 -> 2'b10
//   3 -> 2'b11
//
// PMOD JD:
//   JD1/JD2 = pam4_code[0]/pam4_code[1]
//   JD7     = sample_strobe, one sys_clk pulse per sample
//   JD8     = frame_sync, one sys_clk pulse at pattern phase 0
//=============================================================
module top_pam4_accuracy_tx_board #(
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

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

function [1:0] accuracy_pattern_class;
    input [3:0] phase;
    begin
        case (phase)
            4'd0:  accuracy_pattern_class = 2'd0;
            4'd1:  accuracy_pattern_class = 2'd1;
            4'd2:  accuracy_pattern_class = 2'd2;
            4'd3:  accuracy_pattern_class = 2'd3;
            4'd4:  accuracy_pattern_class = 2'd3;
            4'd5:  accuracy_pattern_class = 2'd2;
            4'd6:  accuracy_pattern_class = 2'd1;
            4'd7:  accuracy_pattern_class = 2'd0;
            4'd8:  accuracy_pattern_class = 2'd0;
            4'd9:  accuracy_pattern_class = 2'd2;
            4'd10: accuracy_pattern_class = 2'd1;
            4'd11: accuracy_pattern_class = 2'd3;
            4'd12: accuracy_pattern_class = 2'd1;
            4'd13: accuracy_pattern_class = 2'd0;
            4'd14: accuracy_pattern_class = 2'd3;
            default: accuracy_pattern_class = 2'd2;
        endcase
    end
endfunction

reg [31:0] hold_cnt;
reg [31:0] sample_cnt;
reg [31:0] frame_cnt;
reg [3:0]  pattern_phase;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        hold_cnt      <= 32'd0;
        sample_cnt    <= 32'd0;
        frame_cnt     <= 32'd0;
        pattern_phase <= 4'd0;
        pam4_code     <= 2'b00;
        pam4_valid    <= 1'b0;
        pam4_sync     <= 1'b0;
    end else begin
        pam4_code  <= accuracy_pattern_class(pattern_phase);
        pam4_valid <= (hold_cnt >= STROBE_OFFSET_CLKS) &&
                      (hold_cnt < STROBE_OFFSET_CLKS + STROBE_PULSE_CLKS);
        pam4_sync  <= (hold_cnt >= STROBE_OFFSET_CLKS) &&
                      (hold_cnt < STROBE_OFFSET_CLKS + STROBE_PULSE_CLKS) &&
                      (pattern_phase == 4'd0);

        if (hold_cnt == STROBE_OFFSET_CLKS)
            sample_cnt <= sample_cnt + 32'd1;

        if (hold_cnt == SYMBOL_HOLD_CLKS - 1) begin
            hold_cnt <= 32'd0;
            pattern_phase <= pattern_phase + 4'd1;
            if (pattern_phase == 4'd15)
                frame_cnt <= frame_cnt + 32'd1;
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

// "PAM4ATX SH=XXXX FR=XXXXXXXX SA=XXXXXXXX C=X\r\n"
function [7:0] log_char;
    input [6:0] ptr;
    input [31:0] fr;
    input [31:0] sa;
    input [1:0] code;
    begin
        case (ptr)
            7'd0:  log_char = "P";
            7'd1:  log_char = "A";
            7'd2:  log_char = "M";
            7'd3:  log_char = "4";
            7'd4:  log_char = "A";
            7'd5:  log_char = "T";
            7'd6:  log_char = "X";
            7'd7:  log_char = " ";
            7'd8:  log_char = "S";
            7'd9:  log_char = "H";
            7'd10: log_char = "=";
            7'd11: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[15:12]);
            7'd12: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[11: 8]);
            7'd13: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[ 7: 4]);
            7'd14: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[ 3: 0]);
            7'd15: log_char = " ";
            7'd16: log_char = "F";
            7'd17: log_char = "R";
            7'd18: log_char = "=";
            7'd19: log_char = nibble_ascii(fr[31:28]);
            7'd20: log_char = nibble_ascii(fr[27:24]);
            7'd21: log_char = nibble_ascii(fr[23:20]);
            7'd22: log_char = nibble_ascii(fr[19:16]);
            7'd23: log_char = nibble_ascii(fr[15:12]);
            7'd24: log_char = nibble_ascii(fr[11: 8]);
            7'd25: log_char = nibble_ascii(fr[ 7: 4]);
            7'd26: log_char = nibble_ascii(fr[ 3: 0]);
            7'd27: log_char = " ";
            7'd28: log_char = "S";
            7'd29: log_char = "A";
            7'd30: log_char = "=";
            7'd31: log_char = nibble_ascii(sa[31:28]);
            7'd32: log_char = nibble_ascii(sa[27:24]);
            7'd33: log_char = nibble_ascii(sa[23:20]);
            7'd34: log_char = nibble_ascii(sa[19:16]);
            7'd35: log_char = nibble_ascii(sa[15:12]);
            7'd36: log_char = nibble_ascii(sa[11: 8]);
            7'd37: log_char = nibble_ascii(sa[ 7: 4]);
            7'd38: log_char = nibble_ascii(sa[ 3: 0]);
            7'd39: log_char = " ";
            7'd40: log_char = "C";
            7'd41: log_char = "=";
            7'd42: log_char = nibble_ascii({2'b00, code});
            7'd43: log_char = 8'h0D;
            7'd44: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_frame_cnt;
reg [31:0] log_sample_cnt;
reg [1:0]  log_code;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt        <= 27'd0;
        log_frame_cnt  <= 32'd0;
        log_sample_cnt <= 32'd0;
        log_code       <= 2'd0;
        log_req        <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt        <= 27'd0;
            log_frame_cnt  <= frame_cnt;
            log_sample_cnt <= sample_cnt;
            log_code       <= pam4_code;
            log_req        <= 1'b1;
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
        log_ptr    <= 7'd0;
        log_active <= 1'b0;
        uart_start <= 1'b0;
        uart_data  <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (!log_active) begin
            if (log_req) begin
                log_ptr    <= 7'd0;
                log_active <= 1'b1;
            end
        end else if (!uart_busy && !uart_start) begin
            uart_data  <= log_char(log_ptr, log_frame_cnt, log_sample_cnt, log_code);
            uart_start <= 1'b1;
            if (log_ptr == 7'd44)
                log_active <= 1'b0;
            else
                log_ptr <= log_ptr + 7'd1;
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
