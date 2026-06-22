/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *

 * coeff = round(2*cos(2*pi*k/N) * 2^6), where k = round(f_target * N / f_sample).
 */

`default_nettype none

module goertzel (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire signed  [7:0] sample_in,
    input  wire signed  [7:0] coeff,       
    input  wire         [10:0] block_len,
    output reg          [15:0] energy,
    output reg                 done
);

  reg signed [19:0] s1, s2;
  reg [10:0] count;

  wire signed [27:0] prod  = coeff * s1;           
  wire signed [19:0] prod_scaled = prod[25:6];      // shift by 6 to get back no decimal
  wire signed [19:0] s0_next = prod_scaled - s2 + {{12{sample_in[7]}}, sample_in};

  wire [19:0] abs_s1 = s1[19] ? (~s1 + 20'd1) : s1;
  wire [19:0] abs_s2 = s2[19] ? (~s2 + 20'd1) : s2;

  always @(posedge clk) begin
    if (!rst_n) begin
      s1     <= 20'd0;
      s2     <= 20'd0;
      count  <= 11'd0;
      energy <= 16'd0;
      done   <= 1'b0;
    end else begin
      done <= 1'b0;

      if (sample_valid) begin
        if (count == 11'd0) begin
          s1    <= {{12{sample_in[7]}}, sample_in};
          s2    <= 20'd0;
          count <= 11'd1;
        end else if (count >= block_len) begin
          energy <= {4'd0, abs_s1[19:8]} + {4'd0, abs_s2[19:8]};
          done   <= 1'b1;
          s1    <= {{12{sample_in[7]}}, sample_in};
          s2    <= 20'd0;
          count <= 11'd1;
        end else begin
          s2    <= s1;
          s1    <= s0_next;
          count <= count + 11'd1;
        end
      end
    end
  end



endmodule
