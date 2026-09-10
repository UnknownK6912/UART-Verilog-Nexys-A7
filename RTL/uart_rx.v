`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/31/2026 05:27:09 PM
// Design Name: 
// Module Name: uart_rx
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
module uart_rx # 
    (parameter DATA_BITS = 8,
     parameter SAMPLES_PER_BIT = 16, // 16x oversampling
     parameter integer FPGA_CLK_FREQ = 100_000_000,
     parameter integer BAUD_RATE = 115_200
    )
    (
    input wire clk,
    input wire reset_n,
    input wire uart_rx,
    output wire rx_valid,
    output wire [DATA_BITS-1:0] rx_data,
    output wire rx_frame_error
    );
    
    // Calculate clocks per sample tick
    localparam integer CLKS_PER_SAMPLE = (FPGA_CLK_FREQ + BAUD_RATE * SAMPLES_PER_BIT / 2) 
                                         / (BAUD_RATE * SAMPLES_PER_BIT);
    
    // Sampling points for majority voting
    localparam integer MID_SAMPLE = SAMPLES_PER_BIT / 2;
    localparam integer SAMPLE_A = MID_SAMPLE - 1;
    localparam integer SAMPLE_B = MID_SAMPLE;
    localparam integer SAMPLE_C = MID_SAMPLE + 1;
    
    // Baud rate tick generator
    // Reg width increased to accomodate lower baud rates if you want to change parameters
    reg [15:0] clk_div_count = 0;
    wire baud_tick;

    always @(posedge clk) begin
        if (!reset_n) begin
            clk_div_count <= 16'd0;
        end else if (clk_div_count == CLKS_PER_SAMPLE - 1) begin
            clk_div_count <= 16'd0;
        end else begin
            clk_div_count <= clk_div_count + 16'd1;
        end
    end

    assign baud_tick = (clk_div_count == CLKS_PER_SAMPLE - 1);

    // Synchronizer for asynchronous uart_rx input
    reg rx_sync_1 = 1'b1;
    reg rx_sync_2 = 1'b1;
    reg rx_prev = 1'b1;
    wire rx_falling_edge;

    always @(posedge clk) begin
        if (!reset_n) begin
            rx_sync_1 <= 1'b1;
            rx_sync_2 <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_sync_1 <= uart_rx;
            rx_sync_2 <= rx_sync_1;
            rx_prev <= rx_sync_2;
        end
    end

    assign rx_falling_edge = (rx_prev == 1'b1) && (rx_sync_2 == 1'b0);

    // Registers for 3 sample majority voting
    reg rx_sample_a = 0;
    reg rx_sample_b = 0;

    // Majority vote logic (sum of 3 bits,  and the vote is >= 2 then set voted_bit to 1)
    wire [1:0] vote_sum = {1'b0, rx_sample_a} + {1'b0, rx_sample_b} + {1'b0, rx_sync_2};
    wire voted_bit = (vote_sum >= 2'd2);

    // FSM Registers
    // the widths accomodate different parameters
    reg [7:0] sample_count = 0;
    reg [5:0] bit_count = 0; 
    reg [DATA_BITS-1:0] shift_reg = 0;
    
    reg rx_valid_reg = 1'b0;
    reg [DATA_BITS-1:0] rx_data_reg = 0;
    reg rx_frame_error_reg = 1'b0;

    reg [1:0] state = 0;
    // FSM States
    parameter RX_IDLE = 2'b00; // Idle state
    parameter RX_START = 2'b01;
    parameter RX_RECEIVE_DATA = 2'b11; // Receive data bits
    parameter RX_STOP = 2'b10; // Stop state

    // FSM logic for RX
    always @(posedge clk) begin
        if (!reset_n) begin
            state <= RX_IDLE;
            sample_count <= 8'd0;
            bit_count <= 6'd0;
            shift_reg <= {DATA_BITS{1'b0}};
            rx_sample_a <= 1'b0;
            rx_sample_b <= 1'b0;
            rx_valid_reg <= 1'b0;
            rx_data_reg <= {DATA_BITS{1'b0}};
            rx_frame_error_reg <= 1'b0;
        end else begin
        
            // Clear pulses
            rx_valid_reg <= 1'b0;
            rx_frame_error_reg <= 1'b0;
            
            case(state)
            
                RX_IDLE:
                    begin
                        if (rx_falling_edge == 1'b1) begin
                            sample_count <= 8'd0;
                            bit_count <= 6'd0;
                            state <= RX_START;
                        end
                    end
                    
                RX_START:
                    begin
                        if (baud_tick == 1'b1) begin
                            if (sample_count == MID_SAMPLE && rx_sync_2 == 1'b1) begin
                                // False start, abort
                                state <= RX_IDLE;
                                sample_count <= 8'd0;
                            end else if (sample_count == SAMPLES_PER_BIT - 1) begin
                                sample_count <= 8'd0;
                                state <= RX_RECEIVE_DATA;
                            end else begin
                            sample_count <= sample_count + 8'd1;
                            end
                        end
                    end
                    
                RX_RECEIVE_DATA:
                    begin
                        if (baud_tick == 1'b1) begin
                            // Capture samples around the center for majority vote
                            if (sample_count == SAMPLE_A) rx_sample_a <= rx_sync_2;
                            if (sample_count == SAMPLE_B) rx_sample_b <= rx_sync_2;
                            
                            // At SAMPLE_C check the majority and shift in data
                            if (sample_count == SAMPLE_C) begin
                                shift_reg <= {voted_bit, shift_reg[DATA_BITS-1:1]}; // LSB first
                                bit_count <= bit_count + 6'd1;
                            end
                            
                            // End of bit period
                            if (sample_count == SAMPLES_PER_BIT - 1) begin
                                sample_count <= 8'd0;
                                // Check if we just finished the last data bit
                                if (bit_count == DATA_BITS) begin 
                                    state <= RX_STOP;
                                end else begin
                                    state <= RX_RECEIVE_DATA;
                                end
                            end else begin
                                sample_count <= sample_count + 8'd1;
                            end
                        end
                    end
                    
                RX_STOP:
                    begin
                        if (baud_tick == 1'b1) begin
                            // Check middle of stop bit
                            if (sample_count == MID_SAMPLE) begin
                                if (rx_sync_2 == 1'b1) begin // Valid stop bit
                                    rx_valid_reg <= 1'b1;
                                    rx_data_reg <= shift_reg;
                                end else begin
                                    rx_frame_error_reg <= 1'b1;
                                end
                            end
                            
                            // End of stop bit period
                            if (sample_count == SAMPLES_PER_BIT - 1) begin
                                sample_count <= 8'd0;
                                state <= RX_IDLE;
                            end else begin
                                sample_count <= sample_count + 8'd1;
                            end
                        end
                    end        
            endcase        
        end
    end

    assign rx_valid = rx_valid_reg;
    assign rx_data = rx_data_reg;
    assign rx_frame_error = rx_frame_error_reg;

endmodule
