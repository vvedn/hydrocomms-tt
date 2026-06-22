/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_hydrocomms (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out[0] = spi_miso;         // SPI data out
  assign uo_out[1] = rx_valid;         // rx_byte_valid — pulse when byte decoded
  assign uo_out[2] = rx_crc_ok;        // crc_ok — high if last frame CRC matched
  assign uo_out[3] = rx_locked;        // packet_detected — sync word found
  assign uo_out[4] = tx_busy;          // tx_active — high during transmission
  assign uo_out[5] = symbol_clk;       // symbol_clock — baud rate tick
  assign uo_out[6] = bit_decision;     // tone0_energy_gt_tone1 — Goertzel comparison
  assign uo_out[7] = sample_tick;      // 200 kHz sample clock

  assign uio_out = tx_sample;
  assign uio_oe  = {8{tx_busy & ~loopback_en}};

  wire       spi_sclk  = ui_in[0];
  wire       spi_mosi  = ui_in[1];
  wire       spi_cs_n  = ui_in[2];
  wire       spi_miso;

  // Reset combines external reset with soft reset register
  wire       soft_rst;
  wire       rst_int = rst_n & ~soft_rst;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], uio_in[0], tx_sample_valid, 1'b0};

  // SPI 
  wire [7:0] spi_rx_data;
  wire       spi_rx_valid;
  wire       spi_cs_active;
  wire [7:0] spi_tx_data;

  spi u_spi (
    .clk       (clk),
    .rst_n     (rst_int),
    .spi_sclk  (spi_sclk),
    .spi_mosi  (spi_mosi),
    .spi_cs_n  (spi_cs_n),
    .spi_miso  (spi_miso),
    .tx_data   (spi_tx_data),
    .rx_data   (spi_rx_data),
    .rx_valid  (spi_rx_valid),
    .tx_load   ()
  );

   // SPI command decoder 
  wire [7:0] reg_rd_addr;
  wire [7:0] reg_wr_addr;
  wire [7:0] reg_wr_data;
  wire       reg_wr_en;

  spi_cmd u_cmd (
    .clk       (clk),
    .rst_n     (rst_int),
    .rx_data   (spi_rx_data),
    .rx_valid  (spi_rx_valid),
    .cs_active (spi_cs_active),
    .rd_addr   (reg_rd_addr),
    .wr_addr   (reg_wr_addr),
    .wr_data   (reg_wr_data),
    .wr_en     (reg_wr_en)
  );


  // Configuration regs
  wire [15:0] mark_inc, space_inc;
  wire [15:0] baud_div;
  wire [10:0] block_len;
  wire        loopback_en;
  wire [7:0]  reg_tx_data;
  wire        reg_tx_trigger;
  wire        tx_busy;
  wire [7:0]  rx_byte;
  wire        rx_valid;
  wire        rx_locked;

  regs u_regs (
    .clk         (clk),
    .rst_n       (rst_int),
    .wr_addr     (reg_wr_addr),
    .wr_data     (reg_wr_data),
    .wr_en       (reg_wr_en),
    .rd_addr     (reg_rd_addr),
    .rd_data     (spi_tx_data),
    .tx_busy     (tx_busy),
    .rx_locked   (rx_locked),
    .rx_byte_in  (rx_byte),
    .mark_inc    (mark_inc),
    .space_inc   (space_inc),
    .baud_div    (baud_div),
    .block_len   (block_len),
    .loopback_en (loopback_en),
    .soft_rst    (soft_rst),
    .tx_data     (reg_tx_data),
    .tx_trigger  (reg_tx_trigger)
  );

  // Clk divider for baud rate and receive symbol timing
  wire sample_tick;

  sample_gen #(.DIV(250)) u_sample_gen (
    .clk   (clk),
    .rst_n (rst_int),
    .tick  (sample_tick)
  );

  // Transmitter module 
  wire       tx_start = reg_tx_trigger;
  wire [7:0] tx_byte  = reg_tx_data;
  wire [7:0] tx_sample;
  wire       tx_sample_valid;
  wire       tx_done;
  wire       symbol_clk;

  tx_handler u_tx_handler (
    .clk          (clk),
    .rst_n        (rst_int),
    .sample_tick  (sample_tick),
    .tx_start     (tx_start),
    .tx_byte      (tx_byte),
    .mark_inc     (mark_inc),
    .space_inc    (space_inc),
    .baud_div     (baud_div),
    .sample_out   (tx_sample),
    .sample_valid (tx_sample_valid),
    .tx_busy      (tx_busy),
    .tx_done      (tx_done),
    .symbol_clk   (symbol_clk)
  );  


  // Receiver module and fix for loopback testing: 
  // adds a lb_tail after TX ends so the
  // final Goertzel block completes and the last bits flush
  // TODO add a fix to make frame self contained 
  reg [2:0] lb_tail;

  always @(posedge clk) begin
    if (!rst_int)
      lb_tail <= 3'd0;
    else if (tx_busy)
      lb_tail <= 3'd7;
    else if (sample_tick && lb_tail != 3'd0)
      lb_tail <= lb_tail - 3'd1;
  end

  // Convert unsigned 8-bit to signed 8-bit (subtract 64)
  wire signed [7:0] rx_sample_in = loopback_en ?
    $signed({1'b0, tx_sample[7:1]}) - 8'sd64 :
    $signed({1'b0, uio_in[7:1]}) - 8'sd64;
  wire rx_sample_valid = loopback_en ?
    (sample_tick & (tx_busy | (lb_tail != 3'd0))) : sample_tick;

  wire       rx_crc_ok;
  wire       bit_decision;

  // coeff = round(2*cos(2*pi*k/N) * 64)
  // mark (48 kHz): k=480, coeff = 2*cos(2*pi*480/2000) = 0.1253 gives you 8
  // space (54 kHz): k=540, coeff = 2*cos(2*pi*540/2000) = -0.2487 gives you -16
  wire signed [7:0] mark_coeff  = 8'sd8;
  wire signed [7:0] space_coeff = -8'sd16;

  rx u_rx (
    .clk          (clk),
    .rst_n        (rst_int),
    .sample_valid (rx_sample_valid),
    .sample_in    (rx_sample_in),
    .mark_coeff   (mark_coeff),
    .space_coeff  (space_coeff),
    .block_len    (block_len),
    .rx_byte      (rx_byte),
    .rx_valid     (rx_valid),
    .rx_locked    (rx_locked),
    .rx_crc_ok    (rx_crc_ok),
    .bit_decision (bit_decision)
  );


endmodule
