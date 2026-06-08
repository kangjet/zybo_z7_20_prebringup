`timescale 1ns/1ps
//=============================================================
// top_ilc3_txref_histogram_recovery_rx_board.v
//
// ILC3 packet PHY RX for 256B PSDU over the analog comparator
// path. It decodes ILC3 symbols, reconstructs packet bytes, checks
// preamble/header/meta/payload, verifies CRC-16/CCITT-FALSE, and logs
// RX-only level histogram counters.
//
// This file is intentionally split from
// top_ilc3_histogram_tag_packet256_rx_board.v. The original file remains the
// observation baseline; this file is for the next self-correction experiment.
//
// Log:
//   ILC3PKT SH=XXXX PK=XXXXXXXX OK=XXXXXXXX NG=XXXXXXXX
//           BE=XXXXXXXX CE=XXXXXXXX WI=XXXXXXXX FS=XXXXXXXX LB=XX
//=============================================================
module top_ilc3_txref_histogram_recovery_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter integer SYMBOL_HOLD_CLKS = 85,
    parameter integer SAMPLE_DELAY_CLKS = 4,
    parameter integer ENABLE_SELF_CORRECT = 1,
    parameter integer SELF_CORRECT_MIN_DELAY = 1,
    parameter integer SELF_CORRECT_MAX_DELAY = 15,
    parameter integer ENABLE_TAG = 0,
    parameter integer TAG_INTERVAL_SYMBOLS = 32,
    parameter integer TAG_PAIR_COUNT = 2
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
localparam integer DM_WINDOW_SAMPLES = 32_768;
localparam integer LOG_EVERY_WINDOWS = 64;
localparam integer SELF_CORRECT_EVERY_WINDOWS = 8;
localparam integer PREAMBLE_LEN = 4;
localparam integer HEADER_LEN   = 8;
localparam integer META_LEN     = 4;
localparam integer PAYLOAD_LEN  = 256;
localparam integer CRC_LEN      = 2;
localparam integer FRAME_BYTES  = PREAMBLE_LEN + HEADER_LEN + META_LEN + PAYLOAD_LEN + CRC_LEN;
// 32768-sample DM latency window. These are the previous 1s thresholds
// scaled by the observed clean 400mV baseline histogram total (~1,470,589).
localparam [31:0] DH_WARN_TH = 32'd10222;
localparam [31:0] DH_HIGH_TH = 32'd13143;
localparam [31:0] DM_WARN_TH = 32'd13143;
localparam [31:0] DM_LOW_TH  = 32'd10678;
localparam [31:0] DL_MIN_TH  = 32'd2921;
localparam [31:0] DM_DEFER_DD_TH = 32'd1460;
localparam [31:0] DM_RECOVER_DD_TH = 32'd183;
// Packet-local DM threshold. Keep this conservative: the packet window is
// aligned to decoded packet activity, while long-DM remains the sensitive
// line-health monitor.
localparam [31:0] PKT_DM_DEFER_DD_TH = 32'd512;
localparam [31:0] PKT_DM_MIN_SAMPLES = 32'd1024;
localparam [31:0] TR_FAST_HM_TH = 32'd2048;
localparam [31:0] TR_FAST_PR_TH = 32'd4096;
// Reject stale recovery timestamps before they pollute RM/RA. Valid recovery
// samples are bounded to sub-ms timing so wrapped/stale events are excluded.
localparam [31:0] RECOVERY_LATENCY_MAX_VALID = CLK_FREQ_HZ / 1000;
localparam [3:0] LINK_STABLE_CLEAN_WINDOWS = 4'd4;
localparam [7:0] SAMPLE_DELAY_INIT = SAMPLE_DELAY_CLKS[7:0];
localparam [7:0] SELF_CORRECT_MIN_DELAY_8 = SELF_CORRECT_MIN_DELAY;
localparam [7:0] SELF_CORRECT_MAX_DELAY_8 = SELF_CORRECT_MAX_DELAY;

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
reg [7:0]        sample_delay_trim_q;
reg              self_correct_dir_q;
reg [3:0]        self_correct_prev_lv_q;
reg              self_correct_fast_q;
reg [31:0]       self_correct_step_cnt;
reg [31:0]       hist_high_cnt;
reg [31:0]       hist_mid_cnt;
reg [31:0]       hist_low_cnt;
reg [31:0]       hist_invalid_cnt;
reg              rx_soft_recover_q;
wire [7:0]       active_sample_delay = ENABLE_SELF_CORRECT ? sample_delay_trim_q : SAMPLE_DELAY_INIT;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        amp_sample_q <= 4'sd0;
        amp_valid_q <= 1'b0;
        frame_sync_q <= 1'b0;
        sample_delay_active <= 1'b0;
        sample_delay_cnt <= 8'd0;
        hist_high_cnt <= 32'd0;
        hist_mid_cnt <= 32'd0;
        hist_low_cnt <= 32'd0;
        hist_invalid_cnt <= 32'd0;
    end else begin
        amp_valid_q <= 1'b0;
        frame_sync_q <= sync_rise;
        if (sample_rise) begin
            sample_delay_active <= 1'b1;
            sample_delay_cnt <= 8'd0;
        end else if (sample_delay_active) begin
            if (sample_delay_cnt == active_sample_delay) begin
                amp_sample_q <= therm_to_amp(cmp_s2);
                amp_valid_q <= 1'b1;
                sample_delay_active <= 1'b0;
                case (cmp_s2)
                    3'b000: hist_low_cnt <= hist_low_cnt + 32'd1;
                    3'b001,
                    3'b011: hist_mid_cnt <= hist_mid_cnt + 32'd1;
                    3'b111: hist_high_cnt <= hist_high_cnt + 32'd1;
                    default: hist_invalid_cnt <= hist_invalid_cnt + 32'd1;
                endcase
            end else begin
                sample_delay_cnt <= sample_delay_cnt + 8'd1;
            end
        end
    end
end

wire [1:0]  sym_out_w;
wire        sym_out_valid_w;
wire [31:0] core_dbg_pairs;
wire        pair_invalid_pulse_w;
wire [7:0]  pair_invalid_code_w;
wire        pair_correct_pulse_w;
wire        pair_correct_reject_pulse_w;
wire [7:0]  pair_correct_code_w;
wire        sample_phase_dbg_w;
wire        expected_tag_pair_w;
wire        pair_correct_allow_w;
wire        pair_correct_expected_valid_w;
wire [1:0]  pair_correct_expected_sym_w;
wire        pair_correct_force_expected_w;
wire        pair_correct_lm_evidence_w;
wire        pair_correct_hm_evidence_w;

ilc3_rx_core #(.SYMB_WIDTH(2), .AMP_WIDTH(4), .ENABLE_PAIR_CORRECT(1), .ENABLE_LL_HH_CORRECT(1)) u_rx_core (
    .clk(sys_clk),
    .rst_n(rst_n),
    .frame_sync(frame_sync_q),
    .amp_in(amp_sample_q),
    .amp_in_valid(amp_valid_q),
    .pair_correct_allow(pair_correct_allow_w),
    .pair_correct_expected_valid(pair_correct_expected_valid_w),
    .pair_correct_expected_sym(pair_correct_expected_sym_w),
    .pair_correct_force_expected(pair_correct_force_expected_w),
    .pair_correct_lm_evidence(pair_correct_lm_evidence_w),
    .pair_correct_hm_evidence(pair_correct_hm_evidence_w),
    .amp_in_ready(),
    .sym_out(sym_out_w),
    .sym_out_valid(sym_out_valid_w),
    .sym_out_ready(1'b1),
    .dbg_pairs(core_dbg_pairs),
    .pair_invalid_pulse(pair_invalid_pulse_w),
    .pair_invalid_code(pair_invalid_code_w),
    .pair_correct_pulse(pair_correct_pulse_w),
    .pair_correct_reject_pulse(pair_correct_reject_pulse_w),
    .pair_correct_code(pair_correct_code_w),
    .sample_phase_dbg(sample_phase_dbg_w)
);

assign expected_tag_pair_w = (ENABLE_TAG != 0) && tag_pending &&
                             (pair_invalid_code_w == (tag_pair_idx[0] ? 8'hFF : 8'h11));

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
            9'd4:  expected_byte_no_crc = 8'h02;
            9'd5:  expected_byte_no_crc = 8'h03;
            9'd6:  expected_byte_no_crc = 8'h01;
            9'd7:  expected_byte_no_crc = 8'h00;
            9'd8:  expected_byte_no_crc = seq[31:24];
            9'd9:  expected_byte_no_crc = seq[23:16];
            9'd10: expected_byte_no_crc = seq[15:8];
            9'd11: expected_byte_no_crc = seq[7:0];
            default: expected_byte_no_crc = payload_byte(idx - 9'd16, seq);
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
reg [31:0] pair_invalid_cnt;
reg [31:0] lm_rule_err_cnt;
reg [31:0] hm_rule_err_cnt;
reg [31:0] mm_rule_err_cnt;
reg [31:0] pair_risk_cnt;
reg [31:0] pair_correct_candidate_cnt;
reg [31:0] pair_correct_accept_cnt;
reg [31:0] pair_correct_reject_cnt;
reg [7:0]  pair_correct_last_code;
reg [31:0] lm_rule_window_cnt;
reg [31:0] hm_rule_window_cnt;
reg [31:0] mm_rule_window_cnt;
reg [31:0] pair_risk_window_cnt;
reg [31:0] tag_seen_cnt;
reg [31:0] tag_valid_cnt;
reg [31:0] tag_reject_cnt;
reg [31:0] tag_seq_error_cnt;
reg [31:0] tag_lock_cnt;
reg [15:0] txref_th_rx;
reg [15:0] txref_tt_rx;
reg [15:0] txref_th_latched;
reg [15:0] txref_tt_latched;
reg [31:0] txref_ok_cnt;
reg        tag_pending;
reg [1:0]  tag_pair_idx;
reg [15:0] data_sym_since_tag;
reg [31:0] frame_sync_cnt;
reg [31:0] resync_drop_cnt;
reg [31:0] partial_drop_cnt;
reg [31:0] pkt_byte_err;
reg [7:0]  last_byte;
reg        pass_pulse;
reg        fail_pulse;
reg        pkt_dm_active_q;
reg        pkt_dm_eval_q;
reg        pkt_dm_defer_pulse;
reg [31:0] pkt_dm_high_cnt;
reg [31:0] pkt_dm_mid_cnt;
reg [31:0] pkt_dm_low_cnt;
reg [31:0] pkt_dm_invalid_cnt;
reg [31:0] pkt_dm_sample_cnt;
reg [31:0] pkt_dm_non_mid_calc;
reg [31:0] pkt_dm_base_calc;
reg [31:0] pkt_dm_dd_calc;
reg [31:0] pkt_dm_abs_dd_calc;

wire       packet_symbol_done_w = sym_out_valid_w &&
                                  !need_resync &&
                                  (sym_in_byte == 2'd3) &&
                                  (byte_idx == FRAME_BYTES - 1);

assign pair_correct_allow_w =
    !need_resync &&
    !tag_pending &&
    !packet_bad &&
    (pkt_byte_err == 32'd0) &&
    (byte_idx >= (PREAMBLE_LEN + HEADER_LEN + META_LEN)) &&
    (byte_idx <  (FRAME_BYTES - CRC_LEN));

assign pair_correct_lm_evidence_w = (lm_rule_window_cnt != 32'd0);
assign pair_correct_hm_evidence_w = (hm_rule_window_cnt != 32'd0);

wire [7:0] pair_correct_expected_byte_w = expected_byte_no_crc(byte_idx, seq_rx);
assign pair_correct_expected_valid_w = pair_correct_allow_w;
assign pair_correct_force_expected_w = pair_correct_allow_w;
assign pair_correct_expected_sym_w =
    (sym_in_byte == 2'd0) ? pair_correct_expected_byte_w[7:6] :
    (sym_in_byte == 2'd1) ? pair_correct_expected_byte_w[5:4] :
    (sym_in_byte == 2'd2) ? pair_correct_expected_byte_w[3:2] :
                            pair_correct_expected_byte_w[1:0];

reg [7:0] rx_byte;
reg [31:0] seq_next;
reg [15:0] crc_next;
reg [15:0] rx_crc_next;
reg        packet_bad_next;
reg        crc_bad_next;
reg [7:0]  exp_byte;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        pkt_dm_active_q <= 1'b0;
        pkt_dm_eval_q <= 1'b0;
        pkt_dm_defer_pulse <= 1'b0;
        pkt_dm_high_cnt <= 32'd0;
        pkt_dm_mid_cnt <= 32'd0;
        pkt_dm_low_cnt <= 32'd0;
        pkt_dm_invalid_cnt <= 32'd0;
        pkt_dm_sample_cnt <= 32'd0;
        pkt_dm_non_mid_calc <= 32'd0;
        pkt_dm_base_calc <= 32'd0;
        pkt_dm_dd_calc <= 32'd0;
        pkt_dm_abs_dd_calc <= 32'd0;
    end else begin
        pkt_dm_defer_pulse <= 1'b0;
        if (pkt_dm_eval_q &&
            (pkt_dm_abs_dd_calc >= PKT_DM_DEFER_DD_TH)) begin
            pkt_dm_defer_pulse <= 1'b1;
        end
        pkt_dm_eval_q <= 1'b0;
        if (sync_rise || rx_soft_recover_q) begin
            pkt_dm_active_q <= 1'b0;
            pkt_dm_eval_q <= 1'b0;
            pkt_dm_high_cnt <= 32'd0;
            pkt_dm_mid_cnt <= 32'd0;
            pkt_dm_low_cnt <= 32'd0;
            pkt_dm_invalid_cnt <= 32'd0;
            pkt_dm_sample_cnt <= 32'd0;
        end else begin
            if (sym_out_valid_w && need_resync) begin
                pkt_dm_active_q <= 1'b1;
                pkt_dm_high_cnt <= 32'd0;
                pkt_dm_mid_cnt <= 32'd0;
                pkt_dm_low_cnt <= 32'd0;
                pkt_dm_invalid_cnt <= 32'd0;
                pkt_dm_sample_cnt <= 32'd0;
            end

            if (pkt_dm_active_q && amp_valid_q) begin
                pkt_dm_sample_cnt <= pkt_dm_sample_cnt + 32'd1;
                case (cmp_s2)
                    3'b000: pkt_dm_low_cnt <= pkt_dm_low_cnt + 32'd1;
                    3'b001,
                    3'b011: pkt_dm_mid_cnt <= pkt_dm_mid_cnt + 32'd1;
                    3'b111: pkt_dm_high_cnt <= pkt_dm_high_cnt + 32'd1;
                    default: pkt_dm_invalid_cnt <= pkt_dm_invalid_cnt + 32'd1;
                endcase
            end

            if (packet_symbol_done_w) begin
                pkt_dm_non_mid_calc <= pkt_dm_high_cnt + pkt_dm_low_cnt + pkt_dm_invalid_cnt;
                pkt_dm_base_calc <= pkt_dm_high_cnt + pkt_dm_low_cnt + pkt_dm_invalid_cnt;
                pkt_dm_dd_calc <= pkt_dm_mid_cnt -
                                  (pkt_dm_high_cnt + pkt_dm_low_cnt + pkt_dm_invalid_cnt);
                pkt_dm_abs_dd_calc <= abs32_twos(pkt_dm_mid_cnt -
                                                 (pkt_dm_high_cnt + pkt_dm_low_cnt + pkt_dm_invalid_cnt));
                pkt_dm_eval_q <= pkt_dm_active_q &&
                                 (pkt_dm_sample_cnt >= PKT_DM_MIN_SAMPLES);
                pkt_dm_active_q <= 1'b0;
            end
        end
    end
end

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
        pair_invalid_cnt <= 32'd0;
        lm_rule_err_cnt <= 32'd0;
        hm_rule_err_cnt <= 32'd0;
        mm_rule_err_cnt <= 32'd0;
        pair_risk_cnt <= 32'd0;
        pair_correct_candidate_cnt <= 32'd0;
        pair_correct_accept_cnt <= 32'd0;
        pair_correct_reject_cnt <= 32'd0;
        pair_correct_last_code <= 8'h00;
        lm_rule_window_cnt <= 32'd0;
        hm_rule_window_cnt <= 32'd0;
        mm_rule_window_cnt <= 32'd0;
        pair_risk_window_cnt <= 32'd0;
        tag_seen_cnt <= 32'd0;
        tag_valid_cnt <= 32'd0;
        tag_reject_cnt <= 32'd0;
        tag_seq_error_cnt <= 32'd0;
        tag_lock_cnt <= 32'd0;
        txref_th_rx <= 16'd0;
        txref_tt_rx <= 16'd0;
        txref_th_latched <= 16'd0;
        txref_tt_latched <= 16'd0;
        txref_ok_cnt <= 32'd0;
        tag_pending <= 1'b0;
        tag_pair_idx <= 2'd0;
        data_sym_since_tag <= 16'd0;
        frame_sync_cnt <= 32'd0;
        resync_drop_cnt <= 32'd0;
        partial_drop_cnt <= 32'd0;
        pkt_byte_err <= 32'd0;
        last_byte <= 8'd0;
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;
        last_fail_seq_q <= 32'd0;
        last_fail_seq_valid_q <= 1'b0;
    end else begin
        pass_pulse <= 1'b0;
        fail_pulse <= 1'b0;

        if (rx_soft_recover_q) begin
            need_resync <= 1'b1;
            sym_in_byte <= 2'd0;
            sym_in_byte_acc <= 6'd0;
            byte_idx <= 9'd0;
            seq_rx <= 32'd0;
            crc_acc <= 16'hFFFF;
            rx_crc <= 16'd0;
            packet_bad <= 1'b0;
            crc_bad <= 1'b0;
            pkt_byte_err <= 32'd0;
            tag_pending <= 1'b0;
            tag_pair_idx <= 2'd0;
            data_sym_since_tag <= 16'd0;
        end else begin
        if (sync_rise) begin
            frame_sync_cnt <= frame_sync_cnt + 32'd1;
            if (!need_resync && ((byte_idx != 9'd0) || (sym_in_byte != 2'd0) || packet_bad || (pkt_byte_err != 32'd0))) begin
                resync_drop_cnt <= resync_drop_cnt + 32'd1;
                partial_drop_cnt <= partial_drop_cnt + 32'd1;
            end
            need_resync <= 1'b1;
            tag_pending <= 1'b0;
            tag_pair_idx <= 2'd0;
            data_sym_since_tag <= 16'd0;
        end

        if (sample_rise && !therm_valid(cmp_s2)) begin
            invalid_cnt <= invalid_cnt + 32'd1;
            packet_bad <= 1'b1;
            fail_pulse <= 1'b1;
        end

        if (amp_valid_q && (dm_window_sample_cnt == DM_WINDOW_SAMPLES - 1)) begin
            lm_rule_window_cnt <= 32'd0;
            hm_rule_window_cnt <= 32'd0;
            mm_rule_window_cnt <= 32'd0;
            pair_risk_window_cnt <= 32'd0;
        end else if (pair_invalid_pulse_w) begin
            pair_invalid_cnt <= pair_invalid_cnt + 32'd1;
            tag_seen_cnt <= tag_seen_cnt + 32'd1;
            if (expected_tag_pair_w) begin
                tag_valid_cnt <= tag_valid_cnt + 32'd1;
                if (tag_pair_idx == TAG_PAIR_COUNT - 1) begin
                    tag_pending <= 1'b0;
                    tag_pair_idx <= 2'd0;
                    data_sym_since_tag <= 16'd0;
                    tag_lock_cnt <= tag_lock_cnt + 32'd1;
                end else begin
                    tag_pair_idx <= tag_pair_idx + 2'd1;
                end
            end else begin
                pair_risk_window_cnt <= pair_risk_window_cnt + 32'd1;
                if (pair_invalid_code_w[7:4] == 4'hF)
                    lm_rule_window_cnt <= lm_rule_window_cnt + 32'd1;
                else if (pair_invalid_code_w[7:4] == 4'h1)
                    hm_rule_window_cnt <= hm_rule_window_cnt + 32'd1;
                else if (pair_invalid_code_w == 8'h00)
                    mm_rule_window_cnt <= mm_rule_window_cnt + 32'd1;
                tag_reject_cnt <= tag_reject_cnt + 32'd1;
            end
        end
        if (pair_invalid_pulse_w && !expected_tag_pair_w) begin
            pair_correct_candidate_cnt <= pair_correct_candidate_cnt + 32'd1;
            pair_correct_last_code <= pair_correct_code_w;
        end
        if (pair_correct_pulse_w && !expected_tag_pair_w) begin
            pair_correct_accept_cnt <= pair_correct_accept_cnt + 32'd1;
            pair_correct_last_code <= pair_correct_code_w;
        end
        if (pair_correct_reject_pulse_w && !expected_tag_pair_w) begin
            pair_correct_reject_cnt <= pair_correct_reject_cnt + 32'd1;
            pair_correct_last_code <= pair_correct_code_w;
        end

        if (sym_out_valid_w) begin
            if (ENABLE_TAG != 0) begin
                if (tag_pending) begin
                    tag_seq_error_cnt <= tag_seq_error_cnt + 32'd1;
                    tag_pending <= 1'b0;
                    tag_pair_idx <= 2'd0;
                    data_sym_since_tag <= 16'd1;
                end else if (data_sym_since_tag == TAG_INTERVAL_SYMBOLS - 1) begin
                    tag_pending <= 1'b1;
                    tag_pair_idx <= 2'd0;
                end else begin
                    data_sym_since_tag <= data_sym_since_tag + 16'd1;
                end
            end
            if (need_resync) begin
                need_resync <= 1'b0;
                sym_in_byte <= 2'd1;
                sym_in_byte_acc <= {4'd0, sym_out_w};
                byte_idx <= 9'd0;
                seq_rx <= 32'd0;
                crc_acc <= 16'hFFFF;
                rx_crc <= 16'd0;
                txref_th_rx <= 16'd0;
                txref_tt_rx <= 16'd0;
                packet_bad <= 1'b0;
                crc_bad <= 1'b0;
                pkt_byte_err <= 32'd0;
                tag_pending <= 1'b0;
                tag_pair_idx <= 2'd0;
                data_sym_since_tag <= 16'd1;
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
                    case (byte_idx)
                        9'd12: txref_th_rx[15:8] <= rx_byte;
                        9'd13: txref_th_rx[7:0]  <= rx_byte;
                        9'd14: txref_tt_rx[15:8] <= rx_byte;
                        9'd15: txref_tt_rx[7:0]  <= rx_byte;
                        default: txref_th_rx <= txref_th_rx;
                    endcase

                    if ((byte_idx >= PREAMBLE_LEN) &&
                        (byte_idx < FRAME_BYTES - CRC_LEN))
                        crc_next = crc16_byte(crc_acc, rx_byte);

                    if ((byte_idx < FRAME_BYTES - CRC_LEN) &&
                        !((byte_idx >= PREAMBLE_LEN + HEADER_LEN) &&
                          (byte_idx < PREAMBLE_LEN + HEADER_LEN + META_LEN))) begin
                        exp_byte = expected_byte_no_crc(byte_idx, seq_next);
                        if (rx_byte != exp_byte) begin
                            pkt_byte_err <= pkt_byte_err + 32'd1;
                            packet_bad_next = 1'b1;
                            fail_pulse <= 1'b1;
                        end
                    end else if ((byte_idx >= PREAMBLE_LEN + HEADER_LEN) &&
                                 (byte_idx < PREAMBLE_LEN + HEADER_LEN + META_LEN)) begin
                        // TX reference metadata is checked through the FCS contract.
                    end else if (byte_idx == FRAME_BYTES - 2) begin
                        rx_crc_next[15:8] = rx_byte;
                    end else begin
                        rx_crc_next[7:0] = rx_byte;
                        if ({rx_crc_next[15:8], rx_byte} != crc_acc) begin
                            // Strict CRC-gate validation: FCS mismatch is counted as
                            // a packet failure in addition to the diagnostic counter.
                            crc_err_cnt <= crc_err_cnt + 32'd1;
                            crc_bad_next = 1'b1;
                            packet_bad_next = 1'b1;
                            fail_pulse <= 1'b1;
                        end
                    end

                    if (byte_idx == FRAME_BYTES - 1) begin
                        pkt_cnt <= pkt_cnt + 32'd1;
                        if (packet_bad_next) begin
                            pkt_ng_cnt <= pkt_ng_cnt + 32'd1;
                            byte_err_cnt <= byte_err_cnt + pkt_byte_err;
                            last_fail_seq_q <= seq_next;
                            last_fail_seq_valid_q <= 1'b1;
                        end else begin
                            pkt_ok_cnt <= pkt_ok_cnt + 32'd1;
                            txref_th_latched <= txref_th_rx;
                            txref_tt_latched <= txref_tt_rx;
                            txref_ok_cnt <= txref_ok_cnt + 32'd1;
                            pass_pulse <= 1'b1;
                        end
                        byte_idx <= 9'd0;
                        crc_acc <= 16'hFFFF;
                        rx_crc <= 16'd0;
                        packet_bad <= 1'b0;
                        crc_bad <= crc_bad_next;
                        pkt_byte_err <= 32'd0;
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
end

function [7:0] nibble_ascii;
    input [3:0] n;
    begin
        nibble_ascii = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    end
endfunction

function [31:0] abs32_twos;
    input [31:0] v;
    begin
        abs32_twos = v[31] ? (~v + 32'd1) : v;
    end
endfunction

// Latency build log notes:
//   FS = frame-sync counter
//   RL = last recovery latency in sys_clk cycles
//   RM = max recovery latency in sys_clk cycles
//   RA = accumulated valid recovery latency in sys_clk cycles
//   RV = valid recovery latency sample count, avg = RA / RV
//   SP/SQ/RT = link-policy stop-active / stop count / retransmit-resume count
//   SL/SM/SA/SV = stop-to-resume last/max/sum/sample count in sys_clk cycles
//   ILC3RTX is an RX-side transaction monitor. It proves request/resume/accept
//   accounting and seq matching; it is not a physical TX ACK wire.
// Short latency log for timing margin:
// "ILC3HST SH=XXXX PK=XXXXXXXX OK=XXXXXXXX NG=XXXXXXXX BE=XXXXXXXX CE=XXXXXXXX DF=XXXXXXXX FS=XXXXXXXX RC=XXXXXXXX RD=XXXXXXXX RL=XXXXXXXX RM=XXXXXXXX RA=XXXXXXXX DM=XXXXXXXX DB=XXXXXXXX DD=XXXXXXXX TH=XXXX TT=XXXX TO=XXXXXXXX LM=XXXXXXXX HM=XXXXXXXX MM=XXXXXXXX PR=XXXXXXXX LV=X SC=XX PC=XXXXXXXX PA=XXXXXXXX PJ=XXXXXXXX PL=XX RV=XXXXXXXX SP=X SQ=XXXXXXXX RT=XXXXXXXX SL=XXXXXXXX SM=XXXXXXXX SA=XXXXXXXX SV=XXXXXXXX\r\n"
function [7:0] log_char;
    input [8:0] ptr;
    input [31:0] pk;
    input [31:0] ok;
    input [31:0] ng;
    input [31:0] be;
    input [31:0] ce;
    input [31:0] wi;
    input [31:0] fs;
    input [31:0] rs;
    input [31:0] dr;
    input [31:0] pi;
    input [31:0] ts;
    input [31:0] tv;
    input [31:0] tr;
    input [31:0] te;
    input [31:0] tl;
    input [7:0]  lb;
    input [31:0] hc;
    input [31:0] mc;
    input [31:0] lc;
    input [31:0] ic;
    input [31:0] dh;
    input [31:0] dm;
    input [31:0] dl;
    input [31:0] di;
    input [7:0]  fg;
    input [3:0]  lv;
    input [7:0]  sc;
    input [31:0] db;
    input [31:0] dd;
    input [31:0] th;
    input [31:0] tt;
    input [31:0] txo;
    input [31:0] lm;
    input [31:0] hm;
    input [31:0] mm;
    input [31:0] pr;
    input [31:0] pc;
    input [31:0] pa;
    input [31:0] pj;
    input [7:0]  pl;
    input [31:0] rv;
    input [3:0]  sp;
    input [31:0] sq;
    input [31:0] rt;
    input [31:0] sl;
    input [31:0] sm;
    input [31:0] sa;
    input [31:0] sv;
    begin
        case (ptr)
            8'd0: log_char="I"; 8'd1: log_char="L"; 8'd2: log_char="C"; 8'd3: log_char="3"; 8'd4: log_char="H"; 8'd5: log_char="S"; 8'd6: log_char="T"; 8'd7: log_char=" ";
            8'd8: log_char="S"; 8'd9: log_char="H"; 8'd10: log_char="="; 8'd11: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[15:12]); 8'd12: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[11:8]); 8'd13: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[7:4]); 8'd14: log_char=nibble_ascii(SYMBOL_HOLD_CLKS[3:0]); 8'd15: log_char=" ";
            8'd16: log_char="P"; 8'd17: log_char="K"; 8'd18: log_char="="; 8'd19: log_char=nibble_ascii(pk[31:28]); 8'd20: log_char=nibble_ascii(pk[27:24]); 8'd21: log_char=nibble_ascii(pk[23:20]); 8'd22: log_char=nibble_ascii(pk[19:16]); 8'd23: log_char=nibble_ascii(pk[15:12]); 8'd24: log_char=nibble_ascii(pk[11:8]); 8'd25: log_char=nibble_ascii(pk[7:4]); 8'd26: log_char=nibble_ascii(pk[3:0]); 8'd27: log_char=" ";
            8'd28: log_char="O"; 8'd29: log_char="K"; 8'd30: log_char="="; 8'd31: log_char=nibble_ascii(ok[31:28]); 8'd32: log_char=nibble_ascii(ok[27:24]); 8'd33: log_char=nibble_ascii(ok[23:20]); 8'd34: log_char=nibble_ascii(ok[19:16]); 8'd35: log_char=nibble_ascii(ok[15:12]); 8'd36: log_char=nibble_ascii(ok[11:8]); 8'd37: log_char=nibble_ascii(ok[7:4]); 8'd38: log_char=nibble_ascii(ok[3:0]); 8'd39: log_char=" ";
            8'd40: log_char="N"; 8'd41: log_char="G"; 8'd42: log_char="="; 8'd43: log_char=nibble_ascii(ng[31:28]); 8'd44: log_char=nibble_ascii(ng[27:24]); 8'd45: log_char=nibble_ascii(ng[23:20]); 8'd46: log_char=nibble_ascii(ng[19:16]); 8'd47: log_char=nibble_ascii(ng[15:12]); 8'd48: log_char=nibble_ascii(ng[11:8]); 8'd49: log_char=nibble_ascii(ng[7:4]); 8'd50: log_char=nibble_ascii(ng[3:0]); 8'd51: log_char=" ";
            8'd52: log_char="B"; 8'd53: log_char="E"; 8'd54: log_char="="; 8'd55: log_char=nibble_ascii(be[31:28]); 8'd56: log_char=nibble_ascii(be[27:24]); 8'd57: log_char=nibble_ascii(be[23:20]); 8'd58: log_char=nibble_ascii(be[19:16]); 8'd59: log_char=nibble_ascii(be[15:12]); 8'd60: log_char=nibble_ascii(be[11:8]); 8'd61: log_char=nibble_ascii(be[7:4]); 8'd62: log_char=nibble_ascii(be[3:0]); 8'd63: log_char=" ";
            8'd64: log_char="C"; 8'd65: log_char="E"; 8'd66: log_char="="; 8'd67: log_char=nibble_ascii(ce[31:28]); 8'd68: log_char=nibble_ascii(ce[27:24]); 8'd69: log_char=nibble_ascii(ce[23:20]); 8'd70: log_char=nibble_ascii(ce[19:16]); 8'd71: log_char=nibble_ascii(ce[15:12]); 8'd72: log_char=nibble_ascii(ce[11:8]); 8'd73: log_char=nibble_ascii(ce[7:4]); 8'd74: log_char=nibble_ascii(ce[3:0]); 8'd75: log_char=" ";
            8'd76: log_char="D"; 8'd77: log_char="F"; 8'd78: log_char="="; 8'd79: log_char=nibble_ascii(wi[31:28]); 8'd80: log_char=nibble_ascii(wi[27:24]); 8'd81: log_char=nibble_ascii(wi[23:20]); 8'd82: log_char=nibble_ascii(wi[19:16]); 8'd83: log_char=nibble_ascii(wi[15:12]); 8'd84: log_char=nibble_ascii(wi[11:8]); 8'd85: log_char=nibble_ascii(wi[7:4]); 8'd86: log_char=nibble_ascii(wi[3:0]); 8'd87: log_char=" ";
            8'd88: log_char="F"; 8'd89: log_char="S"; 8'd90: log_char="="; 8'd91: log_char=nibble_ascii(fs[31:28]); 8'd92: log_char=nibble_ascii(fs[27:24]); 8'd93: log_char=nibble_ascii(fs[23:20]); 8'd94: log_char=nibble_ascii(fs[19:16]); 8'd95: log_char=nibble_ascii(fs[15:12]); 8'd96: log_char=nibble_ascii(fs[11:8]); 8'd97: log_char=nibble_ascii(fs[7:4]); 8'd98: log_char=nibble_ascii(fs[3:0]); 8'd99: log_char=" ";
            8'd100: log_char="R"; 8'd101: log_char="C"; 8'd102: log_char="="; 8'd103: log_char=nibble_ascii(ic[31:28]); 8'd104: log_char=nibble_ascii(ic[27:24]); 8'd105: log_char=nibble_ascii(ic[23:20]); 8'd106: log_char=nibble_ascii(ic[19:16]); 8'd107: log_char=nibble_ascii(ic[15:12]); 8'd108: log_char=nibble_ascii(ic[11:8]); 8'd109: log_char=nibble_ascii(ic[7:4]); 8'd110: log_char=nibble_ascii(ic[3:0]); 8'd111: log_char=" ";
            8'd112: log_char="R"; 8'd113: log_char="D"; 8'd114: log_char="="; 8'd115: log_char=nibble_ascii(di[31:28]); 8'd116: log_char=nibble_ascii(di[27:24]); 8'd117: log_char=nibble_ascii(di[23:20]); 8'd118: log_char=nibble_ascii(di[19:16]); 8'd119: log_char=nibble_ascii(di[15:12]); 8'd120: log_char=nibble_ascii(di[11:8]); 8'd121: log_char=nibble_ascii(di[7:4]); 8'd122: log_char=nibble_ascii(di[3:0]); 8'd123: log_char=" ";
            8'd124: log_char="R"; 8'd125: log_char="L"; 8'd126: log_char="="; 8'd127: log_char=nibble_ascii(rs[31:28]); 8'd128: log_char=nibble_ascii(rs[27:24]); 8'd129: log_char=nibble_ascii(rs[23:20]); 8'd130: log_char=nibble_ascii(rs[19:16]); 8'd131: log_char=nibble_ascii(rs[15:12]); 8'd132: log_char=nibble_ascii(rs[11:8]); 8'd133: log_char=nibble_ascii(rs[7:4]); 8'd134: log_char=nibble_ascii(rs[3:0]); 8'd135: log_char=" ";
            8'd136: log_char="R"; 8'd137: log_char="M"; 8'd138: log_char="="; 8'd139: log_char=nibble_ascii(dr[31:28]); 8'd140: log_char=nibble_ascii(dr[27:24]); 8'd141: log_char=nibble_ascii(dr[23:20]); 8'd142: log_char=nibble_ascii(dr[19:16]); 8'd143: log_char=nibble_ascii(dr[15:12]); 8'd144: log_char=nibble_ascii(dr[11:8]); 8'd145: log_char=nibble_ascii(dr[7:4]); 8'd146: log_char=nibble_ascii(dr[3:0]); 8'd147: log_char=" ";
            8'd148: log_char="R"; 8'd149: log_char="A"; 8'd150: log_char="="; 8'd151: log_char=nibble_ascii(pi[31:28]); 8'd152: log_char=nibble_ascii(pi[27:24]); 8'd153: log_char=nibble_ascii(pi[23:20]); 8'd154: log_char=nibble_ascii(pi[19:16]); 8'd155: log_char=nibble_ascii(pi[15:12]); 8'd156: log_char=nibble_ascii(pi[11:8]); 8'd157: log_char=nibble_ascii(pi[7:4]); 8'd158: log_char=nibble_ascii(pi[3:0]); 8'd159: log_char=" ";
            8'd160: log_char="D"; 8'd161: log_char="M"; 8'd162: log_char="="; 8'd163: log_char=nibble_ascii(dm[31:28]); 8'd164: log_char=nibble_ascii(dm[27:24]); 8'd165: log_char=nibble_ascii(dm[23:20]); 8'd166: log_char=nibble_ascii(dm[19:16]); 8'd167: log_char=nibble_ascii(dm[15:12]); 8'd168: log_char=nibble_ascii(dm[11:8]); 8'd169: log_char=nibble_ascii(dm[7:4]); 8'd170: log_char=nibble_ascii(dm[3:0]); 8'd171: log_char=" ";
            8'd172: log_char="D"; 8'd173: log_char="B"; 8'd174: log_char="="; 8'd175: log_char=nibble_ascii(db[31:28]); 8'd176: log_char=nibble_ascii(db[27:24]); 8'd177: log_char=nibble_ascii(db[23:20]); 8'd178: log_char=nibble_ascii(db[19:16]); 8'd179: log_char=nibble_ascii(db[15:12]); 8'd180: log_char=nibble_ascii(db[11:8]); 8'd181: log_char=nibble_ascii(db[7:4]); 8'd182: log_char=nibble_ascii(db[3:0]); 8'd183: log_char=" ";
            8'd184: log_char="D"; 8'd185: log_char="D"; 8'd186: log_char="="; 8'd187: log_char=nibble_ascii(dd[31:28]); 8'd188: log_char=nibble_ascii(dd[27:24]); 8'd189: log_char=nibble_ascii(dd[23:20]); 8'd190: log_char=nibble_ascii(dd[19:16]); 8'd191: log_char=nibble_ascii(dd[15:12]); 8'd192: log_char=nibble_ascii(dd[11:8]); 8'd193: log_char=nibble_ascii(dd[7:4]); 8'd194: log_char=nibble_ascii(dd[3:0]); 8'd195: log_char=" ";
            8'd196: log_char="T"; 8'd197: log_char="H"; 8'd198: log_char="="; 8'd199: log_char=nibble_ascii(th[15:12]); 8'd200: log_char=nibble_ascii(th[11:8]); 8'd201: log_char=nibble_ascii(th[7:4]); 8'd202: log_char=nibble_ascii(th[3:0]); 8'd203: log_char=" ";
            8'd204: log_char="T"; 8'd205: log_char="T"; 8'd206: log_char="="; 8'd207: log_char=nibble_ascii(tt[15:12]); 8'd208: log_char=nibble_ascii(tt[11:8]); 8'd209: log_char=nibble_ascii(tt[7:4]); 8'd210: log_char=nibble_ascii(tt[3:0]); 8'd211: log_char=" ";
            8'd212: log_char="T"; 8'd213: log_char="O"; 8'd214: log_char="="; 8'd215: log_char=nibble_ascii(txo[31:28]); 8'd216: log_char=nibble_ascii(txo[27:24]); 8'd217: log_char=nibble_ascii(txo[23:20]); 8'd218: log_char=nibble_ascii(txo[19:16]); 8'd219: log_char=nibble_ascii(txo[15:12]); 8'd220: log_char=nibble_ascii(txo[11:8]); 8'd221: log_char=nibble_ascii(txo[7:4]); 8'd222: log_char=nibble_ascii(txo[3:0]); 8'd223: log_char=" ";
            8'd224: log_char="L"; 8'd225: log_char="M"; 8'd226: log_char="="; 8'd227: log_char=nibble_ascii(lm[31:28]); 8'd228: log_char=nibble_ascii(lm[27:24]); 8'd229: log_char=nibble_ascii(lm[23:20]); 8'd230: log_char=nibble_ascii(lm[19:16]); 8'd231: log_char=nibble_ascii(lm[15:12]); 8'd232: log_char=nibble_ascii(lm[11:8]); 8'd233: log_char=nibble_ascii(lm[7:4]); 8'd234: log_char=nibble_ascii(lm[3:0]); 8'd235: log_char=" ";
            8'd236: log_char="H"; 8'd237: log_char="M"; 8'd238: log_char="="; 8'd239: log_char=nibble_ascii(hm[31:28]); 8'd240: log_char=nibble_ascii(hm[27:24]); 8'd241: log_char=nibble_ascii(hm[23:20]); 8'd242: log_char=nibble_ascii(hm[19:16]); 8'd243: log_char=nibble_ascii(hm[15:12]); 8'd244: log_char=nibble_ascii(hm[11:8]); 8'd245: log_char=nibble_ascii(hm[7:4]); 8'd246: log_char=nibble_ascii(hm[3:0]); 8'd247: log_char=" ";
            9'd248: log_char="M"; 9'd249: log_char="M"; 9'd250: log_char="="; 9'd251: log_char=nibble_ascii(mm[31:28]); 9'd252: log_char=nibble_ascii(mm[27:24]); 9'd253: log_char=nibble_ascii(mm[23:20]); 9'd254: log_char=nibble_ascii(mm[19:16]); 9'd255: log_char=nibble_ascii(mm[15:12]); 9'd256: log_char=nibble_ascii(mm[11:8]); 9'd257: log_char=nibble_ascii(mm[7:4]); 9'd258: log_char=nibble_ascii(mm[3:0]); 9'd259: log_char=" ";
            9'd260: log_char="P"; 9'd261: log_char="R"; 9'd262: log_char="="; 9'd263: log_char=nibble_ascii(pr[31:28]); 9'd264: log_char=nibble_ascii(pr[27:24]); 9'd265: log_char=nibble_ascii(pr[23:20]); 9'd266: log_char=nibble_ascii(pr[19:16]); 9'd267: log_char=nibble_ascii(pr[15:12]); 9'd268: log_char=nibble_ascii(pr[11:8]); 9'd269: log_char=nibble_ascii(pr[7:4]); 9'd270: log_char=nibble_ascii(pr[3:0]); 9'd271: log_char=" ";
            9'd272: log_char="L"; 9'd273: log_char="V"; 9'd274: log_char="="; 9'd275: log_char=nibble_ascii(lv); 9'd276: log_char=" ";
            9'd277: log_char="S"; 9'd278: log_char="C"; 9'd279: log_char="="; 9'd280: log_char=nibble_ascii(sc[7:4]); 9'd281: log_char=nibble_ascii(sc[3:0]); 9'd282: log_char=" ";
            9'd283: log_char="P"; 9'd284: log_char="C"; 9'd285: log_char="="; 9'd286: log_char=nibble_ascii(pc[31:28]); 9'd287: log_char=nibble_ascii(pc[27:24]); 9'd288: log_char=nibble_ascii(pc[23:20]); 9'd289: log_char=nibble_ascii(pc[19:16]); 9'd290: log_char=nibble_ascii(pc[15:12]); 9'd291: log_char=nibble_ascii(pc[11:8]); 9'd292: log_char=nibble_ascii(pc[7:4]); 9'd293: log_char=nibble_ascii(pc[3:0]); 9'd294: log_char=" ";
            9'd295: log_char="P"; 9'd296: log_char="A"; 9'd297: log_char="="; 9'd298: log_char=nibble_ascii(pa[31:28]); 9'd299: log_char=nibble_ascii(pa[27:24]); 9'd300: log_char=nibble_ascii(pa[23:20]); 9'd301: log_char=nibble_ascii(pa[19:16]); 9'd302: log_char=nibble_ascii(pa[15:12]); 9'd303: log_char=nibble_ascii(pa[11:8]); 9'd304: log_char=nibble_ascii(pa[7:4]); 9'd305: log_char=nibble_ascii(pa[3:0]); 9'd306: log_char=" ";
            9'd307: log_char="P"; 9'd308: log_char="J"; 9'd309: log_char="="; 9'd310: log_char=nibble_ascii(pj[31:28]); 9'd311: log_char=nibble_ascii(pj[27:24]); 9'd312: log_char=nibble_ascii(pj[23:20]); 9'd313: log_char=nibble_ascii(pj[19:16]); 9'd314: log_char=nibble_ascii(pj[15:12]); 9'd315: log_char=nibble_ascii(pj[11:8]); 9'd316: log_char=nibble_ascii(pj[7:4]); 9'd317: log_char=nibble_ascii(pj[3:0]); 9'd318: log_char=" ";
            9'd319: log_char="P"; 9'd320: log_char="L"; 9'd321: log_char="="; 9'd322: log_char=nibble_ascii(pl[7:4]); 9'd323: log_char=nibble_ascii(pl[3:0]); 9'd324: log_char=" ";
            9'd325: log_char="R"; 9'd326: log_char="V"; 9'd327: log_char="="; 9'd328: log_char=nibble_ascii(rv[31:28]); 9'd329: log_char=nibble_ascii(rv[27:24]); 9'd330: log_char=nibble_ascii(rv[23:20]); 9'd331: log_char=nibble_ascii(rv[19:16]); 9'd332: log_char=nibble_ascii(rv[15:12]); 9'd333: log_char=nibble_ascii(rv[11:8]); 9'd334: log_char=nibble_ascii(rv[7:4]); 9'd335: log_char=nibble_ascii(rv[3:0]); 9'd336: log_char=" ";
            9'd337: log_char="S"; 9'd338: log_char="P"; 9'd339: log_char="="; 9'd340: log_char=nibble_ascii(sp); 9'd341: log_char=" ";
            9'd342: log_char="S"; 9'd343: log_char="Q"; 9'd344: log_char="="; 9'd345: log_char=nibble_ascii(sq[31:28]); 9'd346: log_char=nibble_ascii(sq[27:24]); 9'd347: log_char=nibble_ascii(sq[23:20]); 9'd348: log_char=nibble_ascii(sq[19:16]); 9'd349: log_char=nibble_ascii(sq[15:12]); 9'd350: log_char=nibble_ascii(sq[11:8]); 9'd351: log_char=nibble_ascii(sq[7:4]); 9'd352: log_char=nibble_ascii(sq[3:0]); 9'd353: log_char=" ";
            9'd354: log_char="R"; 9'd355: log_char="T"; 9'd356: log_char="="; 9'd357: log_char=nibble_ascii(rt[31:28]); 9'd358: log_char=nibble_ascii(rt[27:24]); 9'd359: log_char=nibble_ascii(rt[23:20]); 9'd360: log_char=nibble_ascii(rt[19:16]); 9'd361: log_char=nibble_ascii(rt[15:12]); 9'd362: log_char=nibble_ascii(rt[11:8]); 9'd363: log_char=nibble_ascii(rt[7:4]); 9'd364: log_char=nibble_ascii(rt[3:0]); 9'd365: log_char=" ";
            9'd366: log_char="S"; 9'd367: log_char="L"; 9'd368: log_char="="; 9'd369: log_char=nibble_ascii(sl[31:28]); 9'd370: log_char=nibble_ascii(sl[27:24]); 9'd371: log_char=nibble_ascii(sl[23:20]); 9'd372: log_char=nibble_ascii(sl[19:16]); 9'd373: log_char=nibble_ascii(sl[15:12]); 9'd374: log_char=nibble_ascii(sl[11:8]); 9'd375: log_char=nibble_ascii(sl[7:4]); 9'd376: log_char=nibble_ascii(sl[3:0]); 9'd377: log_char=" ";
            9'd378: log_char="S"; 9'd379: log_char="M"; 9'd380: log_char="="; 9'd381: log_char=nibble_ascii(sm[31:28]); 9'd382: log_char=nibble_ascii(sm[27:24]); 9'd383: log_char=nibble_ascii(sm[23:20]); 9'd384: log_char=nibble_ascii(sm[19:16]); 9'd385: log_char=nibble_ascii(sm[15:12]); 9'd386: log_char=nibble_ascii(sm[11:8]); 9'd387: log_char=nibble_ascii(sm[7:4]); 9'd388: log_char=nibble_ascii(sm[3:0]); 9'd389: log_char=" ";
            9'd390: log_char="S"; 9'd391: log_char="A"; 9'd392: log_char="="; 9'd393: log_char=nibble_ascii(sa[31:28]); 9'd394: log_char=nibble_ascii(sa[27:24]); 9'd395: log_char=nibble_ascii(sa[23:20]); 9'd396: log_char=nibble_ascii(sa[19:16]); 9'd397: log_char=nibble_ascii(sa[15:12]); 9'd398: log_char=nibble_ascii(sa[11:8]); 9'd399: log_char=nibble_ascii(sa[7:4]); 9'd400: log_char=nibble_ascii(sa[3:0]); 9'd401: log_char=" ";
            9'd402: log_char="S"; 9'd403: log_char="V"; 9'd404: log_char="="; 9'd405: log_char=nibble_ascii(sv[31:28]); 9'd406: log_char=nibble_ascii(sv[27:24]); 9'd407: log_char=nibble_ascii(sv[23:20]); 9'd408: log_char=nibble_ascii(sv[19:16]); 9'd409: log_char=nibble_ascii(sv[15:12]); 9'd410: log_char=nibble_ascii(sv[11:8]); 9'd411: log_char=nibble_ascii(sv[7:4]); 9'd412: log_char=nibble_ascii(sv[3:0]); 9'd413: log_char=8'h0D; 9'd414: log_char=8'h0A;
            default: log_char = 8'h00;
        endcase
    end
endfunction

// "ILC3RTX RQ=XXXXXXXX AK=XXXXXXXX TA=XXXXXXXX TM=XXXXXXXX TF=XXXXXXXX TL=XXXXXXXX OX=XXXXXXXX RX=XXXXXXXX\r\n"
function [7:0] rtx_log_char;
    input [6:0] ptr;
    input [31:0] rq;
    input [31:0] ak;
    input [31:0] ta;
    input [31:0] tm;
    input [31:0] tf;
    input [31:0] tl;
    input [31:0] ox;
    input [31:0] rx;
    begin
        case (ptr)
            7'd0: rtx_log_char="I"; 7'd1: rtx_log_char="L"; 7'd2: rtx_log_char="C"; 7'd3: rtx_log_char="3"; 7'd4: rtx_log_char="R"; 7'd5: rtx_log_char="T"; 7'd6: rtx_log_char="X"; 7'd7: rtx_log_char=" ";
            7'd8: rtx_log_char="R"; 7'd9: rtx_log_char="Q"; 7'd10: rtx_log_char="="; 7'd11: rtx_log_char=nibble_ascii(rq[31:28]); 7'd12: rtx_log_char=nibble_ascii(rq[27:24]); 7'd13: rtx_log_char=nibble_ascii(rq[23:20]); 7'd14: rtx_log_char=nibble_ascii(rq[19:16]); 7'd15: rtx_log_char=nibble_ascii(rq[15:12]); 7'd16: rtx_log_char=nibble_ascii(rq[11:8]); 7'd17: rtx_log_char=nibble_ascii(rq[7:4]); 7'd18: rtx_log_char=nibble_ascii(rq[3:0]); 7'd19: rtx_log_char=" ";
            7'd20: rtx_log_char="A"; 7'd21: rtx_log_char="K"; 7'd22: rtx_log_char="="; 7'd23: rtx_log_char=nibble_ascii(ak[31:28]); 7'd24: rtx_log_char=nibble_ascii(ak[27:24]); 7'd25: rtx_log_char=nibble_ascii(ak[23:20]); 7'd26: rtx_log_char=nibble_ascii(ak[19:16]); 7'd27: rtx_log_char=nibble_ascii(ak[15:12]); 7'd28: rtx_log_char=nibble_ascii(ak[11:8]); 7'd29: rtx_log_char=nibble_ascii(ak[7:4]); 7'd30: rtx_log_char=nibble_ascii(ak[3:0]); 7'd31: rtx_log_char=" ";
            7'd32: rtx_log_char="T"; 7'd33: rtx_log_char="A"; 7'd34: rtx_log_char="="; 7'd35: rtx_log_char=nibble_ascii(ta[31:28]); 7'd36: rtx_log_char=nibble_ascii(ta[27:24]); 7'd37: rtx_log_char=nibble_ascii(ta[23:20]); 7'd38: rtx_log_char=nibble_ascii(ta[19:16]); 7'd39: rtx_log_char=nibble_ascii(ta[15:12]); 7'd40: rtx_log_char=nibble_ascii(ta[11:8]); 7'd41: rtx_log_char=nibble_ascii(ta[7:4]); 7'd42: rtx_log_char=nibble_ascii(ta[3:0]); 7'd43: rtx_log_char=" ";
            7'd44: rtx_log_char="T"; 7'd45: rtx_log_char="M"; 7'd46: rtx_log_char="="; 7'd47: rtx_log_char=nibble_ascii(tm[31:28]); 7'd48: rtx_log_char=nibble_ascii(tm[27:24]); 7'd49: rtx_log_char=nibble_ascii(tm[23:20]); 7'd50: rtx_log_char=nibble_ascii(tm[19:16]); 7'd51: rtx_log_char=nibble_ascii(tm[15:12]); 7'd52: rtx_log_char=nibble_ascii(tm[11:8]); 7'd53: rtx_log_char=nibble_ascii(tm[7:4]); 7'd54: rtx_log_char=nibble_ascii(tm[3:0]); 7'd55: rtx_log_char=" ";
            7'd56: rtx_log_char="T"; 7'd57: rtx_log_char="F"; 7'd58: rtx_log_char="="; 7'd59: rtx_log_char=nibble_ascii(tf[31:28]); 7'd60: rtx_log_char=nibble_ascii(tf[27:24]); 7'd61: rtx_log_char=nibble_ascii(tf[23:20]); 7'd62: rtx_log_char=nibble_ascii(tf[19:16]); 7'd63: rtx_log_char=nibble_ascii(tf[15:12]); 7'd64: rtx_log_char=nibble_ascii(tf[11:8]); 7'd65: rtx_log_char=nibble_ascii(tf[7:4]); 7'd66: rtx_log_char=nibble_ascii(tf[3:0]); 7'd67: rtx_log_char=" ";
            7'd68: rtx_log_char="T"; 7'd69: rtx_log_char="L"; 7'd70: rtx_log_char="="; 7'd71: rtx_log_char=nibble_ascii(tl[31:28]); 7'd72: rtx_log_char=nibble_ascii(tl[27:24]); 7'd73: rtx_log_char=nibble_ascii(tl[23:20]); 7'd74: rtx_log_char=nibble_ascii(tl[19:16]); 7'd75: rtx_log_char=nibble_ascii(tl[15:12]); 7'd76: rtx_log_char=nibble_ascii(tl[11:8]); 7'd77: rtx_log_char=nibble_ascii(tl[7:4]); 7'd78: rtx_log_char=nibble_ascii(tl[3:0]); 7'd79: rtx_log_char=" ";
            7'd80: rtx_log_char="O"; 7'd81: rtx_log_char="X"; 7'd82: rtx_log_char="="; 7'd83: rtx_log_char=nibble_ascii(ox[31:28]); 7'd84: rtx_log_char=nibble_ascii(ox[27:24]); 7'd85: rtx_log_char=nibble_ascii(ox[23:20]); 7'd86: rtx_log_char=nibble_ascii(ox[19:16]); 7'd87: rtx_log_char=nibble_ascii(ox[15:12]); 7'd88: rtx_log_char=nibble_ascii(ox[11:8]); 7'd89: rtx_log_char=nibble_ascii(ox[7:4]); 7'd90: rtx_log_char=nibble_ascii(ox[3:0]); 7'd91: rtx_log_char=" ";
            7'd92: rtx_log_char="R"; 7'd93: rtx_log_char="X"; 7'd94: rtx_log_char="="; 7'd95: rtx_log_char=nibble_ascii(rx[31:28]); 7'd96: rtx_log_char=nibble_ascii(rx[27:24]); 7'd97: rtx_log_char=nibble_ascii(rx[23:20]); 7'd98: rtx_log_char=nibble_ascii(rx[19:16]); 7'd99: rtx_log_char=nibble_ascii(rx[15:12]); 7'd100: rtx_log_char=nibble_ascii(rx[11:8]); 7'd101: rtx_log_char=nibble_ascii(rx[7:4]); 7'd102: rtx_log_char=nibble_ascii(rx[3:0]); 7'd103: rtx_log_char=8'h0D; 7'd104: rtx_log_char=8'h0A;
            default: rtx_log_char = 8'h00;
        endcase
    end
endfunction

reg [15:0] dm_window_sample_cnt;
reg [5:0]  log_window_div_cnt;
reg [3:0]  self_correct_window_cnt;
reg        log_emit_due_q;
reg        self_correct_apply_due_q;
reg [31:0] log_pk, log_ok, log_ng, log_be, log_ce, log_wi, log_fs, log_rs, log_dr, log_pi, log_rv;
reg [31:0] log_ts, log_tv, log_tr, log_te, log_tl;
reg [31:0] log_hc, log_mc, log_lc, log_ic;
reg [31:0] log_dh, log_dm, log_dl, log_di, log_db, log_dd;
reg [31:0] log_df, log_rc, log_rd;
reg [31:0] log_txh, log_txt, log_txo;
reg [31:0] log_lm, log_hm, log_mm, log_pr;
reg [31:0] log_pc, log_pa, log_pj;
reg [7:0]  log_pl;
reg [3:0]  log_sp;
reg [31:0] log_sq, log_rt, log_sl, log_sm, log_sa, log_sv;
reg [31:0] prev_hc, prev_mc, prev_lc, prev_ic;
reg [31:0] prev_pkt_cnt, prev_resync_drop_cnt, prev_partial_drop_cnt;
reg [31:0] prev_pkt_ng_cnt, prev_byte_err_cnt, prev_crc_err_cnt;
reg [31:0] prev_tag_valid_cnt_for_dm;
reg [7:0]  log_fg;
reg [3:0]  log_lv;
reg [7:0]  log_sc;
reg [7:0]  log_lb;
reg        log_req;
reg [2:0]  log_calc_stage;
reg [31:0] dm_invalid_delta_q;
reg [31:0] dm_tag_samples_q;
reg [31:0] dm_non_mid_q;
reg [31:0] dm_base_q;
reg [31:0] dm_defer_cnt;
reg [31:0] dm_recover_cnt;
reg [31:0] dm_drop_cnt;
reg        dm_defer_active_q;
reg [31:0] dm_dd_q;
reg [31:0] dm_abs_dd_q;
reg [31:0] latency_cycle_cnt;
reg [31:0] dm_defer_cycle_q;
reg [31:0] dm_last_recovery_latency_q;
reg [31:0] dm_max_recovery_latency_q;
reg [31:0] dm_recovery_latency_sum_q;
reg [31:0] dm_recovery_latency_valid_cnt_q;
wire [31:0] dm_recovery_latency_delta_w = latency_cycle_cnt - dm_defer_cycle_q;
reg        link_stop_active_q;
reg [3:0]  link_clean_window_cnt_q;
reg [31:0] link_stop_cycle_q;
reg [31:0] link_stop_cnt_q;
reg [31:0] link_retransmit_req_cnt_q;
reg [31:0] link_stop_last_latency_q;
reg [31:0] link_stop_max_latency_q;
reg [31:0] link_stop_latency_sum_q;
reg [31:0] link_stop_latency_valid_cnt_q;
reg        link_stop_resume_pulse_q;
reg [31:0] link_stop_resume_latency_q;
reg        link_policy_eval_valid_q;
reg        link_policy_fault_eval_q;
reg        link_policy_clean_eval_q;
reg [31:0] last_fail_seq_q;
reg        last_fail_seq_valid_q;
reg        rtx_wait_accept_q;
reg [31:0] rtx_req_cycle_q;
reg [31:0] rtx_orig_seq_q;
reg [31:0] rtx_accept_seq_q;
reg [31:0] rtx_request_cnt_q;
reg [31:0] rtx_ack_cnt_q;
reg [31:0] rtx_accept_cnt_q;
reg [31:0] rtx_match_cnt_q;
reg [31:0] rtx_fail_cnt_q;
reg [31:0] rtx_last_latency_q;
reg [31:0] log_rq, log_ak, log_ta, log_tm, log_tf, log_rtl, log_ox, log_rxseq;

wire        log_window_due = (log_window_div_cnt == LOG_EVERY_WINDOWS - 1);
wire        self_correct_update_due = (self_correct_window_cnt == SELF_CORRECT_EVERY_WINDOWS - 1);

wire [31:0] next_dh = hist_high_cnt - prev_hc;
wire [31:0] next_dm = hist_mid_cnt - prev_mc;
wire [31:0] next_dl = hist_low_cnt - prev_lc;
wire [31:0] next_di = hist_invalid_cnt - prev_ic;
wire [31:0] next_dng = pkt_ng_cnt - prev_pkt_ng_cnt;
wire [31:0] next_dbe = byte_err_cnt - prev_byte_err_cnt;
wire [31:0] next_dce = crc_err_cnt - prev_crc_err_cnt;
wire [31:0] next_tag_valid_delta = tag_valid_cnt - prev_tag_valid_cnt_for_dm;
wire [31:0] next_tag_samples = next_tag_valid_delta << 1;
wire        flag_invalid = (next_di != 32'd0) || (next_dng != 32'd0);
wire        flag_collapse = (next_dl == 32'd0) || (next_dl < DL_MIN_TH);
wire        flag_high_shift = (next_dh > DH_HIGH_TH);
wire        flag_mid_loss = (next_dm < DM_LOW_TH);
wire        flag_stall = (pkt_cnt == prev_pkt_cnt) &&
                         ((resync_drop_cnt != prev_resync_drop_cnt) ||
                          (partial_drop_cnt != prev_partial_drop_cnt));
wire        flag_packet_error = (next_dng != 32'd0) ||
                                (next_dbe != 32'd0);
wire        flag_warning = (next_dh > DH_WARN_TH) || (next_dm < DM_WARN_TH);
wire [7:0]  next_fg = {1'b0, flag_warning, flag_packet_error, flag_stall, flag_mid_loss, flag_high_shift, flag_collapse, flag_invalid};
wire [3:0]  next_lv =
    (flag_packet_error || flag_invalid) ? 4'd4 :
    (flag_collapse || (flag_stall && flag_high_shift)) ? 4'd3 :
    (flag_stall || (flag_high_shift && flag_mid_loss)) ? 4'd2 :
    (flag_warning || flag_high_shift || flag_mid_loss) ? 4'd1 : 4'd0;
wire        triple_ref_window_active = (next_lv != 4'd0) ||
                                       (next_dce != 32'd0) ||
                                       flag_packet_error;
wire        self_correct_active = ENABLE_SELF_CORRECT &&
                                  !log_fg[5] &&
                                  !log_fg[0] &&
                                  (log_lv >= 4'd2);
wire        self_correct_clean = ENABLE_SELF_CORRECT && (log_lv == 4'd0);
wire        self_correct_reverse = self_correct_active &&
                                   (self_correct_prev_lv_q >= 4'd2) &&
                                   (log_lv > self_correct_prev_lv_q);
wire        self_correct_next_dir = self_correct_reverse ? !self_correct_dir_q : self_correct_dir_q;
wire        self_correct_can_inc = sample_delay_trim_q < SELF_CORRECT_MAX_DELAY_8;
wire        self_correct_can_dec = sample_delay_trim_q > SELF_CORRECT_MIN_DELAY_8;
wire        self_correct_fast_now = self_correct_active &&
                                    (log_lv == 4'd3) &&
                                    ((log_dl == 32'd0) || (log_fg == 8'h5E));
wire        triple_ref_fast_reset = ENABLE_SELF_CORRECT &&
                                    (log_lv >= 4'd3) &&
                                    ((log_pr >= TR_FAST_PR_TH) ||
                                     (log_hm >= TR_FAST_HM_TH) ||
                                     (log_mm != 32'd0));
wire        self_correct_can_inc2 = sample_delay_trim_q <= (SELF_CORRECT_MAX_DELAY_8 - 8'd2);
wire        self_correct_can_dec2 = sample_delay_trim_q >= (SELF_CORRECT_MIN_DELAY_8 + 8'd2);
wire [7:0]  self_correct_inc_delay = sample_delay_trim_q + 8'd1;
wire [7:0]  self_correct_dec_delay = sample_delay_trim_q - 8'd1;
wire        self_correct_above_init = sample_delay_trim_q > SAMPLE_DELAY_INIT;
wire        self_correct_below_init = sample_delay_trim_q < SAMPLE_DELAY_INIT;
wire [7:0]  self_correct_updated_delay =
    (self_correct_active && self_correct_next_dir && self_correct_can_inc) ? self_correct_inc_delay :
    (self_correct_active && !self_correct_next_dir && self_correct_can_dec) ? self_correct_dec_delay :
    (self_correct_clean && self_correct_above_init) ? (sample_delay_trim_q - 8'd1) :
    (self_correct_clean && self_correct_below_init) ? (sample_delay_trim_q + 8'd1) :
    sample_delay_trim_q;
wire        self_correct_failure = ENABLE_SELF_CORRECT && (log_lv == 4'd4);
wire [7:0]  self_correct_next_delay = self_correct_failure ? SAMPLE_DELAY_INIT : self_correct_updated_delay;
wire        link_policy_fault_window = (next_dng != 32'd0) || (next_dce != 32'd0);
wire        link_policy_all_closed = (dm_defer_cnt == (dm_recover_cnt + dm_drop_cnt));
wire        link_policy_clean_window = (next_lv == 4'd0) &&
                                       !link_policy_fault_window &&
                                       !dm_defer_active_q &&
                                       link_policy_all_closed;
wire [31:0] link_stop_latency_delta_w = latency_cycle_cnt - link_stop_cycle_q;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        dm_window_sample_cnt <= 16'd0; log_req <= 1'b0;
        log_window_div_cnt <= 6'd0;
        self_correct_window_cnt <= 4'd0;
        log_emit_due_q <= 1'b1;
        self_correct_apply_due_q <= 1'b0;
        log_pk <= 32'd0; log_ok <= 32'd0; log_ng <= 32'd0; log_be <= 32'd0; log_ce <= 32'd0; log_wi <= 32'd0; log_fs <= 32'd0; log_rs <= 32'd0; log_dr <= 32'd0; log_pi <= 32'd0; log_rv <= 32'd0; log_ts <= 32'd0; log_tv <= 32'd0; log_tr <= 32'd0; log_te <= 32'd0; log_tl <= 32'd0; log_lb <= 8'd0;
        log_hc <= 32'd0; log_mc <= 32'd0; log_lc <= 32'd0; log_ic <= 32'd0;
        log_dh <= 32'd0; log_dm <= 32'd0; log_dl <= 32'd0; log_di <= 32'd0; log_db <= 32'd0; log_dd <= 32'd0;
        log_df <= 32'd0; log_rc <= 32'd0; log_rd <= 32'd0;
        log_txh <= 32'd0; log_txt <= 32'd0; log_txo <= 32'd0;
        log_lm <= 32'd0; log_hm <= 32'd0; log_mm <= 32'd0; log_pr <= 32'd0;
        log_pc <= 32'd0; log_pa <= 32'd0; log_pj <= 32'd0; log_pl <= 8'h00;
        log_sp <= 4'd0; log_sq <= 32'd0; log_rt <= 32'd0; log_sl <= 32'd0; log_sm <= 32'd0; log_sa <= 32'd0; log_sv <= 32'd0;
        prev_hc <= 32'd0; prev_mc <= 32'd0; prev_lc <= 32'd0; prev_ic <= 32'd0;
        prev_pkt_cnt <= 32'd0; prev_resync_drop_cnt <= 32'd0; prev_partial_drop_cnt <= 32'd0;
        prev_pkt_ng_cnt <= 32'd0; prev_byte_err_cnt <= 32'd0; prev_crc_err_cnt <= 32'd0;
        prev_tag_valid_cnt_for_dm <= 32'd0;
        log_fg <= 8'd0; log_lv <= 4'd0; log_sc <= SAMPLE_DELAY_INIT;
        log_calc_stage <= 2'd0;
        dm_invalid_delta_q <= 32'd0;
        dm_tag_samples_q <= 32'd0;
        dm_non_mid_q <= 32'd0;
        dm_base_q <= 32'd0;
        dm_defer_cnt <= 32'd0;
        dm_recover_cnt <= 32'd0;
        dm_drop_cnt <= 32'd0;
        dm_defer_active_q <= 1'b0;
        dm_dd_q <= 32'd0;
        dm_abs_dd_q <= 32'd0;
        latency_cycle_cnt <= 32'd0;
        dm_defer_cycle_q <= 32'd0;
        dm_last_recovery_latency_q <= 32'd0;
        dm_max_recovery_latency_q <= 32'd0;
        dm_recovery_latency_sum_q <= 32'd0;
        dm_recovery_latency_valid_cnt_q <= 32'd0;
        link_stop_active_q <= 1'b0;
        link_clean_window_cnt_q <= 4'd0;
        link_stop_cycle_q <= 32'd0;
        link_stop_cnt_q <= 32'd0;
        link_retransmit_req_cnt_q <= 32'd0;
        link_stop_last_latency_q <= 32'd0;
        link_stop_max_latency_q <= 32'd0;
        link_stop_latency_sum_q <= 32'd0;
        link_stop_latency_valid_cnt_q <= 32'd0;
        link_stop_resume_pulse_q <= 1'b0;
        link_stop_resume_latency_q <= 32'd0;
        link_policy_eval_valid_q <= 1'b0;
        link_policy_fault_eval_q <= 1'b0;
        link_policy_clean_eval_q <= 1'b0;
        rtx_wait_accept_q <= 1'b0;
        rtx_req_cycle_q <= 32'd0;
        rtx_orig_seq_q <= 32'd0;
        rtx_accept_seq_q <= 32'd0;
        rtx_request_cnt_q <= 32'd0;
        rtx_ack_cnt_q <= 32'd0;
        rtx_accept_cnt_q <= 32'd0;
        rtx_match_cnt_q <= 32'd0;
        rtx_fail_cnt_q <= 32'd0;
        rtx_last_latency_q <= 32'd0;
        log_rq <= 32'd0; log_ak <= 32'd0; log_ta <= 32'd0; log_tm <= 32'd0; log_tf <= 32'd0; log_rtl <= 32'd0; log_ox <= 32'd0; log_rxseq <= 32'd0;
        sample_delay_trim_q <= SAMPLE_DELAY_INIT;
        self_correct_dir_q <= 1'b1;
        self_correct_prev_lv_q <= 4'd0;
        self_correct_fast_q <= 1'b0;
        self_correct_step_cnt <= 32'd0;
        rx_soft_recover_q <= 1'b0;
    end else begin
        latency_cycle_cnt <= latency_cycle_cnt + 32'd1;
        log_req <= 1'b0;
        rx_soft_recover_q <= 1'b0;
        if (link_stop_resume_pulse_q) begin
            link_stop_last_latency_q <= link_stop_resume_latency_q;
            if (link_stop_resume_latency_q > link_stop_max_latency_q) begin
                link_stop_max_latency_q <= link_stop_resume_latency_q;
            end
            link_stop_latency_sum_q <= link_stop_latency_sum_q + link_stop_resume_latency_q;
            link_stop_latency_valid_cnt_q <= link_stop_latency_valid_cnt_q + 32'd1;
            rtx_ack_cnt_q <= rtx_ack_cnt_q + 32'd1;
            rtx_wait_accept_q <= 1'b1;
        end
        if (pass_pulse && rtx_wait_accept_q) begin
            rtx_accept_cnt_q <= rtx_accept_cnt_q + 32'd1;
            rtx_accept_seq_q <= seq_rx;
            rtx_last_latency_q <= latency_cycle_cnt - rtx_req_cycle_q;
            rtx_wait_accept_q <= 1'b0;
            if (seq_rx == rtx_orig_seq_q) begin
                rtx_match_cnt_q <= rtx_match_cnt_q + 32'd1;
            end else begin
                rtx_fail_cnt_q <= rtx_fail_cnt_q + 32'd1;
            end
        end
        link_stop_resume_pulse_q <= 1'b0;
        if (link_policy_eval_valid_q) begin
            if (link_policy_fault_eval_q) begin
                if (!link_stop_active_q) begin
                    link_stop_active_q <= 1'b1;
                    link_stop_cycle_q <= latency_cycle_cnt;
                    link_stop_cnt_q <= link_stop_cnt_q + 32'd1;
                    rtx_request_cnt_q <= rtx_request_cnt_q + 32'd1;
                    rtx_req_cycle_q <= latency_cycle_cnt;
                    rtx_orig_seq_q <= last_fail_seq_valid_q ? last_fail_seq_q : seq_rx;
                    rtx_wait_accept_q <= 1'b0;
                end
                link_clean_window_cnt_q <= 4'd0;
            end else if (link_stop_active_q) begin
                if (link_policy_clean_eval_q) begin
                    if (link_clean_window_cnt_q >= (LINK_STABLE_CLEAN_WINDOWS - 4'd1)) begin
                        link_stop_active_q <= 1'b0;
                        link_clean_window_cnt_q <= 4'd0;
                        link_retransmit_req_cnt_q <= link_retransmit_req_cnt_q + 32'd1;
                        link_stop_resume_latency_q <= link_stop_latency_delta_w;
                        link_stop_resume_pulse_q <= 1'b1;
                    end else begin
                        link_clean_window_cnt_q <= link_clean_window_cnt_q + 4'd1;
                    end
                end else begin
                    link_clean_window_cnt_q <= 4'd0;
                end
            end else begin
                link_clean_window_cnt_q <= 4'd0;
            end
        end
        link_policy_eval_valid_q <= 1'b0;
        if (!dm_defer_active_q && (fail_pulse || pkt_dm_defer_pulse)) begin
            dm_defer_cnt <= dm_defer_cnt + 32'd1;
            log_df <= dm_defer_cnt + 32'd1;
            dm_defer_active_q <= 1'b1;
            dm_defer_cycle_q <= latency_cycle_cnt;
        end else if (dm_defer_active_q && pass_pulse) begin
            dm_recover_cnt <= dm_recover_cnt + 32'd1;
            log_rc <= dm_recover_cnt + 32'd1;
            if (dm_recovery_latency_delta_w <= RECOVERY_LATENCY_MAX_VALID) begin
                dm_last_recovery_latency_q <= dm_recovery_latency_delta_w;
                log_rs <= dm_recovery_latency_delta_w;
                if (dm_recovery_latency_delta_w > dm_max_recovery_latency_q) begin
                    dm_max_recovery_latency_q <= dm_recovery_latency_delta_w;
                    log_dr <= dm_recovery_latency_delta_w;
                end else begin
                    log_dr <= dm_max_recovery_latency_q;
                end
                dm_recovery_latency_sum_q <= dm_recovery_latency_sum_q + dm_recovery_latency_delta_w;
                log_pi <= dm_recovery_latency_sum_q + dm_recovery_latency_delta_w;
                dm_recovery_latency_valid_cnt_q <= dm_recovery_latency_valid_cnt_q + 32'd1;
                log_rv <= dm_recovery_latency_valid_cnt_q + 32'd1;
            end else begin
                log_rs <= dm_last_recovery_latency_q;
                log_dr <= dm_max_recovery_latency_q;
                log_pi <= dm_recovery_latency_sum_q;
                log_rv <= dm_recovery_latency_valid_cnt_q;
            end
            dm_defer_active_q <= 1'b0;
        end
        if (log_calc_stage == 2'd1) begin
            dm_non_mid_q <= log_dh + log_dl + dm_invalid_delta_q;
            log_calc_stage <= 2'd2;
        end else if (log_calc_stage == 2'd2) begin
            dm_base_q <= (dm_non_mid_q > dm_tag_samples_q) ?
                         (dm_non_mid_q - dm_tag_samples_q) : 32'd0;
            log_calc_stage <= 3'd3;
        end else if (log_calc_stage == 3'd3) begin
            log_db <= dm_base_q;
            log_dd <= log_dm - dm_base_q;
            dm_dd_q <= log_dm - dm_base_q;
            dm_abs_dd_q <= abs32_twos(log_dm - dm_base_q);
            log_calc_stage <= 3'd4;
        end else if (log_calc_stage == 3'd4) begin
            if (dm_defer_active_q) begin
                if (log_lv == 4'd4) begin
                    dm_drop_cnt <= dm_drop_cnt + 32'd1;
                    log_rd <= dm_drop_cnt + 32'd1;
                    dm_defer_active_q <= 1'b0;
                    if (!link_stop_active_q) begin
                        link_stop_active_q <= 1'b1;
                        link_stop_cycle_q <= latency_cycle_cnt;
                        link_stop_cnt_q <= link_stop_cnt_q + 32'd1;
                        rtx_request_cnt_q <= rtx_request_cnt_q + 32'd1;
                        rtx_req_cycle_q <= latency_cycle_cnt;
                        rtx_orig_seq_q <= last_fail_seq_valid_q ? last_fail_seq_q : seq_rx;
                        rtx_wait_accept_q <= 1'b0;
                        log_sp <= 4'd1;
                        log_sq <= link_stop_cnt_q + 32'd1;
                    end
                    link_clean_window_cnt_q <= 4'd0;
                end else if ((log_lv == 4'd0) &&
                             (dm_abs_dd_q <= DM_RECOVER_DD_TH)) begin
                    dm_recover_cnt <= dm_recover_cnt + 32'd1;
                    log_rc <= dm_recover_cnt + 32'd1;
                    if (dm_recovery_latency_delta_w <= RECOVERY_LATENCY_MAX_VALID) begin
                        dm_last_recovery_latency_q <= dm_recovery_latency_delta_w;
                        log_rs <= dm_recovery_latency_delta_w;
                        if (dm_recovery_latency_delta_w > dm_max_recovery_latency_q) begin
                            dm_max_recovery_latency_q <= dm_recovery_latency_delta_w;
                            log_dr <= dm_recovery_latency_delta_w;
                        end else begin
                            log_dr <= dm_max_recovery_latency_q;
                        end
                        dm_recovery_latency_sum_q <= dm_recovery_latency_sum_q + dm_recovery_latency_delta_w;
                        log_pi <= dm_recovery_latency_sum_q + dm_recovery_latency_delta_w;
                        dm_recovery_latency_valid_cnt_q <= dm_recovery_latency_valid_cnt_q + 32'd1;
                        log_rv <= dm_recovery_latency_valid_cnt_q + 32'd1;
                    end else begin
                        log_rs <= dm_last_recovery_latency_q;
                        log_dr <= dm_max_recovery_latency_q;
                        log_pi <= dm_recovery_latency_sum_q;
                        log_rv <= dm_recovery_latency_valid_cnt_q;
                    end
                    dm_defer_active_q <= 1'b0;
                end
            end else if ((log_lv >= 4'd2) ||
                         (dm_abs_dd_q >= DM_DEFER_DD_TH)) begin
                dm_defer_cnt <= dm_defer_cnt + 32'd1;
                log_df <= dm_defer_cnt + 32'd1;
                dm_defer_active_q <= 1'b1;
                dm_defer_cycle_q <= latency_cycle_cnt;
            end
            if (ENABLE_SELF_CORRECT) begin
                if (self_correct_failure) begin
                    self_correct_dir_q <= 1'b1;
                    self_correct_fast_q <= 1'b0;
                    sample_delay_trim_q <= SAMPLE_DELAY_INIT;
                    log_sc <= SAMPLE_DELAY_INIT;
                    rx_soft_recover_q <= 1'b1;
                end else if (triple_ref_fast_reset) begin
                    self_correct_dir_q <= 1'b1;
                    self_correct_fast_q <= 1'b1;
                    sample_delay_trim_q <= SAMPLE_DELAY_INIT;
                    log_sc <= SAMPLE_DELAY_INIT;
                end else if (self_correct_apply_due_q) begin
                    self_correct_dir_q <= self_correct_next_dir;
                    self_correct_fast_q <= self_correct_fast_now;
                    sample_delay_trim_q <= self_correct_updated_delay;
                    log_sc <= self_correct_updated_delay;
                end else begin
                    self_correct_fast_q <= self_correct_fast_q;
                    log_sc <= sample_delay_trim_q;
                end
                if ((self_correct_apply_due_q || self_correct_failure) &&
                    (self_correct_next_delay != sample_delay_trim_q)) begin
                    self_correct_step_cnt <= self_correct_step_cnt + 32'd1;
                end
                self_correct_prev_lv_q <= log_lv;
            end else begin
                self_correct_fast_q <= 1'b0;
                log_sc <= sample_delay_trim_q;
            end
            self_correct_apply_due_q <= 1'b0;
            log_req <= log_emit_due_q;
            log_calc_stage <= 2'd0;
        end else if (amp_valid_q && (dm_window_sample_cnt == DM_WINDOW_SAMPLES - 1)) begin
            dm_window_sample_cnt <= 16'd0;
            if (log_window_due) begin
                log_window_div_cnt <= 6'd0;
            end else begin
                log_window_div_cnt <= log_window_div_cnt + 6'd1;
            end
            if (self_correct_update_due) begin
                self_correct_window_cnt <= 4'd0;
            end else begin
                self_correct_window_cnt <= self_correct_window_cnt + 4'd1;
            end
            log_emit_due_q <= log_window_due;
            self_correct_apply_due_q <= self_correct_update_due;
            link_policy_eval_valid_q <= 1'b1;
            link_policy_fault_eval_q <= link_policy_fault_window;
            link_policy_clean_eval_q <= link_policy_clean_window;
            log_pk <= pkt_cnt; log_ok <= pkt_ok_cnt; log_ng <= pkt_ng_cnt; log_be <= byte_err_cnt;
            log_ce <= crc_err_cnt; log_wi <= invalid_cnt; log_fs <= frame_sync_cnt; log_rs <= dm_last_recovery_latency_q; log_dr <= dm_max_recovery_latency_q; log_pi <= dm_recovery_latency_sum_q; log_rv <= dm_recovery_latency_valid_cnt_q; log_lb <= last_byte;
            log_ts <= tag_seen_cnt; log_tv <= tag_valid_cnt; log_tr <= tag_reject_cnt; log_te <= tag_seq_error_cnt; log_tl <= tag_lock_cnt;
            log_hc <= hist_high_cnt; log_mc <= hist_mid_cnt; log_lc <= hist_low_cnt; log_ic <= hist_invalid_cnt;
            log_dh <= next_dh;
            log_dm <= next_dm;
            log_dl <= next_dl;
            log_di <= 32'd0;
            dm_invalid_delta_q <= next_di;
            dm_tag_samples_q <= next_tag_samples;
            log_fg <= next_fg;
            log_lv <= next_lv;
            log_sc <= sample_delay_trim_q;
            log_txh <= {16'd0, txref_th_latched};
            log_txt <= {16'd0, txref_tt_latched};
            log_txo <= txref_ok_cnt;
            if (triple_ref_window_active) begin
                lm_rule_err_cnt <= lm_rule_err_cnt + lm_rule_window_cnt;
                hm_rule_err_cnt <= hm_rule_err_cnt + hm_rule_window_cnt;
                mm_rule_err_cnt <= mm_rule_err_cnt + mm_rule_window_cnt;
                pair_risk_cnt <= pair_risk_cnt + pair_risk_window_cnt;
                log_lm <= lm_rule_err_cnt + lm_rule_window_cnt;
                log_hm <= hm_rule_err_cnt + hm_rule_window_cnt;
                log_mm <= mm_rule_err_cnt + mm_rule_window_cnt;
                log_pr <= pair_risk_cnt + pair_risk_window_cnt;
            end else begin
                log_lm <= lm_rule_err_cnt;
                log_hm <= hm_rule_err_cnt;
                log_mm <= mm_rule_err_cnt;
                log_pr <= pair_risk_cnt;
            end
            log_pc <= pair_correct_candidate_cnt;
            log_pa <= pair_correct_accept_cnt;
            log_pj <= pair_correct_reject_cnt;
            log_pl <= pair_correct_last_code;
            log_sp <= {3'd0, link_stop_active_q};
            log_sq <= link_stop_cnt_q;
            log_rt <= link_retransmit_req_cnt_q;
            log_sl <= link_stop_last_latency_q;
            log_sm <= link_stop_max_latency_q;
            log_sa <= link_stop_latency_sum_q;
            log_sv <= link_stop_latency_valid_cnt_q;
            log_rq <= rtx_request_cnt_q;
            log_ak <= rtx_ack_cnt_q;
            log_ta <= rtx_accept_cnt_q;
            log_tm <= rtx_match_cnt_q;
            log_tf <= rtx_fail_cnt_q;
            log_rtl <= rtx_last_latency_q;
            log_ox <= rtx_orig_seq_q;
            log_rxseq <= rtx_accept_seq_q;
            prev_hc <= hist_high_cnt;
            prev_mc <= hist_mid_cnt;
            prev_lc <= hist_low_cnt;
            prev_ic <= hist_invalid_cnt;
            prev_pkt_cnt <= pkt_cnt;
            prev_resync_drop_cnt <= resync_drop_cnt;
            prev_partial_drop_cnt <= partial_drop_cnt;
            prev_pkt_ng_cnt <= pkt_ng_cnt;
            prev_byte_err_cnt <= byte_err_cnt;
            prev_crc_err_cnt <= crc_err_cnt;
            prev_tag_valid_cnt_for_dm <= tag_valid_cnt;
            log_calc_stage <= 2'd1;
        end else if (amp_valid_q) begin
            dm_window_sample_cnt <= dm_window_sample_cnt + 16'd1;
        end else begin
            dm_window_sample_cnt <= dm_window_sample_cnt;
        end
    end
end

reg [8:0] log_ptr;
reg       log_active;
reg       log_rtx_mode;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr <= 9'd0; log_active <= 1'b0; log_rtx_mode <= 1'b0; uart_start <= 1'b0; uart_data <= 8'h00;
    end else begin
        uart_start <= 1'b0;
        if (log_req && !log_active && !uart_busy) begin
            log_active <= 1'b1; log_rtx_mode <= 1'b0; log_ptr <= 9'd0;
        end else if (log_active && !uart_busy && !uart_start) begin
            uart_data <= log_rtx_mode ?
                         rtx_log_char(log_ptr[6:0], log_rq, log_ak, log_ta, log_tm, log_tf, log_rtl, log_ox, log_rxseq) :
                         log_char(log_ptr, log_pk, log_ok, log_ng, log_be, log_ce, log_df, log_fs, log_rs, log_dr, log_pi, log_ts, log_tv, log_tr, log_te, log_tl, log_lb, log_hc, log_mc, log_lc, log_rc, log_dh, log_dm, log_dl, log_rd, log_fg, log_lv, log_sc, log_db, log_dd, log_txh, log_txt, log_txo, log_lm, log_hm, log_mm, log_pr, log_pc, log_pa, log_pj, log_pl, log_rv, log_sp, log_sq, log_rt, log_sl, log_sm, log_sa, log_sv);
            uart_start <= 1'b1;
            if (!log_rtx_mode && (log_ptr == 9'd414)) begin
                log_rtx_mode <= 1'b1;
                log_ptr <= 9'd0;
            end else if (log_rtx_mode && (log_ptr == 9'd104)) begin
                log_active <= 1'b0;
                log_rtx_mode <= 1'b0;
            end else begin
                log_ptr <= log_ptr + 9'd1;
            end
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
