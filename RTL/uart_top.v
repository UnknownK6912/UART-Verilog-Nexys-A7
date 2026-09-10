`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/31/2026 06:31:41 PM
// Design Name: 
// Module Name: uart_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_top #(
    parameter integer FPGA_CLK_FREQ = 100_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer SAMPLES_PER_BIT = 16, // 16x oversampling
    parameter integer DATA_BITS = 8
) (
    input wire clk,
    input wire reset_n,
 
    // TX interface
    input wire tx_start,
    input wire [DATA_BITS-1:0] tx_data,
    output wire tx_busy,
    output wire tx_done,
    output wire uart_tx,
 
    // RX interface
    input  wire uart_rx,
    output wire rx_valid,
    output wire [DATA_BITS-1:0] rx_data,
    output wire rx_frame_error
);
 
    uart_tx #
    (.DATA_BITS(DATA_BITS),
     .SAMPLES_PER_BIT(SAMPLES_PER_BIT), // 16x oversampling
     .FPGA_CLK_FREQ(FPGA_CLK_FREQ),
     .BAUD_RATE(BAUD_RATE)
    ) uart_tx_instance
    (
    .clk(clk),
    .reset_n(reset_n),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .tx_done(tx_done),
    .uart_tx(uart_tx)
    );
 
 
    uart_rx #
    (.DATA_BITS(DATA_BITS),
     .SAMPLES_PER_BIT(SAMPLES_PER_BIT), // 16x oversampling
     .FPGA_CLK_FREQ(FPGA_CLK_FREQ),
     .BAUD_RATE(BAUD_RATE)
    ) uart_rx_instance
    (
    .clk(clk),
    .reset_n(reset_n),
    .uart_rx(uart_rx),
    .rx_valid(rx_valid),
    .rx_data(rx_data),
    .rx_frame_error(rx_frame_error)
    );
 
endmodule
