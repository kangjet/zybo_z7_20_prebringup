`timescale 1ns/1ps
//=============================================================
// top_ilc3_analog_compare_rx_board.v
//
// ILC3 analog-comparison RX monitor for LMV339 outputs.
// This monitor is matched to the PAM4 analog comparison setup and
// decodes all three LMV339 thresholds:
//   TH2 TH1 TH0 = 000 -> W0
//                 001 -> W1
//                 011 -> W3
//                 111 -> W7
// Other thermometer states are invalid comparator ordering.
//=============================================================
module top_ilc3_analog_compare_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer STABLE_CLKS = 16
) (
    input  wire       sys_clk,
    input  wire       rst_btn_n,

    input  wire [2:0] cmp_in,
    input  wire       sync_in,

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

(* ASYNC_REG = "TRUE" *) reg [2:0] cmp_s1, cmp_s2;
always @(posedge sys_clk) begin
    cmp_s1 <= cmp_in;
    cmp_s2 <= cmp_s1;
end

(* ASYNC_REG = "TRUE" *) reg sync_s1, sync_s2, sync_s3;
always @(posedge sys_clk) begin
    sync_s1 <= sync_in;
    sync_s2 <= sync_s1;
    sync_s3 <= sync_s2;
end
wire sync_rise = sync_s2 && !sync_s3;

function synthetic_valid;
    input [2:0] raw;
    begin
        case (raw)
            3'b000, 3'b001, 3'b011, 3'b111: synthetic_valid = 1'b1;
            default:                         synthetic_valid = 1'b0;
        endcase
    end
endfunction

function [2:0] synthetic_code;
    input [2:0] raw;
    begin
        case (raw)
            3'b000: synthetic_code = 3'd0;
            3'b001: synthetic_code = 3'd1;
            3'b011: synthetic_code = 3'd3;
            3'b111: synthetic_code = 3'd7;
            default: synthetic_code = 3'd4;
        endcase
    end
endfunction

function [2:0] compare_code;
    input [2:0] raw;
    begin
        case (raw)
            3'b000: compare_code = 3'd0;
            3'b001: compare_code = 3'd3;
            3'b011: compare_code = 3'd3;
            3'b111: compare_code = 3'd7;
            default: compare_code = 3'd4;
        endcase
    end
endfunction

function [2:0] preamble_expected_code;
    input [4:0] idx;
    begin
        case (idx)
            // Visible stable sequence for bytes AA 55 08 with duplicate
            // adjacent levels removed. Middle band accepts W1 or W3.
            5'd0:  preamble_expected_code = 3'd7;
            5'd1:  preamble_expected_code = 3'd3;
            5'd2:  preamble_expected_code = 3'd7;
            5'd3:  preamble_expected_code = 3'd3;
            5'd4:  preamble_expected_code = 3'd7;
            5'd5:  preamble_expected_code = 3'd3;
            5'd6:  preamble_expected_code = 3'd7;
            5'd7:  preamble_expected_code = 3'd3;
            5'd8:  preamble_expected_code = 3'd0;
            5'd9:  preamble_expected_code = 3'd3;
            5'd10: preamble_expected_code = 3'd0;
            5'd11: preamble_expected_code = 3'd3;
            5'd12: preamble_expected_code = 3'd0;
            5'd13: preamble_expected_code = 3'd3;
            5'd14: preamble_expected_code = 3'd0;
            5'd15: preamble_expected_code = 3'd3;
            5'd16: preamble_expected_code = 3'd0;
            5'd17: preamble_expected_code = 3'd3;
            5'd18: preamble_expected_code = 3'd7;
            5'd19: preamble_expected_code = 3'd3;
            5'd20: preamble_expected_code = 3'd0;
            5'd21: preamble_expected_code = 3'd3;
            default: preamble_expected_code = 3'd4;
        endcase
    end
endfunction

reg [31:0] low_cnt;
reg [31:0] w1_cnt;
reg [31:0] mid_cnt;
reg [31:0] high_cnt;
reg [31:0] invalid_cnt;
reg [31:0] quality_warn_cnt;
reg [31:0] quality_ng_cnt;
reg [2:0]  cand_raw;
reg [2:0]  accepted_raw;
reg [7:0]  stable_cnt;
reg        have_candidate;
reg        have_accepted;
reg        pass_pulse;
reg        fail_pulse;
reg        preamble_check_active;
reg [4:0]  preamble_idx;
reg [2:0]  expected_code;

wire [2:0] cand_synth = synthetic_code(cand_raw);
wire       cand_valid = synthetic_valid(cand_raw);
wire [2:0] cand_cmp   = compare_code(cand_raw);
wire       sec_tick;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        low_cnt          <= 32'd0;
        w1_cnt           <= 32'd0;
        mid_cnt          <= 32'd0;
        high_cnt         <= 32'd0;
        invalid_cnt      <= 32'd0;
        quality_warn_cnt <= 32'd0;
        quality_ng_cnt   <= 32'd0;
        cand_raw         <= 3'd0;
        accepted_raw     <= 3'd0;
        stable_cnt       <= 8'd0;
        have_candidate   <= 1'b0;
        have_accepted    <= 1'b0;
        pass_pulse       <= 1'b0;
        fail_pulse       <= 1'b0;
        preamble_check_active <= 1'b0;
        preamble_idx          <= 5'd0;
        expected_code         <= 3'd0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (sync_rise) begin
            preamble_check_active <= 1'b0;
            preamble_idx          <= 5'd0;
            expected_code         <= synthetic_code(accepted_raw);
        end

        if (sec_tick) begin
            if (invalid_cnt != 32'd0)
                quality_ng_cnt <= quality_ng_cnt + 32'd1;
            low_cnt     <= 32'd0;
            w1_cnt      <= 32'd0;
            mid_cnt     <= 32'd0;
            high_cnt    <= 32'd0;
            invalid_cnt <= 32'd0;
        end else begin
            case (synthetic_code(cmp_s2))
                3'd0: low_cnt <= low_cnt + 32'd1;
                3'd1: w1_cnt <= w1_cnt + 32'd1;
                3'd3: mid_cnt <= mid_cnt + 32'd1;
                3'd7: high_cnt <= high_cnt + 32'd1;
                default: invalid_cnt <= invalid_cnt + 32'd1;
            endcase
        end

        if (!have_candidate || cmp_s2 != cand_raw) begin
            cand_raw       <= cmp_s2;
            stable_cnt     <= 8'd0;
            have_candidate <= 1'b1;
        end else if (stable_cnt != STABLE_TARGET) begin
            stable_cnt <= stable_cnt + 8'd1;
        end

        if (have_candidate &&
            stable_cnt == STABLE_TARGET &&
            (!have_accepted || cand_raw != accepted_raw)) begin
            accepted_raw  <= cand_raw;
            have_accepted <= 1'b1;
            if (cand_valid) begin
                pass_pulse <= 1'b1;
            end else begin
                quality_ng_cnt <= quality_ng_cnt + 32'd1;
                fail_pulse     <= 1'b1;
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

// "ILC3Q W W0=XXXXXXXX W1=XXXXXXXX W3=XXXXXXXX W7=XXXXXXXX WI=XXXXXXXX QW=XXXXXXXX QN=XXXXXXXX R=X A=X\r\n"
function [7:0] log_char;
    input [6:0] ptr;
    input [31:0] w0;
    input [31:0] w1;
    input [31:0] w3;
    input [31:0] w7;
    input [31:0] wi;
    input [31:0] qw;
    input [31:0] qn;
    input [2:0] raw_code;
    input [2:0] accepted_code;
    begin
        case (ptr)
            7'd0:  log_char = "I";
            7'd1:  log_char = "L";
            7'd2:  log_char = "C";
            7'd3:  log_char = "3";
            7'd4:  log_char = "Q";
            7'd5:  log_char = " ";
            7'd6:  log_char = "W";
            7'd7:  log_char = " ";
            7'd8:  log_char = "W";
            7'd9:  log_char = "0";
            7'd10: log_char = "=";
            7'd11: log_char = nibble_ascii(w0[31:28]);
            7'd12: log_char = nibble_ascii(w0[27:24]);
            7'd13: log_char = nibble_ascii(w0[23:20]);
            7'd14: log_char = nibble_ascii(w0[19:16]);
            7'd15: log_char = nibble_ascii(w0[15:12]);
            7'd16: log_char = nibble_ascii(w0[11: 8]);
            7'd17: log_char = nibble_ascii(w0[ 7: 4]);
            7'd18: log_char = nibble_ascii(w0[ 3: 0]);
            7'd19: log_char = " ";
            7'd20: log_char = "W";
            7'd21: log_char = "1";
            7'd22: log_char = "=";
            7'd23: log_char = nibble_ascii(w1[31:28]);
            7'd24: log_char = nibble_ascii(w1[27:24]);
            7'd25: log_char = nibble_ascii(w1[23:20]);
            7'd26: log_char = nibble_ascii(w1[19:16]);
            7'd27: log_char = nibble_ascii(w1[15:12]);
            7'd28: log_char = nibble_ascii(w1[11: 8]);
            7'd29: log_char = nibble_ascii(w1[ 7: 4]);
            7'd30: log_char = nibble_ascii(w1[ 3: 0]);
            7'd31: log_char = " ";
            7'd32: log_char = "W";
            7'd33: log_char = "3";
            7'd34: log_char = "=";
            7'd35: log_char = nibble_ascii(w3[31:28]);
            7'd36: log_char = nibble_ascii(w3[27:24]);
            7'd37: log_char = nibble_ascii(w3[23:20]);
            7'd38: log_char = nibble_ascii(w3[19:16]);
            7'd39: log_char = nibble_ascii(w3[15:12]);
            7'd40: log_char = nibble_ascii(w3[11: 8]);
            7'd41: log_char = nibble_ascii(w3[ 7: 4]);
            7'd42: log_char = nibble_ascii(w3[ 3: 0]);
            7'd43: log_char = " ";
            7'd44: log_char = "W";
            7'd45: log_char = "7";
            7'd46: log_char = "=";
            7'd47: log_char = nibble_ascii(w7[31:28]);
            7'd48: log_char = nibble_ascii(w7[27:24]);
            7'd49: log_char = nibble_ascii(w7[23:20]);
            7'd50: log_char = nibble_ascii(w7[19:16]);
            7'd51: log_char = nibble_ascii(w7[15:12]);
            7'd52: log_char = nibble_ascii(w7[11: 8]);
            7'd53: log_char = nibble_ascii(w7[ 7: 4]);
            7'd54: log_char = nibble_ascii(w7[ 3: 0]);
            7'd55: log_char = " ";
            7'd56: log_char = "W";
            7'd57: log_char = "I";
            7'd58: log_char = "=";
            7'd59: log_char = nibble_ascii(wi[31:28]);
            7'd60: log_char = nibble_ascii(wi[27:24]);
            7'd61: log_char = nibble_ascii(wi[23:20]);
            7'd62: log_char = nibble_ascii(wi[19:16]);
            7'd63: log_char = nibble_ascii(wi[15:12]);
            7'd64: log_char = nibble_ascii(wi[11: 8]);
            7'd65: log_char = nibble_ascii(wi[ 7: 4]);
            7'd66: log_char = nibble_ascii(wi[ 3: 0]);
            7'd67: log_char = " ";
            7'd68: log_char = "Q";
            7'd69: log_char = "W";
            7'd70: log_char = "=";
            7'd71: log_char = nibble_ascii(qw[31:28]);
            7'd72: log_char = nibble_ascii(qw[27:24]);
            7'd73: log_char = nibble_ascii(qw[23:20]);
            7'd74: log_char = nibble_ascii(qw[19:16]);
            7'd75: log_char = nibble_ascii(qw[15:12]);
            7'd76: log_char = nibble_ascii(qw[11: 8]);
            7'd77: log_char = nibble_ascii(qw[ 7: 4]);
            7'd78: log_char = nibble_ascii(qw[ 3: 0]);
            7'd79: log_char = " ";
            7'd80: log_char = "Q";
            7'd81: log_char = "N";
            7'd82: log_char = "=";
            7'd83: log_char = nibble_ascii(qn[31:28]);
            7'd84: log_char = nibble_ascii(qn[27:24]);
            7'd85: log_char = nibble_ascii(qn[23:20]);
            7'd86: log_char = nibble_ascii(qn[19:16]);
            7'd87: log_char = nibble_ascii(qn[15:12]);
            7'd88: log_char = nibble_ascii(qn[11: 8]);
            7'd89: log_char = nibble_ascii(qn[ 7: 4]);
            7'd90: log_char = nibble_ascii(qn[ 3: 0]);
            7'd91: log_char = " ";
            7'd92: log_char = "R";
            7'd93: log_char = "=";
            7'd94: log_char = nibble_ascii({1'b0, raw_code});
            7'd95: log_char = " ";
            7'd96: log_char = "A";
            7'd97: log_char = "=";
            7'd98: log_char = nibble_ascii({1'b0, accepted_code});
            7'd99: log_char = 8'h0D;
            7'd100: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_w0;
reg [31:0] log_w1;
reg [31:0] log_w3;
reg [31:0] log_w7;
reg [31:0] log_wi;
reg [31:0] log_qw;
reg [31:0] log_qn;
reg [2:0]  log_raw;
reg [2:0]  log_accepted;
reg        log_req;

assign sec_tick = (sec_cnt == SEC_COUNTS - 1);

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt      <= 27'd0;
        log_w0       <= 32'd0;
        log_w1       <= 32'd0;
        log_w3       <= 32'd0;
        log_w7       <= 32'd0;
        log_wi       <= 32'd0;
        log_qw       <= 32'd0;
        log_qn       <= 32'd0;
        log_raw      <= 3'd0;
        log_accepted <= 3'd0;
        log_req      <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_tick) begin
            sec_cnt      <= 27'd0;
            log_w0       <= low_cnt;
            log_w1       <= w1_cnt;
            log_w3       <= mid_cnt;
            log_w7       <= high_cnt;
            log_wi       <= invalid_cnt;
            log_qw       <= quality_warn_cnt;
            log_qn       <= quality_ng_cnt;
            log_raw      <= synthetic_code(cmp_s2);
            log_accepted <= synthetic_code(accepted_raw);
            log_req      <= 1'b1;
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
            uart_data  <= log_char(log_ptr, log_w0, log_w1, log_w3, log_w7, log_wi, log_qw, log_qn, log_raw, log_accepted);
            uart_start <= 1'b1;
            if (log_ptr == 7'd100)
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
assign led[1] = synthetic_valid(cmp_s2);
assign led[2] = pass_pulse;
assign led[3] = fail_pulse;

endmodule
