`timescale 1ns/1ps
//======================================================
// ILC3 0-code RX core (simple reference)
// - input: amplitude samples, 2 samples per symbol
// - codebook:
//   0 -> [-1,  0]
//   1 -> [ 0, -1]
//   2 -> [+1,  0]
//   3 -> [ 0, +1]
// - decode each 2-sample pair by direct lookup
// - frame_sync realigns the sample pairing at frame boundaries
//======================================================
module ilc3_rx_core #(
    parameter SYMB_WIDTH = 2,
    parameter AMP_WIDTH  = 4,
    parameter ENABLE_PAIR_CORRECT = 0,
    parameter ENABLE_LL_HH_CORRECT = 0
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        frame_sync,

    input  wire signed [AMP_WIDTH-1:0] amp_in,
    input  wire                        amp_in_valid,
    input  wire                        pair_correct_allow,
    input  wire                        pair_correct_expected_valid,
    input  wire [SYMB_WIDTH-1:0]       pair_correct_expected_sym,
    input  wire                        pair_correct_force_expected,
    input  wire                        pair_correct_lm_evidence,
    input  wire                        pair_correct_hm_evidence,
    output wire                        amp_in_ready,

    output reg  [SYMB_WIDTH-1:0]       sym_out,
    output reg                         sym_out_valid,
    input  wire                        sym_out_ready,
    output reg  [31:0]                 dbg_pairs,
    output reg                         pair_invalid_pulse,
    output reg  [7:0]                  pair_invalid_code,
    output reg                         pair_correct_pulse,
    output reg                         pair_correct_reject_pulse,
    output reg  [7:0]                  pair_correct_code,
    output reg                         sample_phase_dbg
);

    assign amp_in_ready = 1'b1;

    reg                        sample_phase;      // 0: first, 1: second
    reg signed [AMP_WIDTH-1:0] s0;
    reg signed [AMP_WIDTH-1:0] amp_norm;

    reg signed [AMP_WIDTH-1:0] t0, t1;
    reg                        pair_valid;
    reg [SYMB_WIDTH-1:0]      sym_cand;
    reg [3:0]                 dbg_pair_cnt;
    reg [SYMB_WIDTH-1:0]      prev_sym;
    reg                       prev_sym_valid;

    function signed [AMP_WIDTH-1:0] norm_amp;
        input [AMP_WIDTH-1:0] raw_amp;
        begin
            case (raw_amp)
                4'hF: norm_amp = -1;
                4'h0: norm_amp = 0;
                4'h1: norm_amp = 1;
                default: norm_amp = 0;
            endcase
        end
    endfunction

    function [3:0] norm_nibble;
        input [AMP_WIDTH-1:0] raw_amp;
        begin
            case (raw_amp)
                4'hF: norm_nibble = 4'hF;
                4'h0: norm_nibble = 4'h0;
                4'h1: norm_nibble = 4'h1;
                default: norm_nibble = 4'h0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_phase      <= 1'b0;
            s0                <= {AMP_WIDTH{1'b0}};
            amp_norm          <= {AMP_WIDTH{1'b0}};
            t0                <= {AMP_WIDTH{1'b0}};
            t1                <= {AMP_WIDTH{1'b0}};
            pair_valid        <= 1'b0;
            sym_out           <= {SYMB_WIDTH{1'b0}};
            sym_out_valid     <= 1'b0;
            dbg_pairs         <= 32'd0;
            dbg_pair_cnt      <= 4'd0;
            pair_invalid_pulse <= 1'b0;
            pair_invalid_code  <= 8'h00;
            pair_correct_pulse <= 1'b0;
            pair_correct_reject_pulse <= 1'b0;
            pair_correct_code <= 8'h00;
            sample_phase_dbg   <= 1'b0;
            prev_sym           <= {SYMB_WIDTH{1'b0}};
            prev_sym_valid     <= 1'b0;
        end else begin
            sym_out_valid <= 1'b0;
            pair_invalid_pulse <= 1'b0;
            pair_correct_pulse <= 1'b0;
            pair_correct_reject_pulse <= 1'b0;
            sample_phase_dbg <= sample_phase;

            if (frame_sync) begin
                sample_phase <= 1'b0;
                pair_valid   <= 1'b0;
                dbg_pairs    <= 32'd0;
                dbg_pair_cnt <= 4'd0;
                prev_sym_valid <= 1'b0;
            end

            if (amp_in_valid && amp_in_ready) begin
                amp_norm <= norm_amp(amp_in);
                if (dbg_pair_cnt < 4'd8) begin
                    dbg_pairs    <= {dbg_pairs[27:0], norm_nibble(amp_in)};
                    dbg_pair_cnt <= dbg_pair_cnt + 4'd1;
                end
                if (!sample_phase) begin
                    s0           <= norm_amp(amp_in);
                    sample_phase <= 1'b1;
                end else begin
                    sample_phase <= 1'b0;
                    t0           <= s0;
                    t1           <= norm_amp(amp_in);
                    pair_valid   <= 1'b1;
                end
            end

            if (pair_valid && sym_out_ready) begin
                case ({t0, t1})
                    {4'hF, 4'h0}: begin sym_cand = 2'd0; sym_out_valid <= 1'b1; prev_sym <= 2'd0; prev_sym_valid <= 1'b1; end // [-1, 0]
                    {4'h0, 4'hF}: begin sym_cand = 2'd1; sym_out_valid <= 1'b1; prev_sym <= 2'd1; prev_sym_valid <= 1'b1; end // [ 0,-1]
                    {4'h1, 4'h0}: begin sym_cand = 2'd2; sym_out_valid <= 1'b1; prev_sym <= 2'd2; prev_sym_valid <= 1'b1; end // [ 1, 0]
                    {4'h0, 4'h1}: begin sym_cand = 2'd3; sym_out_valid <= 1'b1; prev_sym <= 2'd3; prev_sym_valid <= 1'b1; end // [ 0, 1]
                    default: begin
                        pair_invalid_pulse <= 1'b1;
                        pair_invalid_code <= {norm_nibble(t0), norm_nibble(t1)};
                        pair_correct_code <= {norm_nibble(t0), norm_nibble(t1)};
                        if ((ENABLE_PAIR_CORRECT != 0) && pair_correct_allow &&
                            pair_correct_force_expected && pair_correct_expected_valid) begin
                            sym_cand = pair_correct_expected_sym;
                            sym_out_valid <= 1'b1;
                            pair_correct_pulse <= 1'b1;
                            prev_sym <= pair_correct_expected_sym;
                            prev_sym_valid <= 1'b1;
                        end else if ((ENABLE_PAIR_CORRECT != 0) && pair_correct_allow) begin
                            case ({norm_nibble(t0), norm_nibble(t1)})
                                8'hFF: begin
                                    if (ENABLE_LL_HH_CORRECT != 0) begin
                                        // Pair-internal grammar: a pair starting at L must
                                        // be LM. Treat LL as a collapsed LM candidate.
                                        sym_cand = 2'd0;
                                        if (pair_correct_lm_evidence && pair_correct_expected_valid && (pair_correct_expected_sym == sym_cand)) begin
                                            sym_out_valid <= 1'b1;
                                            pair_correct_pulse <= 1'b1;
                                            prev_sym <= 2'd0;
                                            prev_sym_valid <= 1'b1;
                                        end else begin
                                            sym_out_valid <= 1'b0;
                                            pair_correct_reject_pulse <= 1'b1;
                                        end
                                    end else begin
                                        sym_cand = 2'd0;
                                        sym_out_valid <= 1'b0;
                                        pair_correct_reject_pulse <= 1'b1;
                                    end
                                end
                                8'h11: begin
                                    if (ENABLE_LL_HH_CORRECT != 0) begin
                                        // Pair-internal grammar: a pair starting at H must
                                        // be HM. Treat HH as a collapsed HM candidate.
                                        sym_cand = 2'd2;
                                        if (pair_correct_hm_evidence && pair_correct_expected_valid && (pair_correct_expected_sym == sym_cand)) begin
                                            sym_out_valid <= 1'b1;
                                            pair_correct_pulse <= 1'b1;
                                            prev_sym <= 2'd2;
                                            prev_sym_valid <= 1'b1;
                                        end else begin
                                            sym_out_valid <= 1'b0;
                                            pair_correct_reject_pulse <= 1'b1;
                                        end
                                    end else begin
                                        sym_cand = 2'd0;
                                        sym_out_valid <= 1'b0;
                                        pair_correct_reject_pulse <= 1'b1;
                                    end
                                end
                                8'h00: begin
                                    // Both samples collapsed to M. Keep the previous
                                    // direction family when possible, otherwise reject.
                                    if (prev_sym_valid) begin
                                        case (prev_sym)
                                            2'd0: sym_cand = 2'd0; // LM family
                                            2'd1: sym_cand = 2'd1; // ML family
                                            2'd2: sym_cand = 2'd2; // HM family
                                            2'd3: sym_cand = 2'd3; // MH family
                                            default: sym_cand = 2'd0;
                                        endcase
                                        if (1'b0 && pair_correct_expected_valid && (pair_correct_expected_sym == sym_cand)) begin
                                            sym_out_valid <= 1'b1;
                                            pair_correct_pulse <= 1'b1;
                                            prev_sym <= sym_cand;
                                            prev_sym_valid <= 1'b1;
                                        end else begin
                                            sym_out_valid <= 1'b0;
                                            pair_correct_reject_pulse <= 1'b1;
                                        end
                                    end else begin
                                        sym_cand = 2'd0;
                                        sym_out_valid <= 1'b0;
                                        pair_correct_reject_pulse <= 1'b1;
                                    end
                                end
                                default: begin
                                    sym_cand = 2'd0;
                                    sym_out_valid <= 1'b0;
                                    pair_correct_reject_pulse <= 1'b1;
                                end
                            endcase
                        end else begin
                            sym_cand = 2'd0;
                            sym_out_valid <= 1'b0;
                            if (ENABLE_PAIR_CORRECT != 0)
                                pair_correct_reject_pulse <= 1'b1;
                        end
                    end
                endcase
                sym_out       <= sym_cand;
                pair_valid    <= 1'b0;
            end
        end
    end

endmodule

