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
    parameter AMP_WIDTH  = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        frame_sync,

    input  wire signed [AMP_WIDTH-1:0] amp_in,
    input  wire                        amp_in_valid,
    output wire                        amp_in_ready,

    output reg  [SYMB_WIDTH-1:0]       sym_out,
    output reg                         sym_out_valid,
    input  wire                        sym_out_ready,
    output reg  [31:0]                 dbg_pairs
);

    assign amp_in_ready = 1'b1;

    reg                        sample_phase;      // 0: first, 1: second
    reg signed [AMP_WIDTH-1:0] s0;
    reg signed [AMP_WIDTH-1:0] amp_norm;

    reg signed [AMP_WIDTH-1:0] t0, t1;
    reg                        pair_valid;
    reg [SYMB_WIDTH-1:0]      sym_cand;
    reg [3:0]                 dbg_pair_cnt;

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
        end else begin
            sym_out_valid <= 1'b0;

            if (frame_sync) begin
                sample_phase <= 1'b0;
                pair_valid   <= 1'b0;
                dbg_pairs    <= 32'd0;
                dbg_pair_cnt <= 4'd0;
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
                    {4'hF, 4'h0}: begin sym_cand = 2'd0; sym_out_valid <= 1'b1; end // [-1, 0]
                    {4'h0, 4'hF}: begin sym_cand = 2'd1; sym_out_valid <= 1'b1; end // [ 0,-1]
                    {4'h1, 4'h0}: begin sym_cand = 2'd2; sym_out_valid <= 1'b1; end // [ 1, 0]
                    {4'h0, 4'h1}: begin sym_cand = 2'd3; sym_out_valid <= 1'b1; end // [ 0, 1]
                    default:      begin sym_cand = 2'd0; sym_out_valid <= 1'b0; end
                endcase
                sym_out       <= sym_cand;
                pair_valid    <= 1'b0;
            end
        end
    end

endmodule

