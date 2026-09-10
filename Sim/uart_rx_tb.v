`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/04/2026 07:36:08 PM
// Design Name: 
// Module Name: uart_rx_tb
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


module uart_rx_tb(
    );
 
    localparam DATA_BITS = 8;
    localparam integer FPGA_CLK_FREQ = 100_000_000;
    localparam real    FPGA_CLK_PERIOD_NS = 1_000_000_000.0 / FPGA_CLK_FREQ;
    localparam integer SAMPLES_PER_BIT = 16;
    localparam integer BAUD_RATE = 115_200;
    localparam integer CLKS_PER_SAMPLE = (FPGA_CLK_FREQ + BAUD_RATE * SAMPLES_PER_BIT / 2)
                                         / (BAUD_RATE * SAMPLES_PER_BIT);
    localparam integer BIT_PERIOD_CLKS = CLKS_PER_SAMPLE * SAMPLES_PER_BIT;
 
    reg  clk_tb;
    reg  reset_n_tb;
    reg  uart_rx_drv_tb;      // drives the DUT's serial input
    wire rx_valid_tb;
    wire [DATA_BITS-1:0] rx_data_tb;
    wire rx_frame_error_tb;
 
    uart_rx #(
        .DATA_BITS(DATA_BITS),
        .SAMPLES_PER_BIT(SAMPLES_PER_BIT)
    ) uart_rx_test
    (
        .clk(clk_tb),
        .reset_n(reset_n_tb),
        .uart_rx(uart_rx_drv_tb),
        .rx_valid(rx_valid_tb),
        .rx_data(rx_data_tb),
        .rx_frame_error(rx_frame_error_tb)
    );
 
    initial begin
        clk_tb = 0;
        forever #(FPGA_CLK_PERIOD_NS/2) clk_tb = ~clk_tb;
    end
 
    localparam MSG_LEN = 12;
    localparam [8*MSG_LEN-1:0] MESSAGE_tb = "UART RX Test";
 
    integer errors = 0;
    integer tests = 0;
    integer rx_valid_pulse_count = 0;
    integer rx_frame_error_pulse_count = 0;
    reg [DATA_BITS-1:0] last_rx_data_captured = 0;
 
 
    // Check that rx_valid is a single-cycle pulse, and record the data
    // that came with each pulse for send_and_check to compare against
    reg rx_valid_d = 1'b0;
    always @(posedge clk_tb) begin
        if (rx_valid_tb == 1'b1) begin
            rx_valid_pulse_count = rx_valid_pulse_count + 1;
            last_rx_data_captured = rx_data_tb;
        end
        if (rx_valid_tb && rx_valid_d) begin
            $display("[%0t] ERROR: rx_valid held high for >1 cycle", $time);
            errors = errors + 1;
        end
        rx_valid_d <= rx_valid_tb;
    end
 
 
    // Check that rx_frame_error is a single-cycle pulse
    reg rx_frame_error_d = 1'b0;
    always @(posedge clk_tb) begin
        if (rx_frame_error_tb == 1'b1) begin
            rx_frame_error_pulse_count = rx_frame_error_pulse_count + 1;
        end
        if (rx_frame_error_tb && rx_frame_error_d) begin
            $display("[%0t] ERROR: rx_frame_error held high for >1 cycle", $time);
            errors = errors + 1;
        end
        rx_frame_error_d <= rx_frame_error_tb;
    end
 

    function [7:0] get_char;
        input [8*MSG_LEN-1:0] msg;
        input integer i;
        begin
            get_char = msg[(MSG_LEN-1-i)*8 +: 8];
        end
    endfunction
 
 
    // Drives uart_rx_drv_tb to "value" for exactly one bit period
    task drive_bit(input value);
        begin
            uart_rx_drv_tb = value;
            repeat (BIT_PERIOD_CLKS) @(posedge clk_tb);
        end
    endtask
 
 
    task send_and_check(input [DATA_BITS-1:0] data);
        integer i;
        integer valid_before, error_before;
        begin
            tests = tests + 1;
            valid_before = rx_valid_pulse_count;
            error_before = rx_frame_error_pulse_count;
 
            drive_bit(1'b0);                        // start bit
            for (i = 0; i < DATA_BITS; i = i + 1)
                drive_bit(data[i]);                 // data bits, LSB first
            drive_bit(1'b1);                        // stop bit
            repeat (20) @(posedge clk_tb);           // margin for rx_valid to register
 
            if (rx_valid_pulse_count !== valid_before + 1) begin
                $display("[%0t] ERROR: rx_valid did not pulse exactly once (data=0x%0h)", $time, data);
                errors = errors + 1;
            end else if (last_rx_data_captured !== data) begin
                $display("[%0t] ERROR: rx_data mismatch: sent=0x%0h received=0x%0h", $time, data, last_rx_data_captured);
                errors = errors + 1;
            end else if (rx_frame_error_pulse_count !== error_before) begin
                $display("[%0t] ERROR: unexpected rx_frame_error during valid frame (data=0x%0h)", $time, data);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: received 0x%0h correctly", $time, data);
            end
        end
    endtask
 
 
    // Passes an ASCII message character by character through
    // send_and_check
    task send_string(input [8*MSG_LEN-1:0] msg, input integer len);
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                send_and_check(get_char(msg, i));
                repeat (20) @(posedge clk_tb);
            end
        end
    endtask
 
 
    // A frame with the stop bit driven low (invalid) must set
    // rx_frame_error and must not set rx_valid
    task check_frame_error;
        integer i;
        reg [DATA_BITS-1:0] test_byte;
        integer valid_before, error_before;
        begin
            tests = tests + 1;
            test_byte = 8'h5A;
            valid_before = rx_valid_pulse_count;
            error_before = rx_frame_error_pulse_count;
 
            drive_bit(1'b0);                        // start bit
            for (i = 0; i < DATA_BITS; i = i + 1)
                drive_bit(test_byte[i]);
            drive_bit(1'b0);                        // bad stop bit (should be 1)
            drive_bit(1'b1);                        // return line to idle before continuing
            repeat (20) @(posedge clk_tb);
 
            if (rx_frame_error_pulse_count !== error_before + 1) begin
                $display("[%0t] ERROR: rx_frame_error did not pulse on bad stop bit", $time);
                errors = errors + 1;
            end else if (rx_valid_pulse_count !== valid_before) begin
                $display("[%0t] ERROR: rx_valid asserted despite invalid stop bit", $time);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: bad stop bit correctly flagged as frame error", $time);
            end
        end
    endtask
 
 
    // A glitch shorter than half a bit period must be rejected as a
    // false start: no rx_valid, no rx_frame_error, with clean return to idle
    task check_false_start;
        integer valid_before, error_before;
        begin
            tests = tests + 1;
            valid_before = rx_valid_pulse_count;
            error_before = rx_frame_error_pulse_count;
 
            uart_rx_drv_tb = 1'b0;
            repeat (BIT_PERIOD_CLKS/4) @(posedge clk_tb); // quarter-bit glitch, well under the
                                                           // mid-start-bit check point
            uart_rx_drv_tb = 1'b1;
            repeat (BIT_PERIOD_CLKS*2) @(posedge clk_tb);
 
            if (rx_valid_pulse_count !== valid_before || rx_frame_error_pulse_count !== error_before) begin
                $display("[%0t] ERROR: false start incorrectly produced rx_valid or rx_frame_error", $time);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: brief glitch correctly rejected as false start", $time);
            end
        end
    endtask
 
 
    // Back-to-back frames with only the minimum legal gap: the stop bit
    // of frame N is itself the only idle-high time before frame N+1's
    // start bit. send_and_check adds no extra idle beyond that, so
    // calling it twice in a row exercises this directly.
    task check_minimal_gap;
        begin
            $display("[%0t] INFO: testing minimal (stop-bit-only) gap between frames", $time);
            send_and_check(8'h11);
            send_and_check(8'h22);
        end
    endtask
 
 
    // Injects a single clock cycle glitch timed to corrupt exactly one
    // of the three majority-vote samples (SAMPLE_B) during a data bit,
    // and checks the vote still recovers the correct bit.
    task check_majority_vote;
        reg [DATA_BITS-1:0] test_byte;
        integer valid_before, error_before;
        integer i;
        reg glitch_now;
        begin
            tests = tests + 1;
            test_byte = 8'hAA;             // LSB (bit 0) = 0
            valid_before = rx_valid_pulse_count;
            error_before = rx_frame_error_pulse_count;
            glitch_now = 1'b0;
 
            drive_bit(1'b0);               // start bit
 
            // Drive data bit 0 for the normal BIT_PERIOD_CLKS duration,
            // except for a 1-cycle glitch to the wrong value fired by a
            // parallel process timed against the DUT's SAMPLE_B point.
            fork
                begin : drive_glitched_bit
                    integer k;
                    for (k = 0; k < BIT_PERIOD_CLKS; k = k + 1) begin
                        uart_rx_drv_tb = glitch_now ? ~test_byte[0] : test_byte[0];
                        @(posedge clk_tb);
                    end
                end
                begin : inject_glitch
                    wait (uart_rx_test.state == uart_rx_test.RX_RECEIVE_DATA &&
                          uart_rx_test.sample_count == uart_rx_test.SAMPLE_B - 1 &&
                          uart_rx_test.baud_tick);
                    @(posedge clk_tb);
                    glitch_now = 1'b1;
                    @(posedge clk_tb);
                    glitch_now = 1'b0;
                end
            join
 
            for (i = 1; i < DATA_BITS; i = i + 1)
                drive_bit(test_byte[i]);
            drive_bit(1'b1);               // stop bit
            repeat (20) @(posedge clk_tb);
 
            if (rx_valid_pulse_count !== valid_before + 1) begin
                $display("[%0t] ERROR: majority-vote test did not produce a valid byte", $time);
                errors = errors + 1;
            end else if (last_rx_data_captured !== test_byte) begin
                $display("[%0t] ERROR: majority vote failed to reject single-sample noise: sent=0x%0h received=0x%0h",
                          $time, test_byte, last_rx_data_captured);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: majority vote rejected single-sample noise, received 0x%0h", $time, test_byte);
            end
        end
    endtask
 
 
    // Asserts reset_n_tb halfway through a frame
    task check_reset_mid_frame;
        integer i;
        reg [DATA_BITS-1:0] test_byte;
        begin
            tests = tests + 1;
            test_byte = 8'hC3;
 
            drive_bit(1'b0);                    // start bit
            for (i = 0; i < 4; i = i + 1)
                drive_bit(test_byte[i]);
 
            reset_n_tb = 1'b0;
            repeat (5) @(posedge clk_tb);
 
            if (rx_valid_tb !== 1'b0 || rx_frame_error_tb !== 1'b0) begin
                $display("[%0t] ERROR: rx_valid/rx_frame_error not clear during reset", $time);
                errors = errors + 1;
            end
 
            reset_n_tb = 1'b1;
            uart_rx_drv_tb = 1'b1;              // return line to idle before resuming
            repeat (10) @(posedge clk_tb);
 
            if (rx_valid_tb !== 1'b0 || rx_frame_error_tb !== 1'b0) begin
                $display("[%0t] ERROR: rx_valid/rx_frame_error not clear after reset release", $time);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: reset mid-frame recovered cleanly", $time);
            end
        end
    endtask
 
 
    // Main stimulus
    initial begin
        reset_n_tb     = 1'b0;
        uart_rx_drv_tb = 1'b1;   // idle high
 
        repeat (10) @(posedge clk_tb);
        reset_n_tb = 1'b1;
        repeat (5) @(posedge clk_tb);
 
        if (rx_valid_tb !== 1'b0 || rx_frame_error_tb !== 1'b0 || rx_data_tb !== {DATA_BITS{1'b0}}) begin
            $display("[%0t] ERROR: outputs not quiescent after reset", $time);
            errors = errors + 1;
        end
 
        // Byte sweep
        send_and_check(8'h00); repeat (20) @(posedge clk_tb);
        send_and_check(8'hFF); repeat (20) @(posedge clk_tb);
        send_and_check(8'h55); repeat (20) @(posedge clk_tb);
        send_and_check(8'hAA); repeat (20) @(posedge clk_tb);
        send_and_check(8'h01); repeat (20) @(posedge clk_tb);
        send_and_check(8'h80); repeat (20) @(posedge clk_tb);
 
        // Pseudo-random bytes
        send_and_check($random); repeat (20) @(posedge clk_tb);
        send_and_check($random); repeat (20) @(posedge clk_tb);
        send_and_check($random); repeat (20) @(posedge clk_tb);
 
        // ASCII string sweep
        send_string(MESSAGE_tb, MSG_LEN);
        repeat (20) @(posedge clk_tb);
 
        // Behavioral edge cases
        check_frame_error();
        repeat (20) @(posedge clk_tb);
 
        check_false_start();
        repeat (20) @(posedge clk_tb);
 
        check_minimal_gap();
        repeat (20) @(posedge clk_tb);
 
        check_majority_vote();
        repeat (20) @(posedge clk_tb);
 
        check_reset_mid_frame();
        repeat (20) @(posedge clk_tb);
 
        // Confirm RX still functions correctly after the reset above
        send_and_check(8'h99);
        repeat (20) @(posedge clk_tb);
 
        $display("--------------------------------------------------");
        $display("Tests run : %0d", tests);
        $display("Errors    : %0d", errors);
        $display("rx_valid pulses observed: %0d", rx_valid_pulse_count);
        $display("rx_frame_error pulses observed: %0d", rx_frame_error_pulse_count);
        if (errors == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: FAILURES DETECTED");
        $display("--------------------------------------------------");
 
        $finish;
    end
 
    // Safety timeout in case the FSM hangs
    initial begin
        #5_000_000; // 5 ms sim time
        $display("[%0t] ERROR: TIMEOUT - simulation did not finish", $time);
        $finish;
    end
 
endmodule
 

