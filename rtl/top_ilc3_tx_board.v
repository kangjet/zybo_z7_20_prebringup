`timescale 1ns/1ps
//=============================================================
// top_ilc3_tx_board.v  —  ILC3 TX Board Top (Board 1)
// COM3 = UART (JE1, V12)   COM8 = JTAG
// Streams ILC3-encoded amplitude frames over PMOD JD → RX board
// PMOD JD (Bank 34, LVCMOS33): ilc3_amp[3:0], amp_valid,
//                               frame_start, frame_end
// PMOD JC (Bank 34, LVCMOS33): rx_ready_in, pkt_done_in (inputs)
//                               tx_sym_dbg[1:0] (outputs)
// UART log every 1 s: "TX PKT=XXXXXXXX\r\n"
//=============================================================
module top_ilc3_tx_board #(
    parameter integer CLK_FREQ_HZ   = 125_000_000,
    parameter integer UART_BAUD     = 115_200,
    parameter integer INTER_PKT_DLY = 8     // idle clocks between frames
)(
    input  wire       sys_clk,
    input  wire       rst_btn_n,       // BTN0, Zybo: LOW=idle, HIGH=pressed

    // PMOD JD → RX board
    output reg  [3:0] ilc3_amp,        // T14/T15/P14/R14
    output reg        ilc3_amp_valid,  // U14
    output reg        ilc3_frame_start,// U15
    output reg        ilc3_frame_end,  // V17

    // PMOD JC ← RX board
    input  wire       rx_ready_in,     // V15
    input  wire       pkt_done_in,     // W15

    // PMOD JC → debug
    output reg  [1:0] tx_sym_dbg,      // T11/T10

    // UART TX
    output wire       uart_tx,

    // LEDs
    output wire [3:0] led
);

//─────────────────────────────────────────────────────────────
// Derived constants
//─────────────────────────────────────────────────────────────
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD; // 1085 @ 115200
localparam integer SEC_COUNTS   = CLK_FREQ_HZ;              // 1-s log interval

//─────────────────────────────────────────────────────────────
// 1. Reset synchronizer (POR + BTN0 active-HIGH press = reset)
//    Zybo Z7 BTN0: idle=LOW, pressed=HIGH
//─────────────────────────────────────────────────────────────
reg [2:0] rst_sr = 3'b000;
wire      rst_n  = rst_sr[2];
always @(posedge sys_clk) begin
    if (rst_btn_n) rst_sr <= 3'b000;   // BTN0 pressed (HIGH) → reset
    else           rst_sr <= {rst_sr[1:0], 1'b1};
end

//─────────────────────────────────────────────────────────────
// 2. CRC-8 (poly = 0x07, init = 0x00) — combinational
//─────────────────────────────────────────────────────────────
function [7:0] crc8_byte;
    input [7:0] crc;
    input [7:0] din;
    integer     i;
    reg   [7:0] c;
    begin
        c = crc ^ din;
        for (i = 0; i < 8; i = i + 1)
            c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
        crc8_byte = c;
    end
endfunction

//─────────────────────────────────────────────────────────────
// 3. Packet sequence counter
//─────────────────────────────────────────────────────────────
reg [31:0] pkt_seq;  // increments after each frame
reg [31:0] cur_seq;  // latched at frame start

//─────────────────────────────────────────────────────────────
// 4. CRC chain (combinational from cur_seq)
// Frame: [AA][55][08][SEQ3][SEQ2][SEQ1][SEQ0][DE][AD][BE][EF][CRC]
// CRC covers bytes 2-10: LENGTH(0x08) + PKT_SEQ(4B) + DEADBEEF(4B)
//─────────────────────────────────────────────────────────────
wire [7:0] cw0 = crc8_byte(8'h00, 8'h08         );
wire [7:0] cw1 = crc8_byte(cw0,   cur_seq[31:24]);
wire [7:0] cw2 = crc8_byte(cw1,   cur_seq[23:16]);
wire [7:0] cw3 = crc8_byte(cw2,   cur_seq[15: 8]);
wire [7:0] cw4 = crc8_byte(cw3,   cur_seq[ 7: 0]);
wire [7:0] cw5 = crc8_byte(cw4,   8'hDE         );
wire [7:0] cw6 = crc8_byte(cw5,   8'hAD         );
wire [7:0] cw7 = crc8_byte(cw6,   8'hBE         );
wire [7:0] frame_crc = crc8_byte(cw7, 8'hEF);

//─────────────────────────────────────────────────────────────
// 5. Frame byte mux (combinational)
//─────────────────────────────────────────────────────────────
reg  [3:0] byte_cnt;   // 0..11
reg  [1:0] sym_cnt;    // 0..3 within byte

reg [7:0] frame_byte;
always @(*) begin
    case (byte_cnt)
        4'd0:  frame_byte = 8'hAA;
        4'd1:  frame_byte = 8'h55;
        4'd2:  frame_byte = 8'h08;
        4'd3:  frame_byte = cur_seq[31:24];
        4'd4:  frame_byte = cur_seq[23:16];
        4'd5:  frame_byte = cur_seq[15: 8];
        4'd6:  frame_byte = cur_seq[ 7: 0];
        4'd7:  frame_byte = 8'hDE;
        4'd8:  frame_byte = 8'hAD;
        4'd9:  frame_byte = 8'hBE;
        4'd10: frame_byte = 8'hEF;
        default: frame_byte = frame_crc;  // byte 11
    endcase
end

// Symbol extraction MSB-first
reg [1:0] cur_sym_mux;
always @(*) begin
    case (sym_cnt)
        2'd0: cur_sym_mux = frame_byte[7:6];
        2'd1: cur_sym_mux = frame_byte[5:4];
        2'd2: cur_sym_mux = frame_byte[3:2];
        2'd3: cur_sym_mux = frame_byte[1:0];
    endcase
end

//─────────────────────────────────────────────────────────────
// 6. Packet generator FSM
//─────────────────────────────────────────────────────────────
localparam [1:0]
    F_IDLE  = 2'd0,
    F_SYM   = 2'd1,
    F_DELAY = 2'd2;

reg [1:0] fst;
reg [3:0] dly_cnt;
reg       sym_valid;
wire      sym_ready;   // from ilc3_tx_core
reg [4:0] sym_dbg_cnt; // capture first 16 transmitted symbols per frame
reg [31:0] sym_dbg_acc;
reg [31:0] last_syms;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        fst       <= F_IDLE;
        pkt_seq   <= 32'd0;
        cur_seq   <= 32'd0;
        byte_cnt  <= 4'd0;
        sym_cnt   <= 2'd0;
        sym_valid <= 1'b0;
        dly_cnt   <= 4'd0;
        sym_dbg_cnt <= 5'd0;
        sym_dbg_acc <= 32'd0;
        last_syms   <= 32'd0;
    end else begin
        sym_valid <= 1'b0;  // default deassert

        case (fst)
            F_IDLE: begin
                cur_seq  <= pkt_seq;  // latch; CRC auto-follows
                byte_cnt <= 4'd0;
                sym_cnt  <= 2'd0;
                sym_dbg_cnt <= 5'd0;
                sym_dbg_acc <= 32'd0;
                fst      <= F_SYM;
            end

            F_SYM: begin
                sym_valid <= 1'b1;   // stay asserted while in F_SYM
                if (sym_valid && sym_ready) begin
                    if (sym_dbg_cnt < 5'd16) begin
                        sym_dbg_cnt <= sym_dbg_cnt + 5'd1;
                        sym_dbg_acc <= {sym_dbg_acc[29:0], cur_sym_mux};
                    end
                    // mirrors tx_core accept: sym_in_valid && sym_in_ready
                    if (sym_cnt == 2'd3) begin
                        sym_cnt <= 2'd0;
                        if (byte_cnt == 4'd11) begin
                            pkt_seq   <= pkt_seq + 1;
                            dly_cnt   <= 4'd0;
                            fst       <= F_DELAY;
                            sym_valid <= 1'b0;   // deassert only on exit
                            if (sym_dbg_cnt < 5'd16)
                                last_syms <= {sym_dbg_acc[29:0], cur_sym_mux};
                            else
                                last_syms <= sym_dbg_acc;
                        end else begin
                            byte_cnt <= byte_cnt + 4'd1;
                        end
                    end else begin
                        sym_cnt <= sym_cnt + 2'd1;
                    end
                end
            end

            F_DELAY: begin
                if (dly_cnt == INTER_PKT_DLY - 1)
                    fst <= F_IDLE;
                else
                    dly_cnt <= dly_cnt + 4'd1;
            end

            default: fst <= F_IDLE;
        endcase
    end
end

//─────────────────────────────────────────────────────────────
// 7. ILC3 TX Core
//─────────────────────────────────────────────────────────────
wire signed [3:0] amp_out_w;
wire              amp_out_valid_w;

// pmod_rdy drives amp_out_ready — backpressure paces the tx_core
reg pmod_rdy;

ilc3_tx_core #(
    .SYMB_WIDTH(2),
    .AMP_WIDTH (4)
) u_tx_core (
    .clk          (sys_clk),
    .rst_n        (rst_n),
    .sym_in       (cur_sym_mux),
    .sym_in_valid (sym_valid),
    .sym_in_ready (sym_ready),
    .amp_out      (amp_out_w),
    .amp_out_valid(amp_out_valid_w),
    .amp_out_ready(pmod_rdy)
);

//─────────────────────────────────────────────────────────────
// 8. PMOD JD sample-and-hold output
//    Each amp sample held HOLD_N clocks, GAP_N low between samples.
//    Gives RX 2-FF synchronizer reliable setup/hold margin despite
//    independent 125 MHz oscillators on the two boards.
//─────────────────────────────────────────────────────────────
localparam integer HOLD_N = 32;  // 256 ns hold for wider async capture margin
localparam integer GAP_N  = 16;  // 128 ns gap to separate adjacent samples

localparam [1:0] PH_IDLE = 2'd0, PH_HOLD = 2'd1, PH_GAP = 2'd2;

reg [1:0] ph_st;
reg [4:0] ph_cnt;
reg [6:0] amp_cnt;   // 0..95 within current frame
reg [31:0] tx_amp_dbg_acc;
reg [31:0] tx_last_amps;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        ph_st            <= PH_IDLE;
        ph_cnt           <= 5'd0;
        pmod_rdy         <= 1'b1;
        amp_cnt          <= 7'd0;
        ilc3_amp         <= 4'd0;
        ilc3_amp_valid   <= 1'b0;
        ilc3_frame_start <= 1'b0;
        ilc3_frame_end   <= 1'b0;
        tx_sym_dbg       <= 2'b00;
        tx_amp_dbg_acc   <= 32'd0;
        tx_last_amps     <= 32'd0;
    end else begin
        case (ph_st)
            PH_IDLE: begin
                pmod_rdy       <= 1'b1;
                ilc3_amp_valid <= 1'b0;
                if (amp_out_valid_w) begin
                    // Capture sample, start hold period
                    ilc3_amp         <= amp_out_w[3:0];
                    ilc3_amp_valid   <= 1'b1;
                    ilc3_frame_start <= (amp_cnt == 7'd0);
                    ilc3_frame_end   <= (amp_cnt == 7'd95);
                    tx_sym_dbg       <= cur_sym_mux;
                    pmod_rdy         <= 1'b0;   // block next sample
                    ph_cnt           <= HOLD_N - 1;
                    ph_st            <= PH_HOLD;
                    // TX amp dump: first 8 samples per frame
                    if (amp_cnt < 7'd8) begin
                        if (amp_cnt == 7'd0)
                            tx_amp_dbg_acc <= {28'd0, amp_out_w[3:0]};
                        else
                            tx_amp_dbg_acc <= {tx_amp_dbg_acc[27:0], amp_out_w[3:0]};
                        if (amp_cnt == 7'd7)
                            tx_last_amps <= {tx_amp_dbg_acc[27:0], amp_out_w[3:0]};
                    end
                end else begin
                    ilc3_frame_start <= 1'b0;
                    ilc3_frame_end   <= 1'b0;
                end
            end
            PH_HOLD: begin
                if (ph_cnt == 5'd0) begin
                    ilc3_amp_valid   <= 1'b0;
                    ilc3_frame_start <= 1'b0;
                    ilc3_frame_end   <= 1'b0;
                    ph_cnt           <= GAP_N - 1;
                    ph_st            <= PH_GAP;
                end else
                    ph_cnt <= ph_cnt - 1;
            end
            PH_GAP: begin
                if (ph_cnt == 5'd0) begin
                    amp_cnt  <= (amp_cnt == 7'd95) ? 7'd0 : amp_cnt + 7'd1;
                    pmod_rdy <= 1'b1;
                    ph_st    <= PH_IDLE;
                end else
                    ph_cnt <= ph_cnt - 1;
            end
            default: ph_st <= PH_IDLE;
        endcase
    end
end

//─────────────────────────────────────────────────────────────
// 9. 1-second UART logger: "TX PKT=XXXXXXXX S=XXXXXXXX\r\n" (30 bytes)
//─────────────────────────────────────────────────────────────
function [7:0] nibble_ascii;
    input [3:0] n;
    begin
        nibble_ascii = (n < 4'd10) ? (8'h30 + {4'd0, n})
                                   : (8'h37 + {4'd0, n}); // 0x37+10='A'
    end
endfunction

// "TX PKT=XXXXXXXX S=XXXXXXXX A=XXXXXXXX\r\n"  (39 bytes, ptr 0..38)
function [7:0] log_char;
    input [5:0] ptr;
    input [31:0] seq;
    input [31:0] syms;
    input [31:0] amps;
    begin
        case (ptr)
            6'd0:  log_char = 8'h54; // 'T'
            6'd1:  log_char = 8'h58; // 'X'
            6'd2:  log_char = 8'h20; // ' '
            6'd3:  log_char = 8'h50; // 'P'
            6'd4:  log_char = 8'h4B; // 'K'
            6'd5:  log_char = 8'h54; // 'T'
            6'd6:  log_char = 8'h3D; // '='
            6'd7:  log_char = nibble_ascii(seq[31:28]);
            6'd8:  log_char = nibble_ascii(seq[27:24]);
            6'd9:  log_char = nibble_ascii(seq[23:20]);
            6'd10: log_char = nibble_ascii(seq[19:16]);
            6'd11: log_char = nibble_ascii(seq[15:12]);
            6'd12: log_char = nibble_ascii(seq[11: 8]);
            6'd13: log_char = nibble_ascii(seq[ 7: 4]);
            6'd14: log_char = nibble_ascii(seq[ 3: 0]);
            6'd15: log_char = 8'h20; // ' '
            6'd16: log_char = 8'h53; // 'S'
            6'd17: log_char = 8'h3D; // '='
            6'd18: log_char = nibble_ascii(syms[31:28]);
            6'd19: log_char = nibble_ascii(syms[27:24]);
            6'd20: log_char = nibble_ascii(syms[23:20]);
            6'd21: log_char = nibble_ascii(syms[19:16]);
            6'd22: log_char = nibble_ascii(syms[15:12]);
            6'd23: log_char = nibble_ascii(syms[11: 8]);
            6'd24: log_char = nibble_ascii(syms[ 7: 4]);
            6'd25: log_char = nibble_ascii(syms[ 3: 0]);
            6'd26: log_char = 8'h20; // ' '
            6'd27: log_char = 8'h41; // 'A'
            6'd28: log_char = 8'h3D; // '='
            6'd29: log_char = nibble_ascii(amps[31:28]);
            6'd30: log_char = nibble_ascii(amps[27:24]);
            6'd31: log_char = nibble_ascii(amps[23:20]);
            6'd32: log_char = nibble_ascii(amps[19:16]);
            6'd33: log_char = nibble_ascii(amps[15:12]);
            6'd34: log_char = nibble_ascii(amps[11: 8]);
            6'd35: log_char = nibble_ascii(amps[ 7: 4]);
            6'd36: log_char = nibble_ascii(amps[ 3: 0]);
            6'd37: log_char = 8'h0D; // \r
            6'd38: log_char = 8'h0A; // \n
            default: log_char = 8'h00;
        endcase
    end
endfunction

// 1-second timer
reg [26:0] sec_cnt;
reg [31:0] log_seq;
reg [31:0] log_syms;
reg [31:0] log_amps;
reg        log_req;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        sec_cnt  <= 27'd0;
        log_seq  <= 32'd0;
        log_syms <= 32'd0;
        log_amps <= 32'd0;
        log_req  <= 1'b0;
    end else begin
        log_req <= 1'b0;
        if (sec_cnt == SEC_COUNTS - 1) begin
            sec_cnt  <= 27'd0;
            log_seq  <= pkt_seq;
            log_syms <= last_syms;
            log_amps <= tx_last_amps;
            log_req  <= 1'b1;
        end else begin
            sec_cnt <= sec_cnt + 27'd1;
        end
    end
end

// UART print FSM
reg [5:0] log_ptr;
reg       log_active;
reg       uart_start;
reg [7:0] uart_data;
wire      uart_busy;

always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        log_ptr    <= 5'd0;
        log_active <= 1'b0;
        uart_start <= 1'b0;
        uart_data  <= 8'h00;
    end else begin
        uart_start <= 1'b0;

        if (!log_active) begin
            if (log_req) begin
                log_ptr    <= 5'd0;
                log_active <= 1'b1;
            end
        end else begin
            if (!uart_busy && !uart_start) begin
                uart_data  <= log_char(log_ptr, log_seq, log_syms, log_amps);
                uart_start <= 1'b1;
                if (log_ptr == 6'd38)
                    log_active <= 1'b0;
                else
                    log_ptr <= log_ptr + 6'd1;
            end
        end
    end
end

//─────────────────────────────────────────────────────────────
// 10. UART TX instance
//─────────────────────────────────────────────────────────────
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

//─────────────────────────────────────────────────────────────
// 11. LEDs
//─────────────────────────────────────────────────────────────
assign led[0] = rst_n;
assign led[1] = ilc3_amp_valid;
assign led[2] = rx_ready_in;
assign led[3] = pkt_done_in;

endmodule
