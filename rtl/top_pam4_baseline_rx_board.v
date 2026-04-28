`timescale 1ns/1ps
//=============================================================
// top_pam4_baseline_rx_board.v
// RX-side monitor for the PAM4 baseline TX pattern.
//
// This validates the two digital bits that feed the external PAM4
// resistor combiner. It does not decode a single analog PAM4 wire.
// True analog PAM4 RX needs an ADC/XADC path or external comparators.
//=============================================================
module top_pam4_baseline_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer STABLE_CLKS = 16
) (
    input  wire       sys_clk,
    input  wire       rst_btn_n,       // BTN0, Zybo: LOW=idle, HIGH=pressed

    input  wire [1:0] pam4_code_in,    // JD1/JD2 from TX
    input  wire       pam4_valid_in,   // JD7 sample strobe from TX
    input  wire       pam4_sync_in,    // JD8 from TX

    output wire       uart_tx,
    output wire [3:0] led
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;
localparam integer SEC_COUNTS   = CLK_FREQ_HZ;
localparam [7:0]   STABLE_TARGET = STABLE_CLKS;

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

(* ASYNC_REG = "TRUE" *) reg [1:0] code_s1, code_s2;
(* ASYNC_REG = "TRUE" *) reg       valid_s1, valid_s2;
(* ASYNC_REG = "TRUE" *) reg       sync_s1, sync_s2;

always @(posedge sys_clk) begin
    code_s1  <= pam4_code_in;
    code_s2  <= code_s1;
    valid_s1 <= pam4_valid_in;
    valid_s2 <= valid_s1;
    sync_s1  <= pam4_sync_in;
    sync_s2  <= sync_s1;
end

reg [31:0] ok_cnt;
reg [31:0] ng_cnt;
reg [1:0]  last_code;
reg [1:0]  cand_code;
reg [1:0]  accepted_code;
reg [7:0]  stable_cnt;
reg        locked;
reg        pass_pulse;
reg        fail_pulse;
reg        have_candidate;
reg        have_accepted;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        ok_cnt        <= 32'd0;
        ng_cnt        <= 32'd0;
        last_code     <= 2'd0;
        cand_code     <= 2'd0;
        accepted_code <= 2'd0;
        stable_cnt    <= 8'd0;
        locked        <= 1'b0;
        pass_pulse    <= 1'b0;
        fail_pulse    <= 1'b0;
        have_candidate <= 1'b0;
        have_accepted  <= 1'b0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (!have_candidate || code_s2 != cand_code) begin
            cand_code      <= code_s2;
            stable_cnt     <= 8'd0;
            have_candidate <= 1'b1;
        end else if (stable_cnt != STABLE_TARGET) begin
            stable_cnt <= stable_cnt + 8'd1;
        end

        if (have_candidate &&
            stable_cnt == STABLE_TARGET &&
            (!have_accepted || cand_code != accepted_code)) begin
            accepted_code <= cand_code;
            have_accepted <= 1'b1;

            if (!locked) begin
                locked    <= 1'b1;
                ok_cnt    <= ok_cnt + 32'd1;
                pass_pulse <= 1'b1;
            end else if (cand_code == last_code + 2'b01) begin
                ok_cnt     <= ok_cnt + 32'd1;
                pass_pulse <= 1'b1;
            end else if (cand_code == 2'b00 && last_code == 2'b11) begin
                ok_cnt     <= ok_cnt + 32'd1;
                pass_pulse <= 1'b1;
            end else begin
                if (sync_s2 && cand_code == 2'b00) begin
                    locked     <= 1'b1;
                    ok_cnt     <= ok_cnt + 32'd1;
                    pass_pulse <= 1'b1;
                end else begin
                    ng_cnt     <= ng_cnt + 32'd1;
                    fail_pulse <= 1'b1;
                end
            end
            last_code <= cand_code;
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

// "PAM4RX OK=XXXXXXXX NG=XXXXXXXX C=X\r\n" (36 bytes, ptr 0..35)
function [7:0] log_char;
    input [5:0] ptr;
    input [31:0] ok;
    input [31:0] ng;
    input [1:0] code;
    begin
        case (ptr)
            6'd0:  log_char = 8'h50; // P
            6'd1:  log_char = 8'h41; // A
            6'd2:  log_char = 8'h4D; // M
            6'd3:  log_char = 8'h34; // 4
            6'd4:  log_char = 8'h52; // R
            6'd5:  log_char = 8'h58; // X
            6'd6:  log_char = 8'h20; // space
            6'd7:  log_char = 8'h4F; // O
            6'd8:  log_char = 8'h4B; // K
            6'd9:  log_char = 8'h3D; // =
            6'd10: log_char = nibble_ascii(ok[31:28]);
            6'd11: log_char = nibble_ascii(ok[27:24]);
            6'd12: log_char = nibble_ascii(ok[23:20]);
            6'd13: log_char = nibble_ascii(ok[19:16]);
            6'd14: log_char = nibble_ascii(ok[15:12]);
            6'd15: log_char = nibble_ascii(ok[11: 8]);
            6'd16: log_char = nibble_ascii(ok[ 7: 4]);
            6'd17: log_char = nibble_ascii(ok[ 3: 0]);
            6'd18: log_char = 8'h20; // space
            6'd19: log_char = 8'h4E; // N
            6'd20: log_char = 8'h47; // G
            6'd21: log_char = 8'h3D; // =
            6'd22: log_char = nibble_ascii(ng[31:28]);
            6'd23: log_char = nibble_ascii(ng[27:24]);
            6'd24: log_char = nibble_ascii(ng[23:20]);
            6'd25: log_char = nibble_ascii(ng[19:16]);
            6'd26: log_char = nibble_ascii(ng[15:12]);
            6'd27: log_char = nibble_ascii(ng[11: 8]);
            6'd28: log_char = nibble_ascii(ng[ 7: 4]);
            6'd29: log_char = nibble_ascii(ng[ 3: 0]);
            6'd30: log_char = 8'h20; // space
            6'd31: log_char = 8'h43; // C
            6'd32: log_char = 8'h3D; // =
            6'd33: log_char = nibble_ascii({2'b00, code});
            6'd34: log_char = 8'h0D;
            6'd35: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_ok;
reg [31:0] log_ng;
reg [1:0]  log_code;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt  <= 27'd0;
        log_ok   <= 32'd0;
        log_ng   <= 32'd0;
        log_code <= 2'd0;
        log_req  <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt  <= 27'd0;
            log_ok   <= ok_cnt;
            log_ng   <= ng_cnt;
            log_code <= last_code;
            log_req  <= 1'b1;
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
            uart_data  <= log_char(log_ptr, log_ok, log_ng, log_code);
            uart_start <= 1'b1;
            if (log_ptr == 6'd35)
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
assign led[1] = valid_s2;
assign led[2] = pass_pulse;
assign led[3] = fail_pulse;

endmodule
