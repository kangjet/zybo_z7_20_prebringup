`timescale 1ns/1ps

// uart_rx_simple — 8N1 UART receiver
// Sample at middle of each bit (CLKS_PER_BIT/2 offset after start edge)
module uart_rx_simple #(
    parameter integer CLKS_PER_BIT = 1085  // 125 MHz / 115200 ≈ 1085
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        data_valid,   // 1-cycle pulse when data_out is valid
    output reg [7:0]  data_out
);

    // Synchronise async RX input to avoid metastability
    reg rx_s1, rx_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_s1 <= 1'b1; rx_s2 <= 1'b1; end
        else         begin rx_s1 <= rx;   rx_s2 <= rx_s1; end
    end

    localparam [1:0]
        S_IDLE  = 2'd0,
        S_START = 2'd1,
        S_DATA  = 2'd2,
        S_STOP  = 2'd3;

    reg [1:0]  state   = S_IDLE;
    reg [15:0] clk_cnt = 16'd0;
    reg [2:0]  bit_idx = 3'd0;
    reg [7:0]  shreg   = 8'h00;

    // Recover from broken/incomplete frame without power-cycle.
    localparam integer FRAME_TIMEOUT_CLKS = CLKS_PER_BIT * 14;
    reg [17:0] frame_to_cnt = 18'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            clk_cnt    <= 16'd0;
            bit_idx    <= 3'd0;
            shreg      <= 8'h00;
            data_valid <= 1'b0;
            data_out   <= 8'h00;
            frame_to_cnt<= 18'd0;
        end else begin
            data_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    frame_to_cnt <= 18'd0;
                    if (rx_s2 == 1'b0)          // falling edge → start bit
                        state <= S_START;
                end

                S_START: begin
                    if (frame_to_cnt >= FRAME_TIMEOUT_CLKS) begin
                        state       <= S_IDLE;
                        clk_cnt     <= 16'd0;
                        bit_idx     <= 3'd0;
                        frame_to_cnt<= 18'd0;
                    end else begin
                        frame_to_cnt <= frame_to_cnt + 18'd1;
                        // Wait CLKS_PER_BIT/2 to sample middle of start bit
                        if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        clk_cnt <= 16'd0;
                        if (rx_s2 == 1'b0)      // still low → valid start
                            state <= S_DATA;
                        else
                            state <= S_IDLE;    // glitch, abort
                    end else begin
                            clk_cnt <= clk_cnt + 16'd1;
                        end
                    end
                end

                S_DATA: begin
                    if (frame_to_cnt >= FRAME_TIMEOUT_CLKS) begin
                        state       <= S_IDLE;
                        clk_cnt     <= 16'd0;
                        bit_idx     <= 3'd0;
                        frame_to_cnt<= 18'd0;
                    end else begin
                        frame_to_cnt <= frame_to_cnt + 18'd1;
                        if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        shreg   <= {rx_s2, shreg[7:1]};   // LSB first
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                            clk_cnt <= clk_cnt + 16'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (frame_to_cnt >= FRAME_TIMEOUT_CLKS) begin
                        state       <= S_IDLE;
                        clk_cnt     <= 16'd0;
                        bit_idx     <= 3'd0;
                        frame_to_cnt<= 18'd0;
                    end else begin
                        frame_to_cnt <= frame_to_cnt + 18'd1;
                        if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                        if (rx_s2 == 1'b1) begin    // valid stop bit
                            data_out   <= shreg;
                            data_valid <= 1'b1;
                        end
                    end else begin
                            clk_cnt <= clk_cnt + 16'd1;
                        end
                    end
                end

                default: begin
                    state        <= S_IDLE;
                    frame_to_cnt <= 18'd0;
                end
            endcase
        end
    end

endmodule
