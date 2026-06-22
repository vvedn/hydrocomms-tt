/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * SPI 
 * MOSI clocked in on rising SCLK
 * MISO shifted out on falling SCLK.
 * tx_data is latched when CS goes low
 */

`default_nettype none

module spi (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       spi_sclk,
    input  wire       spi_mosi,
    input  wire       spi_cs_n,
    output wire       spi_miso,
    input  wire [7:0] tx_data,    // data to send to master
    output reg  [7:0] rx_data,    // data received from master
    output reg        rx_valid,   // pulses high for one clk when byte received
    output reg        tx_load,    // pulses high when tx_data is latched
    output wire       cs_active   // synchronized chip-select active level
);

  // Synchronize SPI signals to system clock domain
  reg [2:0] sclk_sync;
  reg [2:0] cs_sync;
  reg [1:0] mosi_sync;

  always @(posedge clk) begin
    if (!rst_n) begin
      sclk_sync <= 3'b000;
      cs_sync   <= 3'b111;  // CS is high out of reset bc active low signal
      mosi_sync <= 2'b00;
    end else begin
      sclk_sync <= {sclk_sync[1:0], spi_sclk};
      cs_sync   <= {cs_sync[1:0], spi_cs_n};
      mosi_sync <= {mosi_sync[0], spi_mosi};
    end
  end

  //  CS uses 3 flops like SCLK to prevent metastability and for clean edge detection.
  wire sclk_rise = (sclk_sync[2:1] == 2'b01);
  wire sclk_fall = (sclk_sync[2:1] == 2'b10);
  assign cs_active = !cs_sync[2];
  wire cs_fall   = (cs_sync[2:1] == 2'b10);
  wire mosi_s    = mosi_sync[1];

  reg [7:0] shift_in;
  reg [7:0] shift_out;
  reg [2:0] bit_cnt;

  assign spi_miso = shift_out[7];

  always @(posedge clk) begin
    if (!rst_n) begin
      shift_in  <= 8'd0;
      shift_out <= 8'd0;
      bit_cnt   <= 3'd0;
      rx_data   <= 8'd0;
      rx_valid  <= 1'b0;
      tx_load   <= 1'b0;
    end else begin
      rx_valid <= 1'b0;
      tx_load  <= 1'b0;

      if (!cs_active) begin
        bit_cnt <= 3'd0;
      end else begin
        if (cs_fall) begin
          shift_out <= tx_data;
          tx_load   <= 1'b1;
        end

        if (sclk_rise) begin
          shift_in <= {shift_in[6:0], mosi_s};
          bit_cnt  <= bit_cnt + 3'd1;

          if (bit_cnt == 3'd7) begin
            rx_data  <= {shift_in[6:0], mosi_s};
            rx_valid <= 1'b1;
          end
        end

        if (sclk_fall) begin
          if (bit_cnt == 3'd0 && !cs_fall)
            shift_out <= tx_data;
          else
            shift_out <= {shift_out[6:0], 1'b0};
        end
      end
    end
  end

endmodule
