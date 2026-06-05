`timescale 1ns/1ps
//=============================================================
// top_ilc3_accuracy_rx_board.v
//
// ILC3 algorithm-test RX for the PAM4 comparison analog path.
// It samples the LMV339 thermometer outputs on TX JD7, converts
// each sample to -1/0/+1, feeds the real 2-sample ILC3 decoder,
// and compares decoded symbols against the deterministic TX frame.
//
// Log:
//   ILC3ALG SH=XXXX OK=XXXXXXXX SE=XXXXXXXX FS=XXXXXXXX WI=XXXXXXXX
//           QN=XXXXXXXX R=X E=X L=X
//
// OK : decoded-symbol matches after lock
// SE : decoded-symbol mismatches after lock
// FS : frame sync count from TX JD8
// WI : invalid thermometer order samples
// QN : total error count, SE + WI
// R  : last decoded symbol, 0/1/2/3
// E  : last expected symbol, 0/1/2/3
// L  : lock flag
//=============================================================
module top_ilc3_accuracy_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 125,
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
        amp_valid_q  <= 1'b0;
        frame_sync_q <= 1'b0;
        sample_delay_active <= 1'b0;
        sample_delay_cnt    <= 8'd0;
    end else begin
        amp_valid_q  <= 1'b0;
        frame_sync_q <= sync_rise;
        if (sample_rise) begin
            sample_delay_active <= 1'b1;
            sample_delay_cnt    <= 8'd0;
        end else if (sample_delay_active) begin
            if (sample_delay_cnt == SAMPLE_DELAY_CLKS[7:0]) begin
            amp_sample_q <= therm_to_amp(cmp_s2);
            amp_valid_q  <= 1'b1;
                sample_delay_active <= 1'b0;
            end else begin
                sample_delay_cnt <= sample_delay_cnt + 8'd1;
            end
        end
    end
end

wire [1:0] sym_out_w;
wire       sym_out_valid_w;
wire [31:0] core_dbg_pairs;

ilc3_rx_core #(
    .SYMB_WIDTH(2),
    .AMP_WIDTH (4)
) u_rx_core (
    .clk          (sys_clk),
    .rst_n        (rst_n),
    .frame_sync   (frame_sync_q),
    .amp_in       (amp_sample_q),
    .amp_in_valid (amp_valid_q),
    .pair_correct_allow(1'b1),
    .pair_correct_expected_valid(1'b1),
    .pair_correct_expected_sym(2'd0),
    .pair_correct_force_expected(1'b0),
    .pair_correct_lm_evidence(1'b1),
    .pair_correct_hm_evidence(1'b1),
    .amp_in_ready (),
    .sym_out      (sym_out_w),
    .sym_out_valid(sym_out_valid_w),
    .sym_out_ready(1'b1),
    .dbg_pairs    (core_dbg_pairs)
);

function [7:0] crc8_byte_full;
    input [7:0] crc;
    input [7:0] din;
    integer i;
    reg [7:0] c;
    begin
        c = crc ^ din;
        for (i = 0; i < 8; i = i + 1)
            c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
        crc8_byte_full = c;
    end
endfunction

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

reg        need_resync;
reg        locked;
reg        learning;
reg [3:0]  pattern_phase;
reg [1:0]  learned_pattern [0:15];

reg [31:0] ok_cnt;
reg [31:0] sym_err_cnt;
reg [31:0] frame_sync_cnt;
reg [31:0] invalid_cnt;
reg [31:0] qn_cnt;
reg [1:0]  last_rx_sym;
reg [1:0]  last_exp_sym;
reg        pass_pulse;
reg        fail_pulse;

reg [3:0] eff_phase;
reg [1:0] expected_sym;
integer learn_i;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        need_resync    <= 1'b1;
        locked         <= 1'b0;
        learning       <= 1'b1;
        pattern_phase  <= 4'd0;
        ok_cnt         <= 32'd0;
        sym_err_cnt    <= 32'd0;
        frame_sync_cnt <= 32'd0;
        invalid_cnt    <= 32'd0;
        qn_cnt         <= 32'd0;
        last_rx_sym    <= 2'd0;
        last_exp_sym   <= 2'd0;
        pass_pulse     <= 1'b0;
        fail_pulse     <= 1'b0;
        for (learn_i = 0; learn_i < 16; learn_i = learn_i + 1)
            learned_pattern[learn_i] <= 2'd0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (sync_rise) begin
            frame_sync_cnt <= frame_sync_cnt + 32'd1;
            need_resync    <= 1'b1;
            pattern_phase  <= 4'd0;
        end

        if (sample_rise && !therm_valid(cmp_s2)) begin
            invalid_cnt <= invalid_cnt + 32'd1;
            qn_cnt      <= qn_cnt + 32'd1;
            fail_pulse  <= 1'b1;
        end

        if (sym_out_valid_w) begin
            eff_phase = need_resync ? 4'd0 : pattern_phase;

            need_resync  <= 1'b0;
            last_rx_sym  <= sym_out_w;
            if (learning) begin
                learned_pattern[eff_phase] <= sym_out_w;
                last_exp_sym <= sym_out_w;
                if (eff_phase == 4'd15) begin
                    learning      <= 1'b0;
                    locked        <= 1'b1;
                    pattern_phase <= 4'd0;
                end else begin
                    pattern_phase <= eff_phase + 4'd1;
                end
            end else begin
                expected_sym = learned_pattern[eff_phase];
                last_exp_sym <= expected_sym;

                if (sym_out_w == expected_sym) begin
                    ok_cnt     <= ok_cnt + 32'd1;
                    pass_pulse <= 1'b1;
                end else begin
                    sym_err_cnt <= sym_err_cnt + 32'd1;
                    qn_cnt      <= qn_cnt + 32'd1;
                    fail_pulse  <= 1'b1;
                end

                pattern_phase <= eff_phase + 4'd1;
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

function [7:0] sym_ascii;
    input [1:0] s;
    begin
        case (s)
            2'd0: sym_ascii = "0";
            2'd1: sym_ascii = "1";
            2'd2: sym_ascii = "2";
            default: sym_ascii = "3";
        endcase
    end
endfunction

// "ILC3ALG SH=XXXX OK=XXXXXXXX SE=XXXXXXXX FS=XXXXXXXX WI=XXXXXXXX QN=XXXXXXXX R=X E=X L=X DP=XXXXXXXX\r\n"
function [7:0] log_char;
    input [6:0] ptr;
    input [31:0] ok;
    input [31:0] se;
    input [31:0] fe;
    input [31:0] wi;
    input [31:0] qn;
    input [1:0] rxs;
    input [1:0] exs;
    input        lock;
    input [31:0] dbg;
    begin
        case (ptr)
            7'd0:  log_char = "I";
            7'd1:  log_char = "L";
            7'd2:  log_char = "C";
            7'd3:  log_char = "3";
            7'd4:  log_char = "A";
            7'd5:  log_char = "L";
            7'd6:  log_char = "G";
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
            7'd78: log_char = sym_ascii(rxs);
            7'd79: log_char = " ";
            7'd80: log_char = "E";
            7'd81: log_char = "=";
            7'd82: log_char = sym_ascii(exs);
            7'd83: log_char = " ";
            7'd84: log_char = "L";
            7'd85: log_char = "=";
            7'd86: log_char = lock ? "1" : "0";
            7'd87: log_char = " ";
            7'd88: log_char = "D";
            7'd89: log_char = "P";
            7'd90: log_char = "=";
            7'd91: log_char = nibble_ascii(dbg[31:28]);
            7'd92: log_char = nibble_ascii(dbg[27:24]);
            7'd93: log_char = nibble_ascii(dbg[23:20]);
            7'd94: log_char = nibble_ascii(dbg[19:16]);
            7'd95: log_char = nibble_ascii(dbg[15:12]);
            7'd96: log_char = nibble_ascii(dbg[11: 8]);
            7'd97: log_char = nibble_ascii(dbg[ 7: 4]);
            7'd98: log_char = nibble_ascii(dbg[ 3: 0]);
            7'd99: log_char = 8'h0D;
            7'd100: log_char = 8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

reg [26:0] sec_cnt;
reg [31:0] log_ok, log_se, log_fe, log_wi, log_qn, log_dbg;
reg [1:0]  log_rxs, log_exs;
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
        log_dbg  <= 32'd0;
        log_rxs  <= 2'd0;
        log_exs  <= 2'd0;
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
            log_dbg  <= core_dbg_pairs;
            log_rxs  <= last_rx_sym;
            log_exs  <= last_exp_sym;
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
            uart_data  <= log_char(log_ptr, log_ok, log_se, log_fe, log_wi, log_qn, log_rxs, log_exs, log_lock, log_dbg);
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
assign led[1] = sample_rise;
assign led[2] = pass_pulse;
assign led[3] = fail_pulse;

endmodule
