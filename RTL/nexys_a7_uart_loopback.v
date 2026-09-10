`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/11/2026 02:08:09 AM
// Design Name: 
// Module Name: nexys_a7_uart_loopback
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


module nexys_a7_uart_loopback (
    input wire clk,
    input wire reset_n,
    input wire uart_rx,
    output wire uart_tx
);

    // Internal wires for the UART IP core
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_error;
    wire tx_busy;
    wire tx_done;
    wire tx_start;
    //wire [7:0] tx_data;
    
    assign tx_start = rx_valid;

    uart_top #(
        .FPGA_CLK_FREQ(100_000_000),
        .BAUD_RATE(115_200)
    ) uart_inst (
        .clk(clk),
        .reset_n(reset_n),
        .tx_start(tx_start),       
        .tx_data(rx_data), // currently set to loopback
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .rx_valid(rx_valid),
        .rx_data(rx_data),
        .rx_frame_error(rx_frame_error)
    );

endmodule
