`timescale 1ns/1ps

// PAM4 analog-node XADC monitor for Zybo Z7-20.
// Input path: PAM4 node -> 27k/10k divider -> JA1/JA7 (VAUX14P/N).
// UART log every 1 s: "XADC RAW=XXX LV=X MIN=XXX MAX=XXX\r\n"

module top_pam4_xadc_rx_board #(
    parameter integer CLK_FREQ_HZ = 125_000_000,
    parameter integer UART_BAUD   = 115_200,
    parameter [11:0]  THRESH_01   = 12'd610,
    parameter [11:0]  THRESH_12   = 12'd1826,
    parameter [11:0]  THRESH_23   = 12'd3045
)(
    input  wire       sys_clk,
    input  wire       rst_btn_n,
    input  wire       vauxp14,
    input  wire       vauxn14,
    output wire       uart_tx,
    output reg  [3:0] led
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;
localparam integer LOG_PERIOD_CLKS = CLK_FREQ_HZ;

reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];

always @(posedge sys_clk) begin
    if (rst_btn_n) begin
        rst_sr <= 3'b000;
    end else begin
        rst_sr <= {rst_sr[1:0], 1'b1};
    end
end

wire [15:0] vauxp_bus;
wire [15:0] vauxn_bus;
assign vauxp_bus = {1'b0, vauxp14, 14'b0};
assign vauxn_bus = {1'b0, vauxn14, 14'b0};

wire        xadc_busy;
wire [4:0]  xadc_channel;
wire [15:0] xadc_do;
wire        xadc_drdy;
wire        xadc_eoc;
wire        xadc_eos;
wire [7:0]  xadc_alarm;
wire        xadc_ot;
wire        xadc_jtagbusy;
wire        xadc_jtaglocked;
wire        xadc_jtagmodified;
wire [4:0]  xadc_muxaddr;

wire [6:0] xadc_daddr = {2'b00, xadc_channel};

XADC #(
    .INIT_40(16'h0000),
    .INIT_41(16'h2EF0),
    .INIT_42(16'h0400),
    .INIT_48(16'h0000),
    .INIT_49(16'h4000),
    .INIT_4A(16'h0000),
    .INIT_4B(16'h0000),
    .INIT_4C(16'h0000),
    .INIT_4D(16'h0000),
    .INIT_4E(16'h0000),
    .INIT_4F(16'h0000),
    .INIT_50(16'h0000),
    .INIT_51(16'h0000),
    .INIT_52(16'h0000),
    .INIT_53(16'h0000),
    .INIT_54(16'h0000),
    .INIT_55(16'h0000),
    .INIT_56(16'h0000),
    .INIT_57(16'h0000),
    .INIT_58(16'h0000),
    .INIT_5C(16'h0000),
    .SIM_DEVICE("ZYNQ"),
    .SIM_MONITOR_FILE("design.txt")
) u_xadc (
    .DADDR      (xadc_daddr),
    .DCLK       (sys_clk),
    .DEN        (xadc_eoc),
    .DI         (16'h0000),
    .DWE        (1'b0),
    .RESET      (~rst_n),
    .VAUXP      (vauxp_bus),
    .VAUXN      (vauxn_bus),
    .VP         (1'b0),
    .VN         (1'b0),
    .ALM        (xadc_alarm),
    .BUSY       (xadc_busy),
    .CHANNEL    (xadc_channel),
    .DO         (xadc_do),
    .DRDY       (xadc_drdy),
    .EOC        (xadc_eoc),
    .EOS        (xadc_eos),
    .JTAGBUSY   (xadc_jtagbusy),
    .JTAGLOCKED (xadc_jtaglocked),
    .JTAGMODIFIED(xadc_jtagmodified),
    .MUXADDR    (xadc_muxaddr),
    .OT         (xadc_ot)
);

reg [11:0] raw12;
reg [11:0] raw_min;
reg [11:0] raw_max;
reg [1:0]  level;
reg [31:0] sample_count;
reg        window_reset;

function [1:0] level_from_raw;
    input [11:0] r;
    begin
        if (r < THRESH_01) begin
            level_from_raw = 2'd0;
        end else if (r < THRESH_12) begin
            level_from_raw = 2'd1;
        end else if (r < THRESH_23) begin
            level_from_raw = 2'd2;
        end else begin
            level_from_raw = 2'd3;
        end
    end
endfunction

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        raw12        <= 12'd0;
        raw_min      <= 12'hFFF;
        raw_max      <= 12'd0;
        level        <= 2'd0;
        sample_count <= 32'd0;
        led          <= 4'b0001;
    end else begin
        if (window_reset) begin
            raw_min      <= 12'hFFF;
            raw_max      <= 12'd0;
        end else if (xadc_drdy && xadc_channel == 5'h1E) begin
            raw12        <= xadc_do[15:4];
            level        <= level_from_raw(xadc_do[15:4]);
            sample_count <= sample_count + 32'd1;

            if (xadc_do[15:4] < raw_min) begin
                raw_min <= xadc_do[15:4];
            end
            if (xadc_do[15:4] > raw_max) begin
                raw_max <= xadc_do[15:4];
            end

            led <= 4'b0001 << level_from_raw(xadc_do[15:4]);
        end
    end
end

reg [31:0] log_timer;
reg        log_pending;
reg        log_clear;
reg [11:0] log_raw;
reg [11:0] log_min;
reg [11:0] log_max;
reg [1:0]  log_level;
reg [31:0] log_samples;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_timer   <= 32'd0;
        log_pending <= 1'b0;
        log_raw     <= 12'd0;
        log_min     <= 12'd0;
        log_max     <= 12'd0;
        log_level   <= 2'd0;
        log_samples <= 32'd0;
        window_reset <= 1'b0;
    end else if (log_clear) begin
        window_reset <= 1'b0;
        log_pending <= 1'b0;
    end else begin
        window_reset <= 1'b0;
        if (!log_pending) begin
        if (log_timer == LOG_PERIOD_CLKS - 1) begin
            log_timer   <= 32'd0;
            log_pending <= 1'b1;
            log_raw     <= raw12;
            log_min     <= raw_min;
            log_max     <= raw_max;
            log_level   <= level;
            log_samples <= sample_count;
            window_reset <= 1'b1;
        end else begin
            log_timer <= log_timer + 32'd1;
        end
        end
    end
end

function [7:0] hex4;
    input [3:0] v;
    begin
        hex4 = (v < 4'd10) ? (8'h30 + v) : (8'h41 + (v - 4'd10));
    end
endfunction

function [7:0] log_char;
    input [5:0]  idx;
    input [11:0] raw;
    input [1:0]  lev;
    input [11:0] mn;
    input [11:0] mx;
    input [31:0] smp;
    begin
        case (idx)
            6'd0:  log_char = "X";
            6'd1:  log_char = "A";
            6'd2:  log_char = "D";
            6'd3:  log_char = "C";
            6'd4:  log_char = " ";
            6'd5:  log_char = "R";
            6'd6:  log_char = "A";
            6'd7:  log_char = "W";
            6'd8:  log_char = "=";
            6'd9:  log_char = hex4(raw[11:8]);
            6'd10: log_char = hex4(raw[7:4]);
            6'd11: log_char = hex4(raw[3:0]);
            6'd12: log_char = " ";
            6'd13: log_char = "L";
            6'd14: log_char = "V";
            6'd15: log_char = "=";
            6'd16: log_char = 8'h30 + {6'd0, lev};
            6'd17: log_char = " ";
            6'd18: log_char = "M";
            6'd19: log_char = "I";
            6'd20: log_char = "N";
            6'd21: log_char = "=";
            6'd22: log_char = hex4(mn[11:8]);
            6'd23: log_char = hex4(mn[7:4]);
            6'd24: log_char = hex4(mn[3:0]);
            6'd25: log_char = " ";
            6'd26: log_char = "M";
            6'd27: log_char = "A";
            6'd28: log_char = "X";
            6'd29: log_char = "=";
            6'd30: log_char = hex4(mx[11:8]);
            6'd31: log_char = hex4(mx[7:4]);
            6'd32: log_char = hex4(mx[3:0]);
            6'd33: log_char = " ";
            6'd34: log_char = "N";
            6'd35: log_char = "=";
            6'd36: log_char = hex4(smp[31:28]);
            6'd37: log_char = hex4(smp[27:24]);
            6'd38: log_char = hex4(smp[23:20]);
            6'd39: log_char = hex4(smp[19:16]);
            6'd40: log_char = hex4(smp[15:12]);
            6'd41: log_char = hex4(smp[11:8]);
            6'd42: log_char = hex4(smp[7:4]);
            6'd43: log_char = hex4(smp[3:0]);
            6'd44: log_char = 8'h0D;
            6'd45: log_char = 8'h0A;
            default: log_char = 8'h20;
        endcase
    end
endfunction

localparam [5:0] LOG_LEN = 6'd46;

reg        uart_start;
reg [7:0]  uart_data;
wire       uart_busy;
reg [5:0]  log_ptr;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_start <= 1'b0;
        log_clear   <= 1'b0;
        uart_data  <= 8'h00;
        log_ptr    <= 6'd0;
    end else begin
        uart_start <= 1'b0;
        log_clear   <= 1'b0;
        if (log_pending && !uart_busy && !uart_start) begin
            uart_data  <= log_char(log_ptr, log_raw, log_level, log_min, log_max, log_samples);
            uart_start <= 1'b1;
            if (log_ptr == LOG_LEN - 1) begin
                log_ptr   <= 6'd0;
                log_clear <= 1'b1;
            end else begin
                log_ptr <= log_ptr + 6'd1;
            end
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

endmodule
