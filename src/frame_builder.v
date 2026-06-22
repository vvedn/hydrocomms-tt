/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * Frame: [preamble 0xAA] [sync 0x7E] [payload byte] [CRC-8]
 */

`default_nettype none

module frame_builder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tx_start,     // pulse to begin frame transmission
    input  wire [7:0]  tx_byte,      // payload byte to transmit
    input  wire        baud_tick,    // one pulse per symbol period
    output reg         bit_out,      // current bit to modulate
    output reg         tx_active,    // high while frame is being sent
    output reg         tx_done       // pulses when frame completes
);

  localparam [7:0] PREAMBLE = 8'hAA;
  localparam [7:0] SYNC     = 8'h7E;

  localparam S_IDLE     = 3'd0;
  localparam S_PREAMBLE = 3'd1;
  localparam S_SYNC     = 3'd2;
  localparam S_PAYLOAD  = 3'd3;
  localparam S_CRC_LOAD = 3'd4;  
  localparam S_CRC      = 3'd5;
  localparam S_FLUSH    = 3'd6;  

  reg [2:0] state;
  reg [7:0] shift_reg;
  reg [2:0] bit_idx;
  reg [7:0] payload_latch;

  // CRC scomputation over payload bits
  wire [7:0] crc_val;
  reg        crc_clear;
  wire       crc_bit_valid = (state == S_PAYLOAD) && baud_tick;

  crc u_crc (
    .clk       (clk),
    .rst_n     (rst_n),
    .clear     (crc_clear),
    .bit_in    (shift_reg[7 - bit_idx]),
    .bit_valid (crc_bit_valid),
    .crc_out   (crc_val)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      state         <= S_IDLE;
      shift_reg     <= 8'd0;
      bit_idx       <= 3'd0;
      bit_out       <= 1'b0;
      tx_active     <= 1'b0;
      tx_done       <= 1'b0;
      payload_latch <= 8'd0;
      crc_clear     <= 1'b0;
    end else begin
      tx_done   <= 1'b0;
      crc_clear <= 1'b0;

      case (state)
        S_IDLE: begin
          tx_active <= 1'b0;
          if (tx_start) begin
            payload_latch <= tx_byte;
            shift_reg     <= PREAMBLE;
            bit_idx       <= 3'd1;
            bit_out       <= PREAMBLE[7];
            tx_active     <= 1'b1;
            crc_clear     <= 1'b1;  // reset CRC for new frame
            state         <= S_PREAMBLE;
          end
        end

        S_PREAMBLE: begin
          if (baud_tick) begin
            bit_out <= shift_reg[7 - bit_idx];
            if (bit_idx == 3'd7) begin
              shift_reg <= SYNC;
              bit_idx   <= 3'd0;
              state     <= S_SYNC;
            end else begin
              bit_idx <= bit_idx + 3'd1;
            end
          end
        end

        S_SYNC: begin
          if (baud_tick) begin
            bit_out <= shift_reg[7 - bit_idx];
            if (bit_idx == 3'd7) begin
              shift_reg <= payload_latch;
              bit_idx   <= 3'd0;
              state     <= S_PAYLOAD;
            end else begin
              bit_idx <= bit_idx + 3'd1;
            end
          end
        end

        S_PAYLOAD: begin
          if (baud_tick) begin
            bit_out <= shift_reg[7 - bit_idx];
            if (bit_idx == 3'd7) begin
              bit_idx <= 3'd0;
              state   <= S_CRC_LOAD;
            end else begin
              bit_idx <= bit_idx + 3'd1;
            end
          end
        end

        S_CRC_LOAD: begin
          // CRC register has now settled with all 8 payload bits
          shift_reg <= crc_val;
          state     <= S_CRC;
        end

        S_CRC: begin
          if (baud_tick) begin
            bit_out <= shift_reg[7 - bit_idx];
            if (bit_idx == 3'd7) begin
              state <= S_FLUSH;
            end else begin
              bit_idx <= bit_idx + 3'd1;
            end
          end
        end

        S_FLUSH: begin
          // Last bit is sent  now, wait for its symbol period to elapse
          if (baud_tick) begin
            tx_done <= 1'b1;
            state   <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end



endmodule
