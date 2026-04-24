`timescale 1ns/1ps
//======================================================
// ILC3 IPCore Top v0.1
// - 내부 구성:
//     * ilc3_tx_core : 2bit 심볼 → AMP_WIDTH 진폭 코드
//     * ilc3_rx_core : AMP_WIDTH 진폭 코드 → 2bit 심볼 복원
// - 외부 인터페이스:
//   (1) 디지털 상위 계층 (컨트롤러 / 패킷 레이어)
//       * tx_sym_in[1:0]   : 송신 심볼 입력
//       * tx_sym_valid     : 송신 심볼 유효 플래그
//       * tx_sym_ready     : IPCore가 새 심볼을 받을 준비 상태
//       * rx_sym_out[1:0]  : 수신 심볼 출력
//       * rx_sym_valid     : 수신 심볼 유효 플래그
//       * rx_sym_ready     : 상위가 수신 심볼을 읽을 준비 상태
//
//   (2) 아날로그 PHY 쪽 (DAC/ADC에 직접 연결되는 쪽)
//       * tx_amp_out[AMP_WIDTH-1:0] : TX 진폭 코드 (DAC 입력)
//       * tx_amp_valid              : TX 진폭 코드 유효
//       * tx_amp_ready              : DAC가 샘플을 받을 준비 상태
//       * rx_amp_in[AMP_WIDTH-1:0]  : RX 진폭 코드 (ADC 출력)
//       * rx_amp_valid              : RX 진폭 코드 유효
//       * rx_amp_ready              : IPCore가 샘플을 받을 준비 상태
//
// - 주의: 실제 포트 이름/폭은 ilc3_tx_core / ilc3_rx_core 정의와
//        정확히 맞춰야 함. 현재 버전은 기존 tb에서 사용한
//        포트 구조를 기준으로 작성.
//======================================================
module ilc3_ipcore_top #(
    // 진폭 비트 폭 (DAC/ADC 코드 폭)
    parameter integer AMP_WIDTH    = 4,
    // 채널/시뮬레이션 관련 파라미터 (IPCore 자체에서는 사용하지 않고,
    // 상위/x8-top이나 TB에서 일관된 인터페이스를 유지하기 위한 용도)
    parameter integer CH_GAIN_NUM  = 1,
    parameter integer CH_GAIN_DEN  = 1,
    parameter integer CH_OFFSET    = 0,
    parameter integer CH_ADD_NOISE = 0,
    parameter integer CH_NOISE_LSB = 1
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     cfg_enable,
    input  wire                     cfg_test_mode,

    //==================================================
    // (1) 상위 디지털 계층 인터페이스 (심볼 도메인)
    //==================================================
    // TX 방향: 상위 → IPCore
    input  wire [1:0]               tx_sym_in,
    input  wire                     tx_sym_valid,
    output wire                     tx_sym_ready,

    // RX 방향: IPCore → 상위
    output wire [1:0]               rx_sym_out,
    output wire                     rx_sym_valid,
    input  wire                     rx_sym_ready,

    //==================================================
    // (2) PHY 인터페이스 (DAC/ADC와 연결되는 진폭 도메인)
    //==================================================
    // TX 쪽: IPCore → DAC
    output wire signed [AMP_WIDTH-1:0] tx_amp_out,
    output wire                        tx_amp_valid,
    input  wire                        tx_amp_ready,

    // RX 쪽: ADC → IPCore
    input  wire signed [AMP_WIDTH-1:0] rx_amp_in,
    input  wire                        rx_amp_valid,
    output wire                        rx_amp_ready,

    output wire [31:0]              status_err_cnt
);

    //==================================================
    // 내부 제어 신호 (v0.2)
    //  - cfg_enable = 0일 때는 TX/RX 심볼 핸드셰이크를 정지
    //  - cfg_test_mode는 향후 내부 패턴 발생기/에러 카운터용으로 예약
    //==================================================
    wire [1:0] tx_sym_mux;
    wire       tx_sym_valid_mux;
    wire       rx_sym_ready_mux;
    wire signed [AMP_WIDTH-1:0] rx_amp_to_core;
    reg  [7:0] noise_lfsr;

    reg  [1:0] tx_sym_fifo [0:15];
    reg  [3:0] fifo_wr_ptr;
    reg  [3:0] fifo_rd_ptr;
    reg  [4:0] fifo_count;
    reg  [31:0] err_cnt;
    wire       tx_push;
    wire       rx_pop;
    wire       fifo_empty;
    wire       fifo_full;
    wire       push_ok;
    wire       pop_ok;
    wire signed [31:0] noise_step_32;
    wire signed [31:0] rx_amp_noisy_32;

    // 현재 v0.2에서는 상위에서 들어온 심볼을 그대로 사용
    assign tx_sym_mux       = tx_sym_in;
    assign tx_sym_valid_mux = cfg_enable ? tx_sym_valid : 1'b0;
    assign rx_sym_ready_mux = cfg_enable ? rx_sym_ready : 1'b0;

    assign tx_push    = tx_sym_valid_mux && tx_sym_ready;
    assign rx_pop     = rx_sym_valid && rx_sym_ready_mux;
    assign fifo_empty = (fifo_count == 5'd0);
    assign fifo_full  = (fifo_count == 5'd16);
    assign push_ok    = tx_push && (!fifo_full || rx_pop);
    assign pop_ok     = rx_pop && !fifo_empty;

    assign noise_step_32  = noise_lfsr[7] ? -$signed(CH_NOISE_LSB) : $signed(CH_NOISE_LSB);
    assign rx_amp_noisy_32 = $signed(rx_amp_in)
                           + ((CH_ADD_NOISE != 0) ? noise_step_32 : 32'sd0)
                           + $signed(CH_OFFSET);
    assign rx_amp_to_core = rx_amp_noisy_32[AMP_WIDTH-1:0];
    assign status_err_cnt = err_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            noise_lfsr <= 8'h1;
            fifo_wr_ptr <= 4'd0;
            fifo_rd_ptr <= 4'd0;
            fifo_count  <= 5'd0;
            err_cnt     <= 32'd0;
        end else begin
            if (rx_amp_valid && rx_amp_ready) begin
                noise_lfsr <= {noise_lfsr[6:0], noise_lfsr[7] ^ noise_lfsr[5] ^ noise_lfsr[4] ^ noise_lfsr[3]};
            end

            if (push_ok) begin
                tx_sym_fifo[fifo_wr_ptr] <= tx_sym_mux;
                fifo_wr_ptr <= fifo_wr_ptr + 4'd1;
            end

            if (pop_ok) begin
                if (rx_sym_out != tx_sym_fifo[fifo_rd_ptr]) begin
                    err_cnt <= err_cnt + 32'd1;
                end
                fifo_rd_ptr <= fifo_rd_ptr + 4'd1;
            end

            case ({push_ok, pop_ok})
                2'b10: fifo_count <= fifo_count + 5'd1;
                2'b01: fifo_count <= fifo_count - 5'd1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    //==================================================
    // TX Core 인스턴스
    //  - 심볼 입력 → 진폭 코드 출력
    //==================================================
    ilc3_tx_core #(
        .AMP_WIDTH(AMP_WIDTH)
    ) u_tx_core (
        .clk          (clk),
        .rst_n        (rst_n),

        // 상위 심볼 입력
        .sym_in       (tx_sym_mux),
        .sym_in_valid (tx_sym_valid_mux),
        .sym_in_ready (tx_sym_ready),

        // PHY로 나가는 진폭 코드
        .amp_out      (tx_amp_out),
        .amp_out_valid(tx_amp_valid),
        .amp_out_ready(tx_amp_ready)
    );

    //==================================================
    // RX Core 인스턴스
    //  - 진폭 코드 입력 → 심볼 복원
    //==================================================
    ilc3_rx_core #(
        .AMP_WIDTH(AMP_WIDTH)
    ) u_rx_core (
        .clk          (clk),
        .rst_n        (rst_n),

        // PHY에서 들어오는 진폭 코드
        .amp_in       (rx_amp_to_core),
        .amp_in_valid (rx_amp_valid),
        .amp_in_ready (rx_amp_ready),

        // 상위로 내보내는 복원 심볼
        .sym_out      (rx_sym_out),
        .sym_out_valid(rx_sym_valid),
        .sym_out_ready(rx_sym_ready_mux)
    );

endmodule
