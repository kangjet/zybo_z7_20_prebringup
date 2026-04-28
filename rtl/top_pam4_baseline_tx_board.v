`timescale 1ns/1ps
//=============================================================
// top_pam4_baseline_tx_board.v
// TX-only PAM4 baseline pattern generator for Zybo Z7-20.
//
// Outputs a repeating 2-bit level code on PMOD JD:
//   00 -> 01 -> 10 -> 11 -> repeat
//
// The two digital pins are intended to feed an external weighted
// resistor combiner / R-2R node for real single-wire PAM4 voltage
// measurement. Without that analog combiner, AD3 will only see two
// normal 0/3.3 V digital channels.
//=============================================================
module top_pam4_baseline_tx_board #(
    parameter integer CLK_FREQ_HZ      = 125_000_000,
    parameter integer UART_BAUD        = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 125       // 1 us per PAM4 level
) (
    input  wire       sys_clk,
    input  wire       rst_btn_n,       // BTN0, Zybo: LOW=idle, HIGH=pressed

    output reg  [1:0] pam4_code,       // JD1/JD2: LSB/MSB digital code
    output reg        pam4_valid,      // JD7: 1-clk sample strobe after code settles
    output reg        pam4_sync,       // JD8: 1-clk pulse with valid at code 00

    output wire       uart_tx,
    output wire [3:0] led
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;
localparam integer SEC_COUNTS   = CLK_FREQ_HZ;
localparam integer VALID_START  = SYMBOL_HOLD_CLKS / 4;
localparam integer VALID_END    = (SYMBOL_HOLD_CLKS * 3) / 4;

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

reg [31:0] hold_cnt;
reg [31:0] cycle_cnt;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        hold_cnt   <= 32'd0;
        cycle_cnt  <= 32'd0;
        pam4_code  <= 2'b00;
        pam4_valid <= 1'b0;
        pam4_sync  <= 1'b0;
    end else begin
        pam4_valid <= (hold_cnt >= VALID_START) && (hold_cnt < VALID_END);
        pam4_sync  <= (hold_cnt >= VALID_START) && (hold_cnt < VALID_END) &&
                      (pam4_code == 2'b00);

        if (hold_cnt == SYMBOL_HOLD_CLKS - 1) begin
            hold_cnt <= 32'd0;
            if (pam4_code == 2'b11) begin
                pam4_code <= 2'b00;
                cycle_cnt <= cycle_cnt + 32'd1;
                pam4_sync <= 1'b1;
            end else begin
                pam4_code <= pam4_code + 2'b01;
            end
        end else begin
            hold_cnt <= hold_cnt + 32'd1;
        end
    end
end

function [7:0] nibble_ascii;
    input [3:0] n;
    begin
        nibble_ascii = (n < 4'd10) ? (8'h30 + {4'd0, n})
                                   : (8'h37 + {4'd0, n});
    end
endfunction

// "PAM4 CNT=XXXXXXXX C=X\r\n" (23 bytes, ptr 0..22)
function [7:0] log_char;
    input [4:0] ptr;
    input [31:0] cnt;
    input [1:0] code;
    begin
        case (ptr)
            5'd0:  log_char = 8'h50; // P
            5'd1:  log_char = 8'h41; // A
            5'd2:  log_char = 8'h4D; // M
            5'd3:  log_char = 8'h34; // 4
            5'd4:  log_char = 8'h20; // space
            5'd5:  log_char = 8'h43; // C
            5'd6:  log_char = 8'h4E; // N
            5'd7:  log_char = 8'h54; // T
            5'd8:  log_char = 8'h3D; // =
            5'd9:  log_char = nibble_ascii(cnt[31:28]);
            5'd10: log_char = nibble_ascii(cnt[27:24]);
            5'd11: log_char = nibble_ascii(cnt[23:20]);
            5'd12: log_char = nibble_ascii(cnt[19:16]);
            5'd13: log_char = nibble_ascii(cnt[15:12]);
            5'd14: log_char = nibble_ascii(cnt[11: 8]);
            5'd15: log_char = nibble_ascii(cnt[ 7: 4]);
            5'd16: log_char = nibble_ascii(cnt[ 3: 0]);
            5'd17: log_char = 8'h20; // space
            5'd18: log_char = 8'h43; // C
            5'd19: log_char = 8'h3D; // =
            5'd20: log_char = nibble_ascii({2'b00, code});
            5'd21: log_char = 8'h0D;
            5'd22: log_char = 8'h0A;
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
            log_cnt  <= cycle_cnt;
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
            if (log_ptr == 5'd22)
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
