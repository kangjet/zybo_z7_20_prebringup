`timescale 1ns/1ps
//======================================================
// ILC3 0-code TX core (simple reference)
// - symbol input: 2 bits (0, 1, 2, 3)
// - mapping over 2 samples:
//   0 -> [-1,  0]
//   1 -> [ 0, -1]
//   2 -> [+1,  0]
//   3 -> [ 0, +1]
// - a new symbol is accepted only when sym_in_ready = 1
// - once a symbol is active, amp_out/amp_out_valid stay stable until
//   amp_out_ready consumes each sample
//======================================================
module ilc3_tx_core #(
    parameter SYMB_WIDTH = 2,
    parameter AMP_WIDTH  = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire [SYMB_WIDTH-1:0]       sym_in,
    input  wire                        sym_in_valid,
    output wire                        sym_in_ready,

    output reg  signed [AMP_WIDTH-1:0] amp_out,
    output reg                         amp_out_valid,
    input  wire                        amp_out_ready
);

    reg                  busy;
    reg                  samp_idx;  // 0: first sample, 1: second sample
    reg [SYMB_WIDTH-1:0] cur_sym;

    assign sym_in_ready = ~busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy          <= 1'b0;
            samp_idx      <= 1'b0;
            cur_sym       <= {SYMB_WIDTH{1'b0}};
            amp_out       <= {AMP_WIDTH{1'b0}};
            amp_out_valid <= 1'b0;
        end else begin
            if (!busy) begin
                amp_out_valid <= 1'b0;

                if (sym_in_valid && sym_in_ready) begin
                    cur_sym  <= sym_in;
                    samp_idx <= 1'b0;
                    busy     <= 1'b1;
                end
            end else begin
                amp_out_valid <= 1'b1;

                case (cur_sym)
                    2'd0: amp_out <= (samp_idx == 1'b0) ? -1 : 0;
                    2'd1: amp_out <= (samp_idx == 1'b0) ?  0 : -1;
                    2'd2: amp_out <= (samp_idx == 1'b0) ?  1 : 0;
                    default: amp_out <= (samp_idx == 1'b0) ? 0 : 1;
                endcase

                if (amp_out_ready) begin
                    if (samp_idx == 1'b1) begin
                        busy     <= 1'b0;
                        samp_idx <= 1'b0;
                    end else begin
                        samp_idx <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
