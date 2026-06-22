/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * uses bit_slicer and frame_sync to output decoded bytes
 */

`default_nettype none

module fsk_rx (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              sample_valid,
    input  wire signed [7:0] sample_in,
    input  wire signed [7:0] mark_coeff,
    input  wire signed [7:0] space_coeff,
    input  wire        [10:0] block_len,
    output wire         [7:0] rx_byte,
    output wire               rx_valid,
    output wire               rx_locked,
    output wire               rx_crc_ok,
    output wire               bit_decision  // 1=mark>space, for debug
);

  wire [15:0] mark_energy, space_energy;
  wire        mark_done, space_done;

  goertzel u_mark (
    .clk          (clk),
    .rst_n        (rst_n),
    .sample_valid (sample_valid),
    .sample_in    (sample_in),
    .coeff        (mark_coeff),
    .block_len    (block_len),
    .energy       (mark_energy),
    .done         (mark_done)
  );

  goertzel u_space (
    .clk          (clk),
    .rst_n        (rst_n),
    .sample_valid (sample_valid),
    .sample_in    (sample_in),
    .coeff        (space_coeff),
    .block_len    (block_len),
    .energy       (space_energy),
    .done         (space_done)
  );

  wire bit_out, bit_valid;

  bit_slicer u_slicer (
    .clk          (clk),
    .rst_n        (rst_n),
    .mark_energy  (mark_energy),
    .mark_done    (mark_done),
    .space_energy (space_energy),
    .space_done   (space_done),
    .bit_out      (bit_out),
    .bit_valid    (bit_valid)
  );

  frame_sync u_sync (
    .clk       (clk),
    .rst_n     (rst_n),
    .bit_in    (bit_out),
    .bit_valid (bit_valid),
    .rx_byte   (rx_byte),
    .rx_valid  (rx_valid),
    .locked    (rx_locked),
    .crc_ok    (rx_crc_ok)
  );

  assign bit_decision = bit_out;


endmodule
