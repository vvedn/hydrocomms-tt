/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * Bit slicer that compares mark and space Goertzel energies to decide each bit
 */

`default_nettype none

module bit_slicer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] mark_energy,
    input  wire        mark_done,
    input  wire [15:0] space_energy,
    input  wire        space_done,
    output reg         bit_out,
    output reg         bit_valid
);

  reg [15:0] mark_latch;
  reg [15:0] space_latch;
  reg        mark_ready;
  reg        space_ready;

  always @(posedge clk) begin
    if (!rst_n) begin
      mark_latch  <= 16'd0;
      space_latch <= 16'd0;
      mark_ready  <= 1'b0;
      space_ready <= 1'b0;
      bit_out     <= 1'b0;
      bit_valid   <= 1'b0;
    end else begin
      bit_valid <= 1'b0;

      if (mark_done) begin
        mark_latch <= mark_energy;
        mark_ready <= 1'b1;
      end

      if (space_done) begin
        space_latch <= space_energy;
        space_ready <= 1'b1;
      end

      if (mark_ready && space_ready) begin
        bit_out     <= (mark_latch >= space_latch) ? 1'b1 : 1'b0;
        bit_valid   <= 1'b1;
        mark_ready  <= 1'b0;
        space_ready <= 1'b0;
      end
    end
  end



endmodule
