/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * Frame syncrhonizer used for alignment and to detect packet start (0xAA)
 */

`default_nettype none

module frame_sync (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       bit_in,
    input  wire       bit_valid,
    output reg  [7:0] rx_byte,
    output reg        rx_valid,
    output reg        locked,    // high when sync pattern has been detected
    output reg        crc_ok     // high when last received frame had valid CRC
);

  localparam [7:0] PREAMBLE = 8'hAA;
  localparam [7:0] SYNC     = 8'h7E;

  localparam S_HUNT    = 2'd0;  // sliding 16-bit match on preamble+sync
  localparam S_PAYLOAD = 2'd1;  // sync found, collecting payload bits
  localparam S_CRC     = 2'd2;  // collecting CRC byte

  reg [1:0]  state;
  reg [15:0] shift_reg;  
  reg [7:0]  payload_reg;
  reg [7:0]  crc_reg;
  reg [2:0]  bit_cnt;

  // CRC computed over payload bits as they arrive
  wire [7:0] crc_computed;
  reg        crc_clear;
  wire       crc_feed_valid = (state == S_PAYLOAD) && bit_valid;

  crc u_crc (
    .clk       (clk),
    .rst_n     (rst_n),
    .clear     (crc_clear),
    .bit_in    (bit_in),
    .bit_valid (crc_feed_valid),
    .crc_out   (crc_computed)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      state       <= S_HUNT;
      shift_reg   <= 16'd0;
      payload_reg <= 8'd0;
      crc_reg     <= 8'd0;
      bit_cnt     <= 3'd0;
      rx_byte     <= 8'd0;
      rx_valid    <= 1'b0;
      locked      <= 1'b0;
      crc_ok      <= 1'b0;
      crc_clear   <= 1'b0;
    end else begin
      rx_valid  <= 1'b0;
      crc_clear <= 1'b0;

      if (bit_valid) begin
        shift_reg <= {shift_reg[14:0], bit_in};

        case (state)
          S_HUNT: begin
            locked <= 1'b0;
            // Match the full 16-bit preamble+sync pattern in one sliding window
            if ({shift_reg[14:0], bit_in} == {PREAMBLE, SYNC}) begin
              state     <= S_PAYLOAD;
              bit_cnt   <= 3'd0;
              locked    <= 1'b1;
              crc_clear <= 1'b1;  // reset CRC for incoming payload
            end
          end

          S_PAYLOAD: begin
            payload_reg <= {payload_reg[6:0], bit_in};
            bit_cnt     <= bit_cnt + 3'd1;

            if (bit_cnt == 3'd7) begin
              // Payload complete, now collect CRC byte
              bit_cnt <= 3'd0;
              state   <= S_CRC;
            end
          end

          S_CRC: begin
            crc_reg <= {crc_reg[6:0], bit_in};
            bit_cnt <= bit_cnt + 3'd1;

            if (bit_cnt == 3'd7) begin
              // CRC byte received, compare with computed
              rx_byte  <= payload_reg;
              rx_valid <= 1'b1;
              crc_ok   <= (crc_computed == {crc_reg[6:0], bit_in});
              locked   <= 1'b0;
              state    <= S_HUNT;
            end
          end

          default: state <= S_HUNT;
        endcase
      end
    end
  end



endmodule
