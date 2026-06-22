/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 */

`default_nettype none

module sample_gen #(
    parameter integer DIV = 250
) (
    input  wire clk,
    input  wire rst_n,
    output reg  tick
);

  reg [7:0] cnt;

  always @(posedge clk) begin
    if (!rst_n) begin
      cnt  <= 8'd0;
      tick <= 1'b0;
    end else begin
      tick <= 1'b0;
      if (cnt >= DIV - 1) begin
        cnt  <= 8'd0;
        tick <= 1'b1;
      end else begin
        cnt <= cnt + 8'd1;
      end
    end
  end

endmodule
