/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * 
 */

`default_nettype none

module nco (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] phase_inc,
    output wire [ 7:0] sample_out
);

  reg [15:0] phase_acc;

  always @(posedge clk) begin
    if (!rst_n)
      phase_acc <= 16'd0;
    else if (en)
      phase_acc <= phase_acc + phase_inc;
  end

  wire [1:0] quadrant = phase_acc[15:14];
  wire [4:0] lut_addr_raw = phase_acc[13:9];
  wire [4:0] lut_addr = (quadrant[0]) ? (5'd31 - lut_addr_raw) : lut_addr_raw;

  reg [6:0] lut_val;

  always @(*) begin
    case (lut_addr)
      5'd0:  lut_val = 7'd0;
      5'd1:  lut_val = 7'd6;
      5'd2:  lut_val = 7'd12;
      5'd3:  lut_val = 7'd19;
      5'd4:  lut_val = 7'd25;
      5'd5:  lut_val = 7'd31;
      5'd6:  lut_val = 7'd37;
      5'd7:  lut_val = 7'd43;
      5'd8:  lut_val = 7'd49;
      5'd9:  lut_val = 7'd54;
      5'd10: lut_val = 7'd60;
      5'd11: lut_val = 7'd65;
      5'd12: lut_val = 7'd71;
      5'd13: lut_val = 7'd76;
      5'd14: lut_val = 7'd81;
      5'd15: lut_val = 7'd85;
      5'd16: lut_val = 7'd90;
      5'd17: lut_val = 7'd94;
      5'd18: lut_val = 7'd98;
      5'd19: lut_val = 7'd102;
      5'd20: lut_val = 7'd106;
      5'd21: lut_val = 7'd109;
      5'd22: lut_val = 7'd112;
      5'd23: lut_val = 7'd115;
      5'd24: lut_val = 7'd117;
      5'd25: lut_val = 7'd120;
      5'd26: lut_val = 7'd121;
      5'd27: lut_val = 7'd123;
      5'd28: lut_val = 7'd125;
      5'd29: lut_val = 7'd126;
      5'd30: lut_val = 7'd126;
      5'd31: lut_val = 7'd127;
      default: lut_val = 7'd0;
    endcase
  end

  assign sample_out = (quadrant[1]) ? (8'd128 - {1'b0, lut_val}) : (8'd128 + {1'b0, lut_val});


endmodule
