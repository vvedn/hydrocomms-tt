/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 */

`default_nettype none

module tx_handler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,  // 200 kHz sample-rate tick
    input  wire        tx_start,
    input  wire [7:0]  tx_byte,
    input  wire [15:0] mark_inc,    // phase increment for mark 
    input  wire [15:0] space_inc,   // phase increment for space (bit=0)
    input  wire [15:0] baud_div,    
    output wire [ 7:0] sample_out,  // 8-bit NCO output sample
    output wire        sample_valid,
    output wire        tx_busy,
    output wire        tx_done,
    output wire        symbol_clk   // baud tick, one pulse per symbol period
);

  // Baud rate counter to align the tx with the rx 
  // resets on tx_start and counts sample_tick until baud_div
  reg [15:0] baud_cnt;
  reg        baud_tick;

  wire frame_active;

  always @(posedge clk) begin
    if (!rst_n) begin
      baud_cnt  <= 16'd0;
      baud_tick <= 1'b0;
    end else begin
      baud_tick <= 1'b0;
      if (tx_start && !frame_active) begin
        baud_cnt <= 16'd0;
      end else if (sample_tick) begin
        if (baud_cnt >= baud_div - 16'd1) begin
          baud_cnt  <= 16'd0;
          baud_tick <= 1'b1;
        end else begin
          baud_cnt <= baud_cnt + 16'd1;
        end
      end
    end
  end

  // Frame builder
  wire       data_bit;
  wire       frame_done;

  frame_builder u_frame (
    .clk       (clk),
    .rst_n     (rst_n),
    .tx_start  (tx_start),
    .tx_byte   (tx_byte),
    .baud_tick (baud_tick),
    .bit_out   (data_bit),
    .tx_active (frame_active),
    .tx_done   (frame_done)
  );

  // frequency selection, if its 1 its mark, if its 0 its space freq
  wire [15:0] freq_sel = data_bit ? mark_inc : space_inc;

  nco u_nco (
    .clk        (clk),
    .rst_n      (rst_n),
    .en         (frame_active),
    .phase_inc  (freq_sel),
    .sample_out (sample_out)
  );

  assign tx_busy      = frame_active;
  assign tx_done      = frame_done;
  assign sample_valid = frame_active;
  assign symbol_clk   = baud_tick;



endmodule
