`timescale 1ns/1ps
//======================================================
// ILC3 0-code RX core (simple reference)
// - 입력: 연속된 진폭 샘플 (amp_in), 각 심벌당 2샘플
// - 코드북:
//   0 -> [-1,  0]
//   1 -> [ 0, -1]
//   2 -> [+1,  0]
//   3 -> [ 0, +1]
// - 두 샘플을 모아서 4개 코드워드와의 거리(d0~d3)를 계산한 뒤
//   최소 거리의 인덱스를 복원 심벌로 출력
// - 파이프라인 레이턴시:
//   각 심벌은 2샘플로 표현되며, 두 번째 샘플이 들어오는 클럭에서
//   해당 심벌을 바로 디코드하여 sym_out/sym_out_valid로 출력한다.
//   따라서 TX 기준 심벌 인덱스로 보면, 항상 1심벌 지연된 출력이 된다.
//======================================================
module ilc3_rx_core #(
    parameter SYMB_WIDTH = 2,
    parameter AMP_WIDTH  = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        frame_sync,

    // 채널에서 들어오는 진폭 샘플
    input  wire signed [AMP_WIDTH-1:0] amp_in,
    input  wire                        amp_in_valid,
    output wire                        amp_in_ready,

    // 복원된 심벌 출력
    output reg  [SYMB_WIDTH-1:0]       sym_out,
    output reg                         sym_out_valid,
    input  wire                        sym_out_ready
);

    // 이번 버전에서는 항상 ready=1 (백프레셔 없음)
    assign amp_in_ready = 1'b1;

   // 샘플 2개를 모아두는 레지스터
    reg                        sample_phase; // 0: 첫 번째 샘플, 1: 두 번째 샘플
    reg signed [AMP_WIDTH-1:0] s0; 

    // 거리 계산 2-stage 파이프라인
    reg signed [AMP_WIDTH-1:0] t0, t1;
    reg                        pair_valid;
    reg                        dist_valid;
    reg signed [7:0] e0_0, e0_1;
    reg signed [7:0] e1_0, e1_1;
    reg signed [7:0] e2_0, e2_1;
    reg signed [7:0] e3_0, e3_1;
    reg       [15:0] d0, d1, d2, d3;
    reg       [15:0] min_d;
    reg [SYMB_WIDTH-1:0] sym_cand;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_phase  <= 1'b0;
            s0            <= {AMP_WIDTH{1'b0}};
            t0            <= {AMP_WIDTH{1'b0}};
            t1            <= {AMP_WIDTH{1'b0}};
            pair_valid    <= 1'b0;
            dist_valid    <= 1'b0;
            d0            <= 16'd0;
            d1            <= 16'd0;
            d2            <= 16'd0;
            d3            <= 16'd0;
            sym_out       <= {SYMB_WIDTH{1'b0}};
            sym_out_valid <= 1'b0;
        end else begin
            sym_out_valid <= 1'b0;  // 기본값

            if (frame_sync) begin
                sample_phase <= 1'b0;
                pair_valid   <= 1'b0;
                dist_valid   <= 1'b0;
            end
            if (amp_in_valid && amp_in_ready) begin
                if (frame_sync || !sample_phase) begin
                    // 첫 번째 샘플 저장
                    s0           <= amp_in;
                    sample_phase <= 1'b1;
                end else begin
                    // 두 번째 샘플 도착 -> 거리 계산 입력 페어 준비
                    sample_phase <= 1'b0;
                    t0         <= s0;
                    t1         <= amp_in;
                    pair_valid <= 1'b1;
                end
            end

            // stage-1: 거리 계산
            if (pair_valid) begin
                e0_0 = t0 - (-1);
                e0_1 = t1 - 0;
                d0   <= e0_0 * e0_0 + e0_1 * e0_1;

                e1_0 = t0 - 0;
                e1_1 = t1 - (-1);
                d1   <= e1_0 * e1_0 + e1_1 * e1_1;

                e2_0 = t0 - 1;
                e2_1 = t1 - 0;
                d2   <= e2_0 * e2_0 + e2_1 * e2_1;

                e3_0 = t0 - 0;
                e3_1 = t1 - 1;
                d3   <= e3_0 * e3_0 + e3_1 * e3_1;

                pair_valid <= 1'b0;
                dist_valid <= 1'b1;
            end

            // stage-2: 최소 거리 선택 및 출력
            if (dist_valid && sym_out_ready) begin
                min_d    = d0;
                sym_cand = 2'd0;

                if (d1 < min_d) begin
                    min_d    = d1;
                    sym_cand = 2'd1;
                end
                if (d2 < min_d) begin
                    min_d    = d2;
                    sym_cand = 2'd2;
                end
                if (d3 < min_d) begin
                    min_d    = d3;
                    sym_cand = 2'd3;
                end

                sym_out       <= sym_cand;
                sym_out_valid <= 1'b1;
                dist_valid    <= 1'b0;
            end
        end
    end

endmodule
