/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * CRC-8 calculator 
 * Polynomial: x^8 + x^5 + x^3 + x^2 + x + 1 = 0x2F
 */

`default_nettype none

module crc (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,     // synchronous clear to 0xFF
    input  wire       bit_in,    // input bit
    input  wire       bit_valid, // process this bit
    output wire [7:0] crc_out    // current CRC value
);


  reg [7:0] crc;

  wire feedback = crc[7] ^ bit_in;

  always @(posedge clk) begin
    if (!rst_n || clear) begin
      crc <= 8'hFF;
    end else if (bit_valid) begin
      crc[7] <= crc[6];
      crc[6] <= crc[5];
      crc[5] <= crc[4] ^ feedback;
      crc[4] <= crc[3];
      crc[3] <= crc[2] ^ feedback;
      crc[2] <= crc[1] ^ feedback;
      crc[1] <= crc[0] ^ feedback;
      crc[0] <= feedback;
    end
  end

  assign crc_out = crc;

endmodule
