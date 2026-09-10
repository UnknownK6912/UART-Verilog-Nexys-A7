`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/31/2026 05:27:09 PM
// Design Name: 
// Module Name: uart_tx_tb
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
module uart_tx_tb(
    );
 
    localparam DATA_BITS = 8;
    localparam integer FPGA_CLK_FREQ = 100_000_000;
    localparam real FPGA_CLK_PERIOD_NS = 1_000_000_000.0 / FPGA_CLK_FREQ;
    localparam integer SAMPLES_PER_BIT = 16;
    localparam integer BAUD_RATE = 115_200;
    localparam integer CLKS_PER_SAMPLE = (FPGA_CLK_FREQ + BAUD_RATE * SAMPLES_PER_BIT / 2)
                                         / (BAUD_RATE * SAMPLES_PER_BIT);
    localparam integer BIT_PERIOD_CLKS = CLKS_PER_SAMPLE * SAMPLES_PER_BIT;
    localparam integer FRAME_CYCLES_EXP = (1 + DATA_BITS + 1) * BIT_PERIOD_CLKS; // start+data+stop
    localparam integer FRAME_CYC_TOL = 1; // +-1 cycle tolerance on the frame-length check
 
    reg  clk_tb;
    reg  reset_n_tb;
    reg  tx_start_tb;
    reg  [DATA_BITS-1:0] tx_data_tb;
    wire tx_busy_tb;
    wire tx_done_tb;
    wire uart_tx_tb_wire;
 
    uart_tx #(
        .DATA_BITS(DATA_BITS),
        .SAMPLES_PER_BIT(SAMPLES_PER_BIT)
    ) uart_tx_test
    (
        .clk(clk_tb),
        .reset_n(reset_n_tb),
        .tx_start(tx_start_tb),
        .tx_data(tx_data_tb),
        .tx_busy(tx_busy_tb),
        .tx_done(tx_done_tb),
        .uart_tx(uart_tx_tb_wire)
    );
 
    initial begin
        clk_tb = 0;
        forever #(FPGA_CLK_PERIOD_NS/2) clk_tb = ~clk_tb;
    end
 
    localparam MSG_LEN = 12;
    localparam [8*MSG_LEN-1:0] MESSAGE_tb = "UART TX Test";
 
    integer errors = 0;
    integer tests = 0;
    integer done_pulse_count = 0;
 
 
    // Check that tx_done is a single-cycle pulse
    reg tx_done_d = 1'b0;
    always @(posedge clk_tb) begin
        if (tx_done_tb == 1'b1) begin
            done_pulse_count = done_pulse_count + 1;
        end
        if (tx_done_tb && tx_done_d) begin
            $display("[%0t] ERROR: tx_done held high for >1 cycle", $time);
            errors = errors + 1;
        end
        tx_done_d <= tx_done_tb; // for behavior to be correct, tx_done_d would get updated to 1
                                 // and on the next cycle, tx_done_tb would get back to 0, indicating a pulse
    end
 
 
    // Measure how many cycles tx_busy stays high
    // per frame and check it against expected frame length
    integer frame_cycle_count = 0;
    reg tx_busy_d = 1'b0;
    always @(posedge clk_tb) begin
        tx_busy_d <= tx_busy_tb;
        if (tx_busy_tb == 1'b1) begin
            frame_cycle_count = frame_cycle_count + 1;
        end
        if (tx_busy_d && !tx_busy_tb) begin // falling edge = frame just ended
            if (reset_n_tb) begin // skip the check if busy dropped because of reset, not completion
                if ((frame_cycle_count < FRAME_CYCLES_EXP - FRAME_CYC_TOL) ||
                    (frame_cycle_count > FRAME_CYCLES_EXP + FRAME_CYC_TOL)) begin
                    $display("[%0t] ERROR: frame length %0d cycles, expected %0d (+/-%0d)", $time, frame_cycle_count, FRAME_CYCLES_EXP, FRAME_CYC_TOL);
                    errors = errors + 1;
                end
            end
            frame_cycle_count = 0;
        end
    end
 
 
    function [7:0] get_char;
        input [8*MSG_LEN-1:0] msg;
        input integer i;
        begin
            get_char = msg[(MSG_LEN-1-i)*8 +: 8];
        end
    endfunction
 
 
    task send_and_check(input [DATA_BITS-1:0] data);
        integer i;
        reg [DATA_BITS-1:0] captured;
        reg start_bit_val;
        reg stop_bit_val;
        begin
            tests = tests + 1;
 
            @(posedge clk_tb);
            tx_data_tb = data;
            tx_start_tb = 1'b1;
            @(posedge clk_tb);
            tx_start_tb = 1'b0;
 
            if (tx_busy_tb !== 1'b1) begin
                $display("[%0t] ERROR: tx_busy not asserted after tx_start (data=0x%0h)", $time, data);
                errors = errors + 1;
            end
 
            repeat (BIT_PERIOD_CLKS/2) @(posedge clk_tb);
            start_bit_val = uart_tx_tb_wire;
            if (start_bit_val !== 1'b0) begin
                $display("[%0t] ERROR: start bit not 0 (data=0x%0h, got=%b)", $time, data, start_bit_val);
                errors = errors + 1;
            end
 
            for (i = 0; i < DATA_BITS; i = i + 1) begin
                repeat (BIT_PERIOD_CLKS) @(posedge clk_tb);
                captured[i] = uart_tx_tb_wire;
            end
 
            if (captured !== data) begin
                $display("[%0t] ERROR: data mismatch: sent=0x%0h received=0x%0h", $time, data, captured);
                errors = errors + 1;
            end
 
            repeat (BIT_PERIOD_CLKS) @(posedge clk_tb);
            stop_bit_val = uart_tx_tb_wire;
            if (stop_bit_val !== 1'b1) begin
                $display("[%0t] ERROR: stop bit not 1 (data=0x%0h, got=%b)", $time, data, stop_bit_val);
                errors = errors + 1;
            end
 
            repeat (BIT_PERIOD_CLKS/2 + 4) @(posedge clk_tb);
            if (tx_busy_tb !== 1'b0) begin
                $display("[%0t] ERROR: tx_busy still high after frame complete (data=0x%0h)", $time, data);
                errors = errors + 1;
            end
 
            $display("[%0t] PASS: sent 0x%0h, framing OK", $time, data);
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
 

    // A second tx_start with different data, issued mid-frame, must be
    // ignored
    task check_busy_reject;
        begin
            tests = tests + 1;
            @(posedge clk_tb);
            tx_data_tb = 8'hA5;
            tx_start_tb = 1'b1;
            @(posedge clk_tb);
            tx_start_tb = 1'b0;
 
            repeat (BIT_PERIOD_CLKS * 2) @(posedge clk_tb);
 
            @(posedge clk_tb);
            tx_data_tb = 8'h3C;   // different byte, must be ignored
            tx_start_tb = 1'b1;
            @(posedge clk_tb);
            tx_start_tb = 1'b0;
 
            repeat (BIT_PERIOD_CLKS * 8) @(posedge clk_tb);
 
            if (tx_busy_tb !== 1'b0) begin
                $display("[%0t] ERROR: frame did not complete cleanly after busy-reject test", $time);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: tx_start ignored while busy", $time);
            end
        end
    endtask
 

    task check_continuous_burst;
        integer frames_before, frames_after;
        begin
            tests = tests + 1;
            frames_before = done_pulse_count;
 
            @(posedge clk_tb);
            tx_data_tb = 8'h5A;
            tx_start_tb = 1'b1;                 // held high, not pulsed
            repeat (BIT_PERIOD_CLKS * 10 * 3 + 50) @(posedge clk_tb); // ~3 frames worth
            tx_start_tb = 1'b0;
 
            repeat (BIT_PERIOD_CLKS * 10 + 20) @(posedge clk_tb); // let any in-flight frame finish
 
            frames_after = done_pulse_count;
            if ((frames_after - frames_before) < 3) begin
                $display("[%0t] ERROR: continuous tx_start burst produced only %0d frames, expected >=3",
                          $time, frames_after - frames_before);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: continuous tx_start burst produced %0d back-to-back frames cleanly",
                          $time, frames_after - frames_before);
            end
        end
    endtask


    // Asserts reset_n_tb halfway through a transmission and confirms a clean return to idle
    task check_reset_mid_frame;
        begin
            tests = tests + 1;
            @(posedge clk_tb);
            tx_data_tb  = 8'hC3;
            tx_start_tb = 1'b1;
            @(posedge clk_tb);
            tx_start_tb = 1'b0;
 
            repeat (BIT_PERIOD_CLKS * 4) @(posedge clk_tb);
            reset_n_tb = 1'b0;
            repeat (5) @(posedge clk_tb);
 
            if (tx_busy_tb !== 1'b0) begin
                $display("[%0t] ERROR: tx_busy still high during reset", $time);
                errors = errors + 1;
            end
            if (uart_tx_tb_wire !== 1'b1) begin
                $display("[%0t] ERROR: uart line not idle-high during reset", $time);
                errors = errors + 1;
            end
 
            reset_n_tb = 1'b1;
            repeat (5) @(posedge clk_tb);
 
            if (uart_tx_tb_wire !== 1'b1) begin
                $display("[%0t] ERROR: uart line not idle-high after reset release", $time);
                errors = errors + 1;
            end else begin
                $display("[%0t] PASS: reset mid-frame recovered cleanly", $time);
            end
        end
    endtask
 

    // Main stimulus
    initial begin
        reset_n_tb  = 1'b0;
        tx_start_tb = 1'b0;
        tx_data_tb  = {DATA_BITS{1'b0}};
 
        repeat (10) @(posedge clk_tb);
        reset_n_tb = 1'b1;
        repeat (5) @(posedge clk_tb);
 
        if (uart_tx_tb_wire !== 1'b1) begin
            $display("[%0t] ERROR: uart_tx not idle-high after reset", $time);
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
        check_busy_reject();
        repeat (20) @(posedge clk_tb);
 
        check_continuous_burst();
        repeat (20) @(posedge clk_tb);
 
        check_reset_mid_frame();
        repeat (20) @(posedge clk_tb);
 
        $display("--------------------------------------------------");
        $display("Tests run : %0d", tests);
        $display("Errors    : %0d", errors);
        $display("tx_done pulses observed: %0d", done_pulse_count);
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
    
