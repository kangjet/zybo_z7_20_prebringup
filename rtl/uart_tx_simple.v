`timescale 1ns/1ps

module uart_tx_simple #(
    parameter integer CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data_in,
    output reg        tx,
    output reg        busy
);

    localparam [2:0]
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_STOP  = 3'd3;

    reg [2:0]  state   = S_IDLE;
    reg [15:0] clk_cnt = 16'd0;
    reg [2:0]  bit_idx = 3'd0;
    reg [7:0]  shreg   = 8'h00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'h00;
            tx      <= 1'b1;
            busy    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx      <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;

                    if (start) begin
                        shreg <= data_in;
                        busy  <= 1'b1;
                        state <= S_START;
                        tx    <= 1'b0;
                    end
                end

                S_START: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                        tx      <= shreg[0];
                        bit_idx <= 3'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                            tx    <= 1'b1;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                            tx      <= shreg[bit_idx + 3'd1];
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                        tx      <= 1'b1;
                        busy    <= 1'b0;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    tx    <= 1'b1;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
