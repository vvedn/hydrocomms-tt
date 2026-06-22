/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 * *
 * Register map:
 *   0x00: status, {5'b0, rx_locked, tx_busy, 1'b1}, read-only
 *   0x01: control, {6'b0, loopback_en, soft_rst}
 *   0x02: mark_inc_hi, mark_inc[15:8]
 *   0x03: mark_inc_lo, mark_inc[7:0]
 *   0x04: space_inc_hi, space_inc[15:8]
 *   0x05: space_inc_lo, space_inc[7:0]
 *   0x06: baud_div_hi, baud_div[15:8]  (symbol period in 200 kHz samples)
 *   0x07: baud_div_lo,baud_div[7:0]   (default 2000 samples = 10 ms = 100 bps)
 *   0x08: block_len_hi, {5'b0, block_len[10:8]}
 *   0x09: block_len_lo, block_len[7:0]
 *   0x0A: tx_data, byte to transmit (write triggers TX), write-only
 *   0x0B: rx_data, last received byte, read-only
 *
 */

`default_nettype none

module regs (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  wr_addr,
    input  wire [7:0]  wr_data,
    input  wire        wr_en,
    input  wire [7:0]  rd_addr,
    output reg  [7:0]  rd_data,
    input  wire        tx_busy,
    input  wire        rx_locked,
    input  wire [7:0]  rx_byte_in,
    output wire [15:0] mark_inc,
    output wire [15:0] space_inc,
    output wire [15:0] baud_div,
    output wire [10:0] block_len,
    output wire        loopback_en,
    output wire        soft_rst,
    output reg  [7:0]  tx_data,
    output reg         tx_trigger
);

  reg [7:0] r_mark_hi, r_mark_lo;
  reg [7:0] r_space_hi, r_space_lo;
  reg [7:0] r_baud_hi, r_baud_lo;
  reg [7:0] r_block_hi, r_block_lo;
  reg [7:0] r_control;

  wire [15:0] baud_div_raw  = {r_baud_hi, r_baud_lo};
  wire [10:0] block_len_raw = {r_block_hi[2:0], r_block_lo};

  assign mark_inc    = {r_mark_hi, r_mark_lo};
  assign space_inc   = {r_space_hi, r_space_lo};
  assign baud_div    = (baud_div_raw < 16'd2) ? 16'd2 : baud_div_raw;
  assign block_len   = (block_len_raw < 11'd2) ? 11'd2 : block_len_raw;
  assign loopback_en = r_control[1];
  assign soft_rst    = r_control[0];

  always @(posedge clk) begin
    if (!rst_n) begin
      r_mark_hi   <= 8'h00;  
      r_mark_lo   <= 8'h3F;   // set to 48 khz
      r_space_hi  <= 8'h00;  
      r_space_lo  <= 8'h47;   // this increment sets 56khz 
      r_baud_hi   <= 8'h07;  
      r_baud_lo   <= 8'hD0;   //2000 samples/symbol = 0x07D0 (100 bps)
      r_block_hi  <= 8'h07;  
      r_block_lo  <= 8'hD0;
      r_control   <= 8'h00;
      tx_data     <= 8'd0;
      tx_trigger  <= 1'b0;
    end else begin
      tx_trigger <= 1'b0;

      if (wr_en) begin
        case (wr_addr)
          8'h01: r_control  <= wr_data;
          8'h02: r_mark_hi  <= wr_data;
          8'h03: r_mark_lo  <= wr_data;
          8'h04: r_space_hi <= wr_data;
          8'h05: r_space_lo <= wr_data;
          8'h06: r_baud_hi  <= wr_data;
          8'h07: r_baud_lo  <= wr_data;
          8'h08: r_block_hi <= wr_data;
          8'h09: r_block_lo <= wr_data;
          8'h0A: begin
            tx_data    <= wr_data;
            tx_trigger <= 1'b1;
          end
          default: ;
        endcase
      end
    end
  end

  always @(*) begin
    case (rd_addr)
      8'h00:   rd_data = {5'b0, rx_locked, tx_busy, 1'b1};
      8'h01:   rd_data = r_control;
      8'h02:   rd_data = r_mark_hi;
      8'h03:   rd_data = r_mark_lo;
      8'h04:   rd_data = r_space_hi;
      8'h05:   rd_data = r_space_lo;
      8'h06:   rd_data = r_baud_hi;
      8'h07:   rd_data = r_baud_lo;
      8'h08:   rd_data = r_block_hi;
      8'h09:   rd_data = r_block_lo;
      8'h0B:   rd_data = rx_byte_in;
      default: rd_data = 8'hFF;
    endcase
  end


endmodule
