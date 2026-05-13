`timescale 1ns/1ps
//=============================================================
// top_pam4_static_tx_board.v
//
// Static PAM4 code TX for analog/noise-path debug.
//
// PMOD JD:
//   JD1/JD2 = pam4_code[0]/pam4_code[1]
//   JD7     = pam4_valid, held LOW
//   JD8     = pam4_sync, held LOW
//
// This bitstream is intended for bench checks where the Wavegen
// injection path must be observed without PAM4 data transitions.
//=============================================================
module top_pam4_static_tx_board #(
    parameter integer STATIC_CODE = 0
) (
    input  wire       sys_clk,
    input  wire       rst_btn_n,

    output wire [1:0] pam4_code,
    output wire       pam4_valid,
    output wire       pam4_sync,

    output wire       uart_tx,
    output wire [3:0] led
);

wire [1:0] static_code_safe =
    (STATIC_CODE == 0) ? 2'b00 :
    (STATIC_CODE == 1) ? 2'b01 :
    (STATIC_CODE == 2) ? 2'b10 :
                         2'b11;

assign pam4_code  = static_code_safe;
assign pam4_valid = 1'b0;
assign pam4_sync  = 1'b0;

assign uart_tx = 1'b1;

assign led[0] = rst_btn_n;
assign led[1] = static_code_safe[0];
assign led[2] = static_code_safe[1];
assign led[3] = sys_clk;

endmodule
