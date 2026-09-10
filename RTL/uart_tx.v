`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/31/2026 05:27:09 PM
// Design Name: 
// Module Name: uart_tx
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
module uart_tx #
    (parameter DATA_BITS = 8,
     parameter SAMPLES_PER_BIT = 16, // 16x oversampling
     parameter integer FPGA_CLK_FREQ = 100_000_000,
     parameter integer BAUD_RATE = 115_200
    )
    (
    input wire clk,
    input wire reset_n,
    input wire tx_start,
    input wire [DATA_BITS-1:0] tx_data,
    output wire tx_busy,
    output wire tx_done,
    output wire uart_tx
    );

    localparam integer CLKS_PER_SAMPLE = (FPGA_CLK_FREQ + BAUD_RATE * SAMPLES_PER_BIT / 2) 
                                         / (BAUD_RATE * SAMPLES_PER_BIT);
    
    // Baud rate tick generator
    reg [15:0] clk_div_count = 0;
    wire baud_tick;

    always @(posedge clk) begin
        if (!reset_n) begin
            clk_div_count <= 8'd0;
        end else if (state == TX_IDLE && tx_start) begin
            clk_div_count <= 8'd0; // Reset divider on start to align first bit perfectly
        end else if (clk_div_count == CLKS_PER_SAMPLE - 1) begin
            clk_div_count <= 8'd0;
        end else if (state != TX_IDLE) begin
            clk_div_count <= clk_div_count + 8'd1;
        end
    end

    assign baud_tick = (clk_div_count == CLKS_PER_SAMPLE - 1);

    reg [3:0] sample_count = 0;
    reg [3:0] bit_count = 0; // Increased to 4 bits to safely count 0-8 without overflow
    reg [DATA_BITS-1:0] shift_reg = 0;
    reg uart_tx_reg = 1'b1; // UART line must be HIGH (idle) on reset
    // bits are transfered from LSB to MSB
    reg tx_done_reg = 0;
    
    reg [1:0] state = 0;
    // FSM States
    parameter TX_IDLE = 2'b00; // Idle state
    parameter TX_START = 2'b01; // Start state, send bit 0 to initiate the transfer 
    parameter TX_SENDING_DATA = 2'b11; // Send data bits
    parameter TX_STOP = 2'b10; // Stop state

    // FSM logic for TX
    always @(posedge clk) begin
        if (!reset_n) begin
            state <= TX_IDLE;
            sample_count <= 4'd0;
            bit_count <= 4'd0;
            uart_tx_reg <= 1'b1;
            shift_reg <= {DATA_BITS{1'b0}};
            tx_done_reg <= 1'b0;
        end else begin
            // Clear tx_done pulse after 1 cycle
            if (tx_done_reg) begin
                tx_done_reg <= 1'b0;
            end

            case(state)
            
                TX_IDLE:
                    begin
                        uart_tx_reg <= 1'b1;
                        if (tx_start == 1'b1) begin
                            shift_reg <= tx_data;
                            state <= TX_START;
                        end
                        else begin
                            state <= TX_IDLE;
                        end    
                    end
                    
                TX_START:
                    begin
                        uart_tx_reg <= 1'b0;
                        if (baud_tick) begin
                            if (sample_count == 4'd15) begin
                                sample_count <= 4'd0;
                                state <= TX_SENDING_DATA;
                            end
                            else begin
                                sample_count <= sample_count + 4'd1;
                            end
                        end
                    end
                    
                TX_SENDING_DATA:
                    begin
                        uart_tx_reg <= shift_reg[0];
                        if (baud_tick) begin
                            if (sample_count == 4'd15) begin
                                sample_count <= 4'd0;
                                shift_reg <= {1'b0, shift_reg[DATA_BITS-1:1]};
                                bit_count <= bit_count + 4'd1;
                                if (bit_count == DATA_BITS-1) begin
                                    bit_count <= 4'd0;
                                    state <= TX_STOP;
                                end
                                else begin
                                    state <= TX_SENDING_DATA;
                                end
                            end
                            else begin
                                sample_count <= sample_count + 4'd1;
                            end
                        end
                    end
                    
                TX_STOP:
                    begin
                        uart_tx_reg <= 1'b1;
                        if (baud_tick) begin
                            if (sample_count == 4'd15) begin
                                sample_count <= 4'd0;
                                tx_done_reg <= 1'b1;
                                state <= TX_IDLE;
                            end
                            else begin
                                sample_count <= sample_count + 4'd1;
                            end
                        end
                    end        
            endcase        
        end
    end

    assign uart_tx = uart_tx_reg;
    assign tx_done = tx_done_reg;
    assign tx_busy = (state != TX_IDLE);

endmodule
