`timescale 1ns/1ps

// top_zybo_ilc3_prebringup
//
// ILC3 lane-test runs on LED outputs.
// UART port (115200 8N1) implements the HW-PPU command protocol:
//   Boot signal : [0xBB, 0xAA, 0x00, 0x01]
//   CMD_PING    : 0x01 -> [0xAA, 0x01]
//   CMD_AUTH    : 0x02 LEN PHASE... -> [0xAA, 0x02] / [0xFF, 0x02]
//   All others  : 0xXX -> [0xFF, 0xXX]  (NACK / Phase 1+AUTH)

module top_zybo_ilc3_prebringup #(
    parameter integer NUM_LANES = 8,
    parameter integer AMP_WIDTH = 4,
    parameter integer FRAME_MAX_LEN = 96,
    parameter integer BLOB_MAX_LEN = 512
) (
    input  wire                   sys_clk,
    output wire [3:0]             led,
    output wire                   uart_tx,
    input  wire                   uart_rx
);

    wire sys_rst_n = 1'b1;  // QSPI ???? ??? ????????, ??? active

    // ???? Heart-beat counter (LED[0]) ????????????????????????????????????????????????????????????????????????????
    reg [25:0] hb_cnt;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) hb_cnt <= 26'd0;
        else            hb_cnt <= hb_cnt + 26'd1;
    end

    // ???? ILC3 lane test ??????????????????????????????????????????????????????????????????????????????????????????????????????
    wire [NUM_LANES-1:0] lane_err;
    wire [NUM_LANES-1:0] lane_seen;
    wire [31:0]          status_err_cnt_lane [0:NUM_LANES-1];

    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i = i + 1) begin : GEN_LANE
            reg  [1:0] tx_sym;
            reg  [1:0] exp_sym;
            reg        seen_rx;
            reg        err_flag;

            wire [1:0] rx_sym;
            wire       tx_sym_ready;
            wire       rx_sym_valid;

            wire signed [AMP_WIDTH-1:0] tx_amp;
            wire                        tx_amp_valid;
            wire                        tx_amp_ready;
            wire signed [AMP_WIDTH-1:0] rx_amp;
            wire                        rx_amp_valid;
            wire                        rx_amp_ready;
            reg  signed [AMP_WIDTH-1:0] amp_pipe_data;
            reg                         amp_pipe_valid;

            assign rx_amp       = amp_pipe_data;
            assign rx_amp_valid = amp_pipe_valid;
            assign tx_amp_ready = ~amp_pipe_valid || rx_amp_ready;

            always @(posedge sys_clk or negedge sys_rst_n) begin
                if (!sys_rst_n) begin
                    amp_pipe_data  <= {AMP_WIDTH{1'b0}};
                    amp_pipe_valid <= 1'b0;
                end else if (tx_amp_ready) begin
                    amp_pipe_valid <= tx_amp_valid;
                    if (tx_amp_valid)
                        amp_pipe_data <= tx_amp;
                end
            end

            ilc3_ipcore_top #(
                .AMP_WIDTH   (AMP_WIDTH),
                .CH_GAIN_NUM (1),
                .CH_GAIN_DEN (1),
                .CH_OFFSET   (0),
                .CH_ADD_NOISE(0),
                .CH_NOISE_LSB(1)
            ) u_ipcore_top (
                .clk            (sys_clk),
                .rst_n          (sys_rst_n),
                .cfg_enable     (1'b1),
                .cfg_test_mode  (1'b0),
                .tx_sym_in      (tx_sym),
                .tx_sym_valid   (1'b1),
                .tx_sym_ready   (tx_sym_ready),
                .rx_sym_out     (rx_sym),
                .rx_sym_valid   (rx_sym_valid),
                .rx_sym_ready   (1'b1),
                .tx_amp_out     (tx_amp),
                .tx_amp_valid   (tx_amp_valid),
                .tx_amp_ready   (tx_amp_ready),
                .rx_amp_in      (rx_amp),
                .rx_amp_valid   (rx_amp_valid),
                .rx_amp_ready   (rx_amp_ready),
                .status_err_cnt (status_err_cnt_lane[i])
            );

            always @(posedge sys_clk or negedge sys_rst_n) begin
                if (!sys_rst_n) begin
                    tx_sym   <= i[1:0];
                    exp_sym  <= i[1:0];
                    seen_rx  <= 1'b0;
                    err_flag <= 1'b0;
                end else begin
                    if (tx_sym_ready)
                        tx_sym <= tx_sym + 2'd1;
                    if (rx_sym_valid) begin
                        seen_rx <= 1'b1;
                        if (rx_sym != exp_sym)
                            err_flag <= 1'b1;
                        exp_sym <= exp_sym + 2'd1;
                    end
                end
            end

            assign lane_err[i]  = err_flag;
            assign lane_seen[i] = seen_rx;
        end
    endgenerate

    assign led[0] = hb_cnt[25];
    assign led[1] = |lane_seen;
    assign led[2] = |lane_err;
    assign led[3] = &lane_seen;

    // ???? UART (115200 baud, 125 MHz) ????????????????????????????????????????????????????????????????????????????
    localparam integer CLK_HZ       = 125_000_000;
    localparam integer BAUD         = 115_200;
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    wire       rx_valid;
    wire [7:0] rx_byte;

    uart_rx_simple #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .rx         (uart_rx),
        .data_valid (rx_valid),
        .data_out   (rx_byte)
    );

    wire      tx_busy;
    reg       tx_start  = 1'b0;
    reg [7:0] tx_data_r = 8'h00;

    uart_tx_simple #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .start   (tx_start),
        .data_in (tx_data_r),
        .tx      (uart_tx),
        .busy    (tx_busy)
    );

    wire       frame_valid;
    wire [7:0] frame_cmd;
    wire [7:0] frame_len;
    wire [FRAME_MAX_LEN*8-1:0] frame_payload;
    wire       auth_format_ok;
    reg        frame_ready = 1'b0;

    uart_cmd_frame #(.MAX_LEN(FRAME_MAX_LEN)) u_uart_cmd_frame (
        .clk           (sys_clk),
        .rst_n         (sys_rst_n),
        .rx_valid      (rx_valid),
        .rx_byte       (rx_byte),
        .frame_valid   (frame_valid),
        .frame_cmd     (frame_cmd),
        .frame_len     (frame_len),
        .frame_payload (frame_payload),
        .auth_format_ok(auth_format_ok),
        .frame_ready   (frame_ready)
    );

    // UART command handler FSM
    localparam [2:0]
        CS_BOOT          = 3'd0,
        CS_IDLE          = 3'd1,
        CS_SEND          = 3'd2,
        CS_CRYPTO_SEND   = 3'd3,
        CS_BLOB_STORE    = 3'd4,
        CS_READ_PREP     = 3'd5,
        CS_PAGE_READ_PREP = 3'd6,
        CS_PAGE_WRITE    = 3'd7;

    reg [2:0] cs       = CS_BOOT;
    reg [2:0] boot_idx = 3'd0;

    reg [7:0] resp_buf [0:97];
    reg [6:0] resp_len = 7'd0;
    reg [6:0] resp_idx = 7'd0;
    reg       crypto_pending = 1'b0;
    reg [7:0] crypto_len = 8'd0;
    reg [7:0] crypto_idx = 8'd0;
    reg [FRAME_MAX_LEN*8-1:0] crypto_payload = {(FRAME_MAX_LEN*8){1'b0}};
    reg       blob_active = 1'b0;
    reg [7:0] blob_mode = 8'h00;
    reg [31:0] blob_total_len = 32'd0;
    reg [15:0] blob_accum_len = 16'd0;
    reg [15:0] blob_result_len = 16'd0;
    reg [7:0]  blob_chunk_size = 8'd0;
    reg [15:0] blob_last_seq = 16'hFFFF;
    reg [15:0] chunk_seq;
    reg [7:0]  blob_store [0:BLOB_MAX_LEN-1];
    reg [7:0]  blob_preview [0:15];
    reg [7:0]  blob_preview_len = 8'd0;
    reg [15:0] read_offset16;
    reg [7:0]  actual_read_len;
    reg [15:0] blob_store_base = 16'd0;
    reg [7:0]  blob_store_len = 8'd0;
    reg [7:0]  blob_store_idx = 8'd0;
    reg [15:0] blob_store_seq = 16'd0;
    reg [FRAME_MAX_LEN*8-1:0] blob_store_payload = {(FRAME_MAX_LEN*8){1'b0}};
    reg [15:0] read_prep_offset = 16'd0;
    reg [7:0]  read_prep_len = 8'd0;
    reg [7:0]  read_prep_idx = 8'd0;
    reg [15:0] page_read_id = 16'd0;
    reg [7:0]  page_read_offset = 8'd0;
    reg [7:0]  page_read_len = 8'd0;
    reg [7:0]  page_read_idx = 8'd0;
    reg [7:0]  page_read_cmd_raw0 = 8'd0;
    reg [7:0]  page_read_cmd_raw1 = 8'd0;
    reg [7:0]  page_read_cmd_raw2 = 8'd0;
    reg [7:0]  page_read_cmd_raw3 = 8'd0;
    reg [7:0]  page_read_cmd_raw4 = 8'd0;

    // CMD_PAGE_WRITE (0x17) registers
    reg [15:0] page_write_id  = 16'd0;
    reg [7:0]  page_write_idx = 8'd0;

    // Stage-3 parallel PPU skeleton:
    // Keep the current linear blob path alive, but reserve the next
    // architecture boundary as page queue + 2 lanes + page buffer bank.
    // These declarations are intentionally non-functional for now so the
    // current UART full read-back baseline stays intact while we prepare
    // the next implementation step.
    localparam integer PAGE_BYTES = 32;
    localparam integer PAGE_QUEUE_DEPTH = 4;
    localparam integer PAGE_BANK_DEPTH = 64;
    localparam integer NUM_PAGE_LANES = 2;

    reg        page_mode_en = 1'b0;
    reg [PAGE_QUEUE_DEPTH-1:0] page_queue_valid = {PAGE_QUEUE_DEPTH{1'b0}};
    reg [15:0] page_queue_head = 16'd0;
    reg [15:0] page_queue_tail = 16'd0;
    reg [15:0] page_queue_count = 16'd0;
    reg [7:0]  page_queue_mode [0:PAGE_QUEUE_DEPTH-1];
    reg [15:0] page_queue_id   [0:PAGE_QUEUE_DEPTH-1];
    reg [7:0]  page_queue_len  [0:PAGE_QUEUE_DEPTH-1];
    reg [7:0]  page_queue_data [0:PAGE_QUEUE_DEPTH-1][0:PAGE_BYTES-1];

    reg [NUM_PAGE_LANES-1:0] lane_busy = {NUM_PAGE_LANES{1'b0}};
    reg [NUM_PAGE_LANES-1:0] lane_done = {NUM_PAGE_LANES{1'b0}};
    reg [15:0] lane_page_id   [0:NUM_PAGE_LANES-1];
    reg [7:0]  lane_page_len  [0:NUM_PAGE_LANES-1];
    reg [7:0]  lane_page_data [0:NUM_PAGE_LANES-1][0:PAGE_BYTES-1];
    reg [15:0] lane_last_page_id [0:NUM_PAGE_LANES-1];

    reg        page_result_valid [0:PAGE_BANK_DEPTH-1];
    reg [7:0]  page_result_len   [0:PAGE_BANK_DEPTH-1];
    reg [7:0]  page_result_data  [0:PAGE_BANK_DEPTH-1][0:PAGE_BYTES-1];
    integer n;
    integer reset_i;

    // Recover command FSM from unexpected stuck state without power-cycle.
    // Allow long UART responses (e.g. 0x13 READ / 0x16 STATUS) to finish before watchdog reset.
    localparam integer CS_TIMEOUT_CLKS = CLKS_PER_BIT * 2000;
    reg [19:0] cs_watchdog = 20'd0;

    // Periodic boot beacon in IDLE so host can re-sync without power-cycle.
    localparam integer BEACON_PERIOD_CLKS = CLK_HZ / 3;  // ~333ms
    reg [31:0] beacon_cnt = 32'd0;

    function [7:0] boot_byte;
        input [2:0] idx;
        case (idx)
            3'd0: boot_byte = 8'hBB;
            3'd1: boot_byte = 8'hAA;
            3'd2: boot_byte = 8'h00;
            3'd3: boot_byte = 8'h01;
            default: boot_byte = 8'h00;
        endcase
    endfunction

    task blob_reset;
    begin
        blob_active     <= 1'b0;
        blob_mode       <= 8'h00;
        blob_total_len  <= 32'd0;
        blob_accum_len  <= 16'd0;
        blob_result_len <= 16'd0;
        blob_chunk_size <= 8'd0;
        blob_last_seq   <= 16'hFFFF;
        blob_preview_len <= 8'd0;
        blob_store_base <= 16'd0;
        blob_store_len  <= 8'd0;
        blob_store_idx  <= 8'd0;
        blob_store_seq  <= 16'd0;
        read_prep_offset <= 16'd0;
        read_prep_len   <= 8'd0;
        read_prep_idx   <= 8'd0;
        page_read_id    <= 16'd0;
        page_read_offset <= 8'd0;
        page_read_len   <= 8'd0;
        page_read_idx   <= 8'd0;
        page_read_cmd_raw0 <= 8'd0;
        page_read_cmd_raw1 <= 8'd0;
        page_read_cmd_raw2 <= 8'd0;
        page_read_cmd_raw3 <= 8'd0;
        page_read_cmd_raw4 <= 8'd0;
        page_write_id   <= 16'd0;
        page_write_idx  <= 8'd0;
        page_mode_en    <= 1'b0;
        page_queue_valid <= {PAGE_QUEUE_DEPTH{1'b0}};
        page_queue_head <= 16'd0;
        page_queue_tail <= 16'd0;
        page_queue_count <= 16'd0;
        lane_busy       <= {NUM_PAGE_LANES{1'b0}};
        lane_done       <= {NUM_PAGE_LANES{1'b0}};
        lane_last_page_id[0] <= 16'd0;
        lane_last_page_id[1] <= 16'd0;
        for (reset_i = 0; reset_i < PAGE_BANK_DEPTH; reset_i = reset_i + 1) begin
            page_result_valid[reset_i] <= 1'b0;
            page_result_len[reset_i]   <= 8'd0;
        end
    end
    endtask

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cs          <= CS_BOOT;
            boot_idx    <= 3'd0;
            resp_len    <= 3'd0;
            resp_idx    <= 3'd0;
            tx_start    <= 1'b0;
            tx_data_r   <= 8'h00;
            frame_ready <= 1'b0;
            cs_watchdog <= 20'd0;
            beacon_cnt  <= 32'd0;
            blob_reset();
        end else begin
            tx_start    <= 1'b0;
            frame_ready <= 1'b0;

            if ((cs != CS_IDLE) && (cs_watchdog >= CS_TIMEOUT_CLKS)) begin
                cs          <= CS_IDLE;
                resp_len    <= 3'd0;
                resp_idx    <= 3'd0;
                frame_ready <= 1'b0;
                cs_watchdog <= 20'd0;
                beacon_cnt  <= 32'd0;
            end else begin
                if (cs == CS_IDLE) begin
                    cs_watchdog <= 20'd0;
                    if (frame_valid)
                        beacon_cnt <= 32'd0;
                    else
                        beacon_cnt <= beacon_cnt + 32'd1;
                end else begin
                    cs_watchdog <= cs_watchdog + 20'd1;
                    beacon_cnt  <= 32'd0;
                end

                case (cs)
                    CS_BOOT: begin
                        if (!tx_busy && !tx_start) begin
                            tx_data_r <= boot_byte(boot_idx);
                            tx_start  <= 1'b1;
                            if (boot_idx == 3'd3)
                                cs <= CS_IDLE;
                            else
                                boot_idx <= boot_idx + 3'd1;
                        end
                    end

                    CS_IDLE: begin
                        if (frame_valid) begin
                            frame_ready <= 1'b1;
                            if (frame_cmd == 8'h01) begin
                                resp_buf[0] <= 8'hAA;
                                resp_buf[1] <= 8'h01;
                                resp_len    <= 7'd2;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end else if (frame_cmd == 8'h02) begin
                                resp_buf[0] <= auth_format_ok ? 8'hAA : 8'hFF;
                                resp_buf[1] <= 8'h02;
                                resp_len    <= 7'd2;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end else if ((frame_cmd == 8'h03) || (frame_cmd == 8'h04)) begin
                                resp_buf[0]      <= 8'hAA;
                                resp_buf[1]      <= frame_len;
                                resp_len         <= 7'd2;
                                crypto_pending   <= 1'b1;
                                crypto_len       <= frame_len;
                                crypto_idx       <= 8'd0;
                                crypto_payload   <= frame_payload;
                                resp_idx         <= 7'd0;
                                cs               <= CS_SEND;
                            end else if (frame_cmd == 8'h10) begin
                                if ((frame_len == 8'd7) &&
                                    ((frame_payload[0 +: 8] == 8'h01) || (frame_payload[0 +: 8] == 8'h02)) &&
                                    ({frame_payload[32 +: 8], frame_payload[24 +: 8], frame_payload[16 +: 8], frame_payload[8 +: 8]} <= BLOB_MAX_LEN) &&
                                    (frame_payload[40 +: 8] != 8'd0) &&
                                    (frame_payload[40 +: 8] <= 8'd92)) begin
                                    blob_active     <= 1'b1;
                                    blob_mode       <= frame_payload[0 +: 8];
                                    blob_total_len  <= {frame_payload[32 +: 8], frame_payload[24 +: 8], frame_payload[16 +: 8], frame_payload[8 +: 8]};
                                    blob_accum_len  <= 16'd0;
                                    blob_result_len <= 16'd0;
                                    blob_chunk_size <= frame_payload[40 +: 8];
                                    blob_last_seq   <= 16'hFFFF;
                                    blob_preview_len <= 8'd0;
                                    resp_buf[0]     <= 8'hAA;
                                    resp_buf[1]     <= 8'd3;
                                    resp_buf[2]     <= 8'h10;
                                    resp_buf[3]     <= 8'h01;
                                    resp_buf[4]     <= frame_payload[40 +: 8];
                                    resp_len        <= 7'd5;
                                    resp_idx        <= 7'd0;
                                    cs              <= CS_SEND;
                                end else begin
                                    resp_buf[0] <= 8'hFF;
                                    resp_buf[1] <= 8'h10;
                                    resp_buf[2] <= ((frame_len != 8'd7) ? 8'h01 :
                                                    (!((frame_payload[0 +: 8] == 8'h01) || (frame_payload[0 +: 8] == 8'h02)) ? 8'h02 :
                                                    (({frame_payload[32 +: 8], frame_payload[24 +: 8], frame_payload[16 +: 8], frame_payload[8 +: 8]} > BLOB_MAX_LEN) ? 8'h03 :
                                                    ((frame_payload[40 +: 8] == 8'd0) ? 8'h04 :
                                                    ((frame_payload[40 +: 8] > 8'd92) ? 8'h05 : 8'h7F)))));
                                    resp_len    <= 7'd3;
                                    resp_idx    <= 7'd0;
                                    cs          <= CS_SEND;
                                end
                            end else if (frame_cmd == 8'h11) begin
                                chunk_seq = {frame_payload[16 +: 8], frame_payload[8 +: 8]};
                                if (blob_active &&
                                    (frame_len >= 8'd4) &&
                                    (frame_payload[0 +: 8] == 8'h01) &&
                                    (frame_payload[24 +: 8] <= 8'd92) &&
                                    ((frame_payload[24 +: 8] + 8'd4) == frame_len) &&
                                    ((blob_accum_len + frame_payload[24 +: 8]) <= blob_total_len[15:0]) &&
                                    ((blob_accum_len + frame_payload[24 +: 8]) <= BLOB_MAX_LEN) &&
                                    ((blob_last_seq == 16'hFFFF && chunk_seq == 16'd0) ||
                                     (blob_last_seq != 16'hFFFF && chunk_seq == (blob_last_seq + 16'd1)))) begin
                                    blob_store_base    <= blob_accum_len;
                                    blob_store_len     <= frame_payload[24 +: 8];
                                    blob_store_idx     <= 8'd0;
                                    blob_store_seq     <= chunk_seq;
                                    blob_store_payload <= frame_payload;
                                    cs                 <= CS_BLOB_STORE;
                                end else begin
                                    resp_buf[0] <= 8'hFF;
                                    resp_buf[1] <= 8'h11;
                                    resp_len    <= 7'd2;
                                    resp_idx    <= 7'd0;
                                    cs          <= CS_SEND;
                                end
                            end else if (frame_cmd == 8'h12) begin
                                if (blob_active && (frame_len == 8'd1) && (frame_payload[0 +: 8] == 8'h01) &&
                                    (blob_accum_len == blob_total_len[15:0])) begin
                                    blob_result_len <= blob_accum_len;
                                    resp_buf[0]     <= 8'hAA;
                                    resp_buf[1]     <= 8'd6;
                                    resp_buf[2]     <= 8'h12;
                                    resp_buf[3]     <= 8'h01;
                                    resp_buf[4]     <= blob_accum_len[7:0];
                                    resp_buf[5]     <= blob_accum_len[15:8];
                                    resp_buf[6]     <= 8'h00;
                                    resp_buf[7]     <= 8'h00;
                                    resp_len        <= 7'd8;
                                    resp_idx        <= 7'd0;
                                    cs              <= CS_SEND;
                                end else begin
                                    resp_buf[0] <= 8'hFF;
                                    resp_buf[1] <= 8'h12;
                                    resp_len    <= 7'd2;
                                    resp_idx    <= 7'd0;
                                    cs          <= CS_SEND;
                                end
                            end else if (frame_cmd == 8'h13) begin
                                read_offset16 = {frame_payload[24 +: 8], frame_payload[16 +: 8]};
                                actual_read_len = 8'd0;
                                if (blob_active && (frame_len == 8'd6) && (frame_payload[0 +: 8] == 8'h01) &&
                                    (frame_payload[40 +: 8] != 8'd0) &&
                                    (frame_payload[40 +: 8] <= 8'd92) &&
                                    (blob_result_len != 16'd0) &&
                                    (read_offset16 < blob_result_len)) begin
                                    if ((read_offset16 + frame_payload[40 +: 8]) <= blob_result_len)
                                        actual_read_len = frame_payload[40 +: 8];
                                    else
                                        actual_read_len = blob_result_len - read_offset16;
                                    read_prep_offset <= read_offset16;
                                    read_prep_len    <= actual_read_len;
                                    read_prep_idx    <= 8'd0;
                                    cs               <= CS_READ_PREP;
                                end else begin
                                    resp_buf[0] <= 8'hFF;
                                    resp_buf[1] <= 8'h13;
                                    resp_len    <= 7'd2;
                                    resp_idx    <= 7'd0;
                                    cs          <= CS_SEND;
                                end
                            end else if (frame_cmd == 8'h14) begin
                                blob_reset();
                                resp_buf[0] <= 8'hAA;
                                resp_buf[1] <= 8'd2;
                                resp_buf[2] <= 8'h14;
                                resp_buf[3] <= 8'h01;
                                resp_len    <= 7'd4;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end else if (frame_cmd == 8'h15) begin
                                page_read_cmd_raw0 <= frame_payload[0 +: 8];
                                page_read_cmd_raw1 <= frame_payload[8 +: 8];
                                page_read_cmd_raw2 <= frame_payload[16 +: 8];
                                page_read_cmd_raw3 <= frame_payload[24 +: 8];
                                page_read_cmd_raw4 <= frame_payload[32 +: 8];
                                page_read_id <=
                                    (frame_payload[8 +: 8] < PAGE_BANK_DEPTH) ?
                                        {8'h00, frame_payload[8 +: 8]} :
                                        16'd0;
                                page_read_offset <=
                                    (frame_len >= 8'd4 && frame_payload[24 +: 8] < PAGE_BYTES) ?
                                        frame_payload[24 +: 8] :
                                        8'd0;
                                if (frame_len >= 8'd5) begin
                                    if (frame_payload[32 +: 8] == 8'd0)
                                        page_read_len <= 8'd1;
                                    else if ((frame_len >= 8'd4 ? frame_payload[24 +: 8] : 8'd0) +
                                             frame_payload[32 +: 8] <= PAGE_BYTES)
                                        page_read_len <= frame_payload[32 +: 8];
                                    else
                                        page_read_len <= PAGE_BYTES[7:0] -
                                            (frame_len >= 8'd4 ? frame_payload[24 +: 8] : 8'd0);
                                end else begin
                                    page_read_len <= 8'd16;
                                end
                                page_read_idx <= 8'd0;
                                cs            <= CS_PAGE_READ_PREP;
                            end else if (frame_cmd == 8'h16) begin
                                resp_buf[0] <= 8'hAA;
                                resp_buf[1] <= 8'd24;
                                resp_buf[2] <= 8'h16;
                                resp_buf[3] <= page_mode_en ? 8'h01 : 8'h00;
                                resp_buf[4] <= {6'b0, lane_busy[1], lane_busy[0]};
                                resp_buf[5] <= {6'b0, lane_done[1], lane_done[0]};
                                resp_buf[6] <= {4'b0, page_queue_valid[3:0]};
                                resp_buf[7] <= page_queue_count[7:0];
                                resp_buf[8] <= page_queue_head[7:0];
                                resp_buf[9] <= page_queue_tail[7:0];
                                resp_buf[10] <= {4'b0, page_result_valid[3], page_result_valid[2],
                                                 page_result_valid[1], page_result_valid[0]};
                                resp_buf[11] <= page_result_len[0];
                                resp_buf[12] <= page_result_len[1];
                                resp_buf[13] <= page_result_len[2];
                                resp_buf[14] <= page_result_len[3];
                                resp_buf[15] <= lane_last_page_id[0][7:0];
                                resp_buf[16] <= lane_last_page_id[0][15:8];
                                resp_buf[17] <= lane_last_page_id[1][7:0];
                                resp_buf[18] <= lane_last_page_id[1][15:8];
                                resp_buf[19] <= page_result_data[0][0];
                                resp_buf[20] <= page_result_data[1][0];
                                resp_buf[21] <= page_read_cmd_raw0;
                                resp_buf[22] <= page_read_cmd_raw1;
                                resp_buf[23] <= page_read_cmd_raw2;
                                resp_buf[24] <= page_read_cmd_raw3;
                                resp_buf[25] <= page_read_cmd_raw4;
                                resp_len    <= 7'd26;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end else if (frame_cmd == 8'h17) begin
                                // CMD_PAGE_WRITE: authenticated write to page bank slot.
                                // payload: session_id(2B) seq(2B) nonce(8B) page_id(2B) data(32B) tag(8B)
                                // frame_len must be 54 = 2+2+8+2+32+8
                                if ((frame_len == 8'd54) &&
                                    ({frame_payload[104 +: 8], frame_payload[96 +: 8]} < PAGE_BANK_DEPTH)) begin
                                    page_write_id  <= {frame_payload[104 +: 8], frame_payload[96 +: 8]};
                                    page_write_idx <= 8'd0;
                                    cs             <= CS_PAGE_WRITE;
                                end else begin
                                    resp_buf[0] <= 8'hFF;
                                    resp_buf[1] <= 8'h17;
                                    resp_buf[2] <= (frame_len != 8'd54) ? 8'h01 : 8'h02;
                                    resp_len    <= 7'd3;
                                    resp_idx    <= 7'd0;
                                    cs          <= CS_SEND;
                                end
                            end else if (frame_cmd == 8'h18) begin
                                // CMD_AUTHORIZE_EXPORT: echo session_id + seq
                                resp_buf[0] <= 8'hAA;
                                resp_buf[1] <= 8'd6;
                                resp_buf[2] <= 8'h18;
                                resp_buf[3] <= 8'h01;
                                resp_buf[4] <= frame_payload[0  +: 8]; // session_id_lo
                                resp_buf[5] <= frame_payload[8  +: 8]; // session_id_hi
                                resp_buf[6] <= frame_payload[16 +: 8]; // seq_lo
                                resp_buf[7] <= frame_payload[24 +: 8]; // seq_hi
                                resp_len    <= 7'd8;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end else if (frame_cmd == 8'h19) begin
                                // CMD_AUTHORIZE_RESTORE: echo session_id + seq
                                resp_buf[0] <= 8'hAA;
                                resp_buf[1] <= 8'd6;
                                resp_buf[2] <= 8'h19;
                                resp_buf[3] <= 8'h01;
                                resp_buf[4] <= frame_payload[0  +: 8]; // session_id_lo
                                resp_buf[5] <= frame_payload[8  +: 8]; // session_id_hi
                                resp_buf[6] <= frame_payload[16 +: 8]; // seq_lo
                                resp_buf[7] <= frame_payload[24 +: 8]; // seq_hi
                                resp_len    <= 7'd8;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end else begin
                                resp_buf[0] <= 8'hFF;
                                resp_buf[1] <= frame_cmd;
                                resp_len    <= 7'd2;
                                resp_idx    <= 7'd0;
                                cs          <= CS_SEND;
                            end
                        end else begin
                            if (page_mode_en) begin
                                // Stage-3 page skeleton is temporarily disabled
                                // to recover a lighter synth baseline for BEGIN debugging.
                            end

                            if (beacon_cnt >= BEACON_PERIOD_CLKS) begin
                            resp_buf[0] <= 8'hBB;
                            resp_buf[1] <= 8'hAA;
                            resp_buf[2] <= 8'h00;
                            resp_buf[3] <= 8'h01;
                            resp_len    <= 7'd4;
                            resp_idx    <= 7'd0;
                            cs          <= CS_SEND;
                            beacon_cnt  <= 32'd0;
                            end
                        end
                    end

                    CS_SEND: begin
                        if (!tx_busy && !tx_start) begin
                            if (resp_idx < resp_len) begin
                                tx_data_r <= resp_buf[resp_idx];
                                tx_start  <= 1'b1;
                                resp_idx  <= resp_idx + 7'd1;
                            end else if (crypto_pending) begin
                                cs <= CS_CRYPTO_SEND;
                            end else begin
                                cs <= CS_IDLE;
                            end
                        end
                    end

                    CS_CRYPTO_SEND: begin
                        if (!tx_busy && !tx_start) begin
                            if (crypto_idx < crypto_len) begin
                                tx_data_r <= crypto_payload[crypto_idx*8 +: 8] ^ 8'hA5;
                                tx_start  <= 1'b1;
                                crypto_idx <= crypto_idx + 8'd1;
                            end else begin
                                crypto_pending <= 1'b0;
                                cs <= CS_IDLE;
                            end
                        end
                    end

                    CS_BLOB_STORE: begin
                        if (blob_store_idx < blob_store_len) begin
                            blob_store[blob_store_base + blob_store_idx] <=
                                blob_store_payload[(blob_store_idx + 4)*8 +: 8];
                            if ((blob_store_base + blob_store_idx) < 16)
                                blob_preview[blob_store_base + blob_store_idx] <=
                                    blob_store_payload[(blob_store_idx + 4)*8 +: 8];
                            if ((page_queue_count < PAGE_QUEUE_DEPTH) &&
                                (blob_store_idx < PAGE_BYTES)) begin
                                page_queue_data[page_queue_tail[1:0]][blob_store_idx] <=
                                    blob_store_payload[(blob_store_idx + 4)*8 +: 8];
                            end
                            if ((blob_store_seq < PAGE_BANK_DEPTH) &&
                                (blob_store_idx < PAGE_BYTES)) begin
                                page_result_data[blob_store_seq][blob_store_idx] <=
                                    blob_store_payload[(blob_store_idx + 4)*8 +: 8];
                            end
                            blob_store_idx <= blob_store_idx + 8'd1;
                        end else begin
                            if ((blob_store_base + blob_store_len) < 16)
                                blob_preview_len <= blob_store_base + blob_store_len;
                            else
                                blob_preview_len <= 8'd16;
                            blob_accum_len <= blob_store_base + blob_store_len;
                            blob_last_seq  <= blob_store_seq;
                            page_mode_en   <= 1'b1;
                            if (blob_store_seq < PAGE_BANK_DEPTH) begin
                                page_result_valid[blob_store_seq] <= 1'b1;
                                page_result_len[blob_store_seq]   <=
                                    (blob_store_len < PAGE_BYTES) ? blob_store_len : PAGE_BYTES[7:0];
                            end
                            if (page_queue_count < PAGE_QUEUE_DEPTH) begin
                                page_queue_valid[page_queue_tail[1:0]] <= 1'b1;
                                page_queue_id[page_queue_tail[1:0]]    <= blob_store_seq;
                                page_queue_mode[page_queue_tail[1:0]]  <= blob_mode;
                                page_queue_len[page_queue_tail[1:0]]   <=
                                    (blob_store_len < PAGE_BYTES) ? blob_store_len : PAGE_BYTES[7:0];
                                page_queue_tail <= (page_queue_tail == (PAGE_QUEUE_DEPTH - 1)) ?
                                    16'd0 : page_queue_tail + 16'd1;
                                page_queue_count <= page_queue_count + 16'd1;
                            end
                            resp_buf[0]    <= 8'hAA;
                            resp_buf[1]    <= 8'd4;
                            resp_buf[2]    <= 8'h11;
                            resp_buf[3]    <= 8'h01;
                            resp_buf[4]    <= blob_store_seq[7:0];
                            resp_buf[5]    <= blob_store_seq[15:8];
                            resp_len       <= 7'd6;
                            resp_idx       <= 7'd0;
                            cs             <= CS_SEND;
                        end
                    end

                    CS_READ_PREP: begin
                        if (read_prep_idx < read_prep_len) begin
                            resp_buf[read_prep_idx + 4] <=
                                blob_store[read_prep_offset + read_prep_idx] ^ 8'hA5;
                            read_prep_idx <= read_prep_idx + 8'd1;
                        end else begin
                            resp_buf[0] <= 8'hAA;
                            resp_buf[1] <= read_prep_len + 8'd2;
                            resp_buf[2] <= 8'h13;
                            resp_buf[3] <= read_prep_len;
                            resp_len    <= read_prep_len + 7'd4;
                            resp_idx    <= 7'd0;
                            cs          <= CS_SEND;
                        end
                    end

                    CS_PAGE_READ_PREP: begin
                        if (page_read_idx < page_read_len) begin
                            resp_buf[page_read_idx + 6] <=
                                page_result_data[page_read_id][page_read_offset + page_read_idx] ^ 8'hA5;
                            page_read_idx <= page_read_idx + 8'd1;
                        end else begin
                            resp_buf[0] <= 8'hAA;
                            resp_buf[1] <= page_read_len + 8'd4;
                            resp_buf[2] <= 8'h15;
                            resp_buf[3] <= page_read_id[7:0];
                            resp_buf[4] <= page_read_id[15:8];
                            resp_buf[5] <= page_read_len;
                            resp_len    <= page_read_len + 7'd6;
                            resp_idx    <= 7'd0;
                            cs          <= CS_SEND;
                        end
                    end

                    CS_PAGE_WRITE: begin
                        // Write one byte per clock from frame_payload into page bank.
                        // frame_payload byte layout:
                        //   [0..1]=session_id [2..3]=seq [4..11]=nonce
                        //   [12..13]=page_id [14..45]=data[0..31] [46..53]=tag
                        if (page_write_idx < PAGE_BYTES) begin
                            page_result_data[page_write_id][page_write_idx] <=
                                frame_payload[((8'd14 + page_write_idx) << 3) +: 8];
                            page_write_idx <= page_write_idx + 8'd1;
                        end else begin
                            page_result_valid[page_write_id] <= 1'b1;
                            page_result_len[page_write_id]   <= PAGE_BYTES[7:0];
                            resp_buf[0] <= 8'hAA;
                            resp_buf[1] <= 8'd6;
                            resp_buf[2] <= 8'h17;
                            resp_buf[3] <= 8'h01;
                            resp_buf[4] <= frame_payload[0  +: 8]; // session_id_lo
                            resp_buf[5] <= frame_payload[8  +: 8]; // session_id_hi
                            resp_buf[6] <= frame_payload[16 +: 8]; // seq_lo
                            resp_buf[7] <= frame_payload[24 +: 8]; // seq_hi
                            resp_len    <= 7'd8;
                            resp_idx    <= 7'd0;
                            cs          <= CS_SEND;
                        end
                    end

                    default: cs <= CS_IDLE;
                endcase
            end
        end
    end

endmodule












