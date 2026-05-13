`timescale 1ns/1ps
//=============================================================
// top_pam4_accuracy_rx_board.v
//
// PAM4 accuracy-test RX for direct comparison with ILC3BER.
// It samples LMV339 thermometer outputs only on TX JD7 strobe,
// auto-locks to the deterministic 16-sample TX pattern, and logs
// BER-style counters using the same field structure as ILC3BER.
//
// Log:
//   PAM4BER SH=XXXX OK=XXXXXXXX SE=XXXXXXXX FS=XXXXXXXX WI=XXXXXXXX
//           QN=XXXXXXXX R=X E=X L=X
//
// SH : TX symbol hold clocks used for this speed-test bitstream
// OK : matched samples after lock
// SE : expected-vs-received symbol mismatches after lock
// FS : frame sync count from TX JD8, reference only
// WI : invalid thermometer order samples
// QN : total error count, SE + WI
// R  : last received class, 0/1/2/3/F
// E  : last expected class, 0/1/2/3
// L  : lock flag
//=============================================================
module top_pam4_accuracy_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 125
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

function [2:0] rx_class;
    input [2:0] raw;
    begin
        case (raw)
            3'b000: rx_class = 3'd0;
            3'b001: rx_class = 3'd1;
            3'b011: rx_class = 3'd2;
            3'b111: rx_class = 3'd3;
            default: rx_class = 3'd4;
        endcase
    end
endfunction

function [2:0] accuracy_pattern_class;
    input [3:0] phase;
    begin
        case (phase)
            4'd0:  accuracy_pattern_class = 3'd0;
            4'd1:  accuracy_pattern_class = 3'd1;
            4'd2:  accuracy_pattern_class = 3'd2;
            4'd3:  accuracy_pattern_class = 3'd3;
            4'd4:  accuracy_pattern_class = 3'd3;
            4'd5:  accuracy_pattern_class = 3'd2;
            4'd6:  accuracy_pattern_class = 3'd1;
            4'd7:  accuracy_pattern_class = 3'd0;
            4'd8:  accuracy_pattern_class = 3'd0;
            4'd9:  accuracy_pattern_class = 3'd2;
            4'd10: accuracy_pattern_class = 3'd1;
            4'd11: accuracy_pattern_class = 3'd3;
            4'd12: accuracy_pattern_class = 3'd1;
            4'd13: accuracy_pattern_class = 3'd0;
            4'd14: accuracy_pattern_class = 3'd3;
            default: accuracy_pattern_class = 3'd2;
        endcase
    end
endfunction

function [2:0] hist_class;
    input [47:0] hist;
    input [3:0] idx;
    begin
        case (idx)
            4'd0:  hist_class = hist[47:45];
            4'd1:  hist_class = hist[44:42];
            4'd2:  hist_class = hist[41:39];
            4'd3:  hist_class = hist[38:36];
            4'd4:  hist_class = hist[35:33];
            4'd5:  hist_class = hist[32:30];
            4'd6:  hist_class = hist[29:27];
            4'd7:  hist_class = hist[26:24];
            4'd8:  hist_class = hist[23:21];
            4'd9:  hist_class = hist[20:18];
            4'd10: hist_class = hist[17:15];
            4'd11: hist_class = hist[14:12];
            4'd12: hist_class = hist[11:9];
            4'd13: hist_class = hist[8:6];
            4'd14: hist_class = hist[5:3];
            default: hist_class = hist[2:0];
        endcase
    end
endfunction

function history_matches;
    input [47:0] hist;
    input [3:0] offset;
    integer j;
    begin
        history_matches = 1'b1;
        for (j = 0; j < 16; j = j + 1) begin
            if (hist_class(hist, j[3:0]) != accuracy_pattern_class(offset + j[3:0]))
                history_matches = 1'b0;
        end
    end
endfunction

reg [3:0]  pattern_phase;
reg [47:0] class_hist;
reg [4:0]  hist_count;
reg        locked;

reg [31:0] ok_cnt;
reg [31:0] sym_err_cnt;
reg [31:0] frame_sync_cnt;
reg [31:0] invalid_cnt;
reg [31:0] qn_cnt;
reg [2:0]  last_rx_class;
reg [2:0]  last_exp_class;
reg        pass_pulse;
reg        fail_pulse;
reg [47:0] next_hist;
reg [4:0]  next_hist_count;
reg [4:0]  match_count;
reg [3:0]  found_phase;
reg [2:0]  sample_expected_class;
reg        sync_pending;
reg        sync_sample_now;
integer    phase_i;

wire [2:0] current_rx_class = rx_class(cmp_s2);
wire [2:0] expected_class   = accuracy_pattern_class(pattern_phase);

task advance_expected;
    begin
        pattern_phase <= pattern_phase + 4'd1;
    end
endtask

task update_lock_history;
    input [2:0] sample_class;
    begin
        next_hist = {class_hist[44:0], sample_class};
        next_hist_count = (hist_count == 5'd16) ? 5'd16 : (hist_count + 5'd1);
        class_hist <= next_hist;
        hist_count <= next_hist_count;

        if (next_hist_count == 5'd16) begin
            match_count = 5'd0;
            found_phase = 4'd0;
            for (phase_i = 0; phase_i < 16; phase_i = phase_i + 1) begin
                if (history_matches(next_hist, phase_i[3:0])) begin
                    match_count = match_count + 5'd1;
                    found_phase = phase_i[3:0];
                end
            end
            if (match_count == 5'd1) begin
                locked        <= 1'b1;
                pattern_phase <= found_phase;
            end
        end
    end
endtask

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        pattern_phase  <= 4'd0;
        class_hist     <= 48'd0;
        hist_count     <= 5'd0;
        locked         <= 1'b0;
        ok_cnt         <= 32'd0;
        sym_err_cnt    <= 32'd0;
        frame_sync_cnt <= 32'd0;
        invalid_cnt    <= 32'd0;
        qn_cnt         <= 32'd0;
        last_rx_class  <= 3'd0;
        last_exp_class <= 3'd0;
        pass_pulse     <= 1'b0;
        fail_pulse     <= 1'b0;
        sync_pending   <= 1'b0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (sync_rise) begin
            frame_sync_cnt <= frame_sync_cnt + 32'd1;
            sync_pending   <= 1'b1;
        end

        if (sample_rise) begin
            sync_sample_now = sync_pending || sync_rise;
            sample_expected_class = sync_sample_now ? accuracy_pattern_class(4'd0) : expected_class;
            sync_pending <= 1'b0;

            last_rx_class  <= current_rx_class;
            last_exp_class <= sample_expected_class;

            if (!therm_valid(cmp_s2)) begin
                invalid_cnt <= invalid_cnt + 32'd1;
                qn_cnt      <= qn_cnt + 32'd1;
                fail_pulse  <= 1'b1;
                locked      <= 1'b0;
                hist_count  <= 5'd0;
            end else if (locked) begin
                if (current_rx_class == sample_expected_class) begin
                    ok_cnt     <= ok_cnt + 32'd1;
                    pass_pulse <= 1'b1;
                end else begin
                    sym_err_cnt <= sym_err_cnt + 32'd1;
                    qn_cnt      <= qn_cnt + 32'd1;
                    fail_pulse  <= 1'b1;
                end
                pattern_phase <= sync_sample_now ? 4'd1 : (pattern_phase + 4'd1);
            end else if (sync_sample_now) begin
                locked <= 1'b1;
                if (current_rx_class == accuracy_pattern_class(4'd0)) begin
                    ok_cnt     <= ok_cnt + 32'd1;
                    pass_pulse <= 1'b1;
                end else begin
                    sym_err_cnt <= sym_err_cnt + 32'd1;
                    qn_cnt      <= qn_cnt + 32'd1;
                    fail_pulse  <= 1'b1;
                end
                pattern_phase <= 4'd1;
            end else begin
                update_lock_history(current_rx_class);
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

function [7:0] class_ascii;
    input [2:0] c;
    begin
        case (c)
            3'd0: class_ascii = "0";
            3'd1: class_ascii = "1";
            3'd2: class_ascii = "2";
            3'd3: class_ascii = "3";
            default: class_ascii = "F";
        endcase
    end
endfunction

// "PAM4BER SH=XXXX OK=XXXXXXXX SE=XXXXXXXX FS=XXXXXXXX WI=XXXXXXXX QN=XXXXXXXX R=X E=X L=X\r\n"
function [7:0] log_char;
    input [6:0] ptr;
    input [31:0] ok;
    input [31:0] se;
    input [31:0] fe;
    input [31:0] wi;
    input [31:0] qn;
    input [2:0] rxc;
    input [2:0] exc;
    input        lock;
    begin
        case (ptr)
            7'd0:  log_char = "P";
            7'd1:  log_char = "A";
            7'd2:  log_char = "M";
            7'd3:  log_char = "4";
            7'd4:  log_char = "B";
            7'd5:  log_char = "E";
            7'd6:  log_char = "R";
            7'd7:  log_char = " ";
            7'd8:  log_char = "S";
            7'd9:  log_char = "H";
            7'd10: log_char = "=";
            7'd11: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[15:12]);
            7'd12: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[11: 8]);
            7'd13: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[ 7: 4]);
            7'd14: log_char = nibble_ascii(SYMBOL_HOLD_CLKS[ 3: 0]);
            7'd15: log_char = " ";
            7'd16: log_char = "O";
            7'd17: log_char = "K";
            7'd18: log_char = "=";
            7'd19: log_char = nibble_ascii(ok[31:28]);
            7'd20: log_char = nibble_ascii(ok[27:24]);
            7'd21: log_char = nibble_ascii(ok[23:20]);
            7'd22: log_char = nibble_ascii(ok[19:16]);
            7'd23: log_char = nibble_ascii(ok[15:12]);
            7'd24: log_char = nibble_ascii(ok[11: 8]);
            7'd25: log_char = nibble_ascii(ok[ 7: 4]);
            7'd26: log_char = nibble_ascii(ok[ 3: 0]);
            7'd27: log_char = " ";
            7'd28: log_char = "S";
            7'd29: log_char = "E";
            7'd30: log_char = "=";
            7'd31: log_char = nibble_ascii(se[31:28]);
            7'd32: log_char = nibble_ascii(se[27:24]);
            7'd33: log_char = nibble_ascii(se[23:20]);
            7'd34: log_char = nibble_ascii(se[19:16]);
            7'd35: log_char = nibble_ascii(se[15:12]);
            7'd36: log_char = nibble_ascii(se[11: 8]);
            7'd37: log_char = nibble_ascii(se[ 7: 4]);
            7'd38: log_char = nibble_ascii(se[ 3: 0]);
            7'd39: log_char = " ";
            7'd40: log_char = "F";
            7'd41: log_char = "S";
            7'd42: log_char = "=";
            7'd43: log_char = nibble_ascii(fe[31:28]);
            7'd44: log_char = nibble_ascii(fe[27:24]);
            7'd45: log_char = nibble_ascii(fe[23:20]);
            7'd46: log_char = nibble_ascii(fe[19:16]);
            7'd47: log_char = nibble_ascii(fe[15:12]);
            7'd48: log_char = nibble_ascii(fe[11: 8]);
            7'd49: log_char = nibble_ascii(fe[ 7: 4]);
            7'd50: log_char = nibble_ascii(fe[ 3: 0]);
            7'd51: log_char = " ";
            7'd52: log_char = "W";
            7'd53: log_char = "I";
            7'd54: log_char = "=";
            7'd55: log_char = nibble_ascii(wi[31:28]);
            7'd56: log_char = nibble_ascii(wi[27:24]);
            7'd57: log_char = nibble_ascii(wi[23:20]);
            7'd58: log_char = nibble_ascii(wi[19:16]);
            7'd59: log_char = nibble_ascii(wi[15:12]);
            7'd60: log_char = nibble_ascii(wi[11: 8]);
            7'd61: log_char = nibble_ascii(wi[ 7: 4]);
            7'd62: log_char = nibble_ascii(wi[ 3: 0]);
            7'd63: log_char = " ";
            7'd64: log_char = "Q";
            7'd65: log_char = "N";
            7'd66: log_char = "=";
            7'd67: log_char = nibble_ascii(qn[31:28]);
            7'd68: log_char = nibble_ascii(qn[27:24]);
            7'd69: log_char = nibble_ascii(qn[23:20]);
            7'd70: log_char = nibble_ascii(qn[19:16]);
            7'd71: log_char = nibble_ascii(qn[15:12]);
            7'd72: log_char = nibble_ascii(qn[11: 8]);
            7'd73: log_char = nibble_ascii(qn[ 7: 4]);
            7'd74: log_char = nibble_ascii(qn[ 3: 0]);
            7'd75: log_char = " ";
            7'd76: log_char = "R";
            7'd77: log_char = "=";
            7'd78: log_char = class_ascii(rxc);
            7'd79: log_char = " ";
            7'd80: log_char = "E";
            7'd81: log_char = "=";
            7'd82: log_char = class_ascii(exc);
            7'd83: log_char = " ";
            7'd84: log_char = "L";
            7'd85: log_char = "=";
            7'd86: log_char = lock ? "1" : "0";
            7'd87: log_char = 8'h0D;
            7'd88: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_ok, log_se, log_fe, log_wi, log_qn;
reg [2:0]  log_rxc, log_exc;
reg        log_lock;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt  <= 27'd0;
        log_ok   <= 32'd0;
        log_se   <= 32'd0;
        log_fe   <= 32'd0;
        log_wi   <= 32'd0;
        log_qn   <= 32'd0;
        log_rxc  <= 3'd0;
        log_exc  <= 3'd0;
        log_lock <= 1'b0;
        log_req  <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt  <= 27'd0;
            log_ok   <= ok_cnt;
            log_se   <= sym_err_cnt;
            log_fe   <= frame_sync_cnt;
            log_wi   <= invalid_cnt;
            log_qn   <= qn_cnt;
            log_rxc  <= last_rx_class;
            log_exc  <= last_exp_class;
            log_lock <= locked;
            log_req  <= 1'b1;
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
            uart_data  <= log_char(log_ptr, log_ok, log_se, log_fe, log_wi, log_qn, log_rxc, log_exc, log_lock);
            uart_start <= 1'b1;
            if (log_ptr == 7'd88)
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
assign led[1] = locked;
assign led[2] = pass_pulse;
assign led[3] = fail_pulse;

endmodule
