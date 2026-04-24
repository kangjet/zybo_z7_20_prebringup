`timescale 1ns/1ps

module uart_cmd_frame #(
    parameter integer MAX_LEN = 96
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     rx_valid,
    input  wire [7:0]               rx_byte,
    output reg                      frame_valid,
    output reg [7:0]                frame_cmd,
    output reg [7:0]                frame_len,
    output reg [MAX_LEN*8-1:0]      frame_payload,
    output reg                      auth_format_ok,
    input  wire                     frame_ready
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_LEN  = 2'd1,
        ST_PAY  = 2'd2,
        ST_HOLD = 2'd3;

    reg [1:0] st = ST_IDLE;
    reg [7:0] pay_rem = 8'd0;
    reg [7:0] pay_idx = 8'd0;

    reg [2:0] auth_field = 3'd0;
    reg [6:0] auth_pin_len = 7'd0;
    reg [3:0] auth_num_len = 4'd0;
    reg [5:0] auth_hour = 6'd0;
    reg       auth_ok = 1'b0;
    reg [5:0] hour_candidate;

    integer k;

    function is_hex;
        input [7:0] b;
        begin
            is_hex = ((b >= "0") && (b <= "9")) ||
                     ((b >= "a") && (b <= "f")) ||
                     ((b >= "A") && (b <= "F"));
        end
    endfunction

    function is_digit;
        input [7:0] b;
        begin
            is_digit = (b >= "0") && (b <= "9");
        end
    endfunction

    always @(*) begin
        hour_candidate = (auth_hour * 6'd10) + (rx_byte - "0");
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st             <= ST_IDLE;
            pay_rem        <= 8'd0;
            pay_idx        <= 8'd0;
            frame_valid    <= 1'b0;
            frame_cmd      <= 8'h00;
            frame_len      <= 8'h00;
            frame_payload  <= {(MAX_LEN*8){1'b0}};
            auth_format_ok <= 1'b0;
            auth_field     <= 3'd0;
            auth_pin_len   <= 7'd0;
            auth_num_len   <= 4'd0;
            auth_hour      <= 6'd0;
            auth_ok        <= 1'b0;
        end else begin
            if (frame_valid && frame_ready)
                frame_valid <= 1'b0;

            case (st)
                ST_IDLE: begin
                    if (rx_valid) begin
                        if (rx_byte == 8'h00) begin
                            // ignore sync/noise byte
                        end else if ((rx_byte == 8'h02) || (rx_byte == 8'h03) || (rx_byte == 8'h04) ||
                                     (rx_byte == 8'h10) || (rx_byte == 8'h11) || (rx_byte == 8'h12) ||
                                     (rx_byte == 8'h13) || (rx_byte == 8'h14) || (rx_byte == 8'h15) ||
                                     (rx_byte == 8'h16) || (rx_byte == 8'h17) ||
                                     (rx_byte == 8'h18) || (rx_byte == 8'h19)) begin
                            frame_cmd      <= rx_byte;
                            frame_len      <= 8'h00;
                            frame_payload  <= {(MAX_LEN*8){1'b0}};
                            auth_format_ok <= 1'b0;
                            pay_rem        <= 8'h00;
                            pay_idx        <= 8'h00;
                            auth_field     <= 3'd0;
                            auth_pin_len   <= 7'd0;
                            auth_num_len   <= 4'd0;
                            auth_hour      <= 6'd0;
                            auth_ok        <= 1'b1;
                            st             <= ST_LEN;
                        end else begin
                            frame_cmd      <= rx_byte;
                            frame_len      <= 8'h00;
                            frame_payload  <= {(MAX_LEN*8){1'b0}};
                            auth_format_ok <= 1'b0;
                            frame_valid    <= 1'b1;
                            st             <= ST_HOLD;
                        end
                    end
                end

                ST_LEN: begin
                    if (rx_valid) begin
                        frame_len <= rx_byte;
                        pay_rem   <= rx_byte;
                        pay_idx   <= 8'd0;
                        if (rx_byte > MAX_LEN[7:0]) begin
                            auth_ok        <= 1'b0;
                            auth_format_ok <= 1'b0;
                            frame_valid    <= 1'b1;
                            st             <= ST_HOLD;
                        end else if (rx_byte == 8'h00) begin
                            auth_ok        <= 1'b0;
                            auth_format_ok <= 1'b0;
                            frame_valid    <= 1'b1;
                            st             <= ST_HOLD;
                        end else begin
                            st <= ST_PAY;
                        end
                    end
                end

                ST_PAY: begin
                    if (rx_valid) begin
                        frame_payload[pay_idx*8 +: 8] <= rx_byte;
                        pay_idx <= pay_idx + 8'd1;

                        if (frame_cmd == 8'h02) begin
                            case (auth_field)
                                3'd0: begin
                                    if (rx_byte == ":") begin
                                        if (auth_pin_len != 7'd64)
                                            auth_ok <= 1'b0;
                                        auth_field   <= 3'd1;
                                        auth_num_len <= 4'd0;
                                    end else if (is_hex(rx_byte) && (auth_pin_len < 7'd64)) begin
                                        auth_pin_len <= auth_pin_len + 7'd1;
                                    end else begin
                                        auth_ok <= 1'b0;
                                    end
                                end

                                3'd1: begin
                                    if (rx_byte == ":") begin
                                        if (auth_num_len == 4'd0)
                                            auth_ok <= 1'b0;
                                        auth_field   <= 3'd2;
                                        auth_num_len <= 4'd0;
                                    end else if (is_digit(rx_byte)) begin
                                        auth_num_len <= auth_num_len + 4'd1;
                                    end else begin
                                        auth_ok <= 1'b0;
                                    end
                                end

                                3'd2: begin
                                    if (rx_byte == ":") begin
                                        if (auth_num_len == 4'd0)
                                            auth_ok <= 1'b0;
                                        auth_field   <= 3'd3;
                                        auth_num_len <= 4'd0;
                                        auth_hour    <= 6'd0;
                                    end else if (is_digit(rx_byte)) begin
                                        auth_num_len <= auth_num_len + 4'd1;
                                    end else begin
                                        auth_ok <= 1'b0;
                                    end
                                end

                                3'd3: begin
                                    if (is_digit(rx_byte) && (auth_num_len < 4'd2)) begin
                                        auth_num_len <= auth_num_len + 4'd1;
                                        auth_hour    <= hour_candidate;
                                        if ((pay_rem == 8'd1) && (hour_candidate > 6'd23))
                                            auth_ok <= 1'b0;
                                    end else begin
                                        auth_ok <= 1'b0;
                                    end
                                end

                                default: auth_ok <= 1'b0;
                            endcase
                        end

                        if (pay_rem > 8'd1) begin
                            pay_rem <= pay_rem - 8'd1;
                        end else begin
                            pay_rem <= 8'd0;
                            if (frame_cmd == 8'h02) begin
                                if ((auth_field != 3'd3) || (auth_num_len == 4'd0))
                                    auth_ok <= 1'b0;
                                auth_format_ok <= auth_ok && (auth_field == 3'd3) && (auth_num_len != 4'd0) && !((auth_field == 3'd3) && (pay_rem == 8'd1) && is_digit(rx_byte) && (hour_candidate > 6'd23));
                            end else begin
                                auth_format_ok <= 1'b0;
                            end
                            frame_valid <= 1'b1;
                            st <= ST_HOLD;
                        end
                    end
                end

                ST_HOLD: begin
                    if (frame_ready)
                        st <= ST_IDLE;
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
