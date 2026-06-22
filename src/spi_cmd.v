/*
 * Copyright (c) 2026 Vaishnavi V
 * SPDX-License-Identifier: Apache-2.0
 *
 * SPI command decoder — application protocol layer on top of spi_slave.
 * A transaction is two bytes: an address byte then a data byte.
 *   Write: send {1'b1, addr[6:0]} then the data byte.
 *   Read:  send {1'b0, addr[6:0]} then a dummy byte (its value is ignored,
 *          so reads can never clobber a register or trigger a transmission).
 * Uses the synchronized cs_active from spi_slave (no raw async pin sampling).
 */

`default_nettype none

module spi_cmd (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] rx_data,    // received byte from spi_slave
    input  wire       rx_valid,   // pulses when a byte is received
    input  wire       cs_active,  // synchronized chip-select active level
    output wire [7:0] rd_addr,    // register read address (write flag masked off)
    output reg  [7:0] wr_addr,    // register write address
    output reg  [7:0] wr_data,    // register write data
    output reg        wr_en       // one-cycle write strobe
);

  reg [7:0] spi_addr;
  reg       spi_has_addr;

  assign rd_addr = {1'b0, spi_addr[6:0]};

  always @(posedge clk) begin
    if (!rst_n) begin
      spi_addr     <= 8'd0;
      spi_has_addr <= 1'b0;
      wr_en        <= 1'b0;
      wr_addr      <= 8'd0;
      wr_data      <= 8'd0;
    end else begin
      wr_en <= 1'b0;
      if (rx_valid) begin
        if (!spi_has_addr) begin
          spi_addr     <= rx_data;
          spi_has_addr <= 1'b1;
        end else begin
          if (spi_addr[7]) begin
            wr_addr <= {1'b0, spi_addr[6:0]};
            wr_data <= rx_data;
            wr_en   <= 1'b1;
          end
          spi_has_addr <= 1'b0;
        end
      end
      if (!cs_active)
        spi_has_addr <= 1'b0;
    end
  end


endmodule
