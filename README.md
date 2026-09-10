# uart-verilog

A basic, parameterized UART transmitter/receiver written in Verilog.

## Modules

- `uart_tx.v` – UART transmitter
- `uart_rx.v` – UART receiver with 16x oversampling (configurable) and 3-sample majority voting to reject noise/jitter on the line
- `uart_top.v` – wraps Tx + Rx together
- `nexys_a7_uart_top.v` – board-level wrapper for the Nexys A7, currently wired for loopback (whatever comes in on RX gets sent back out on TX)

## Parameters

Both `uart_tx` and `uart_rx` take:

- `DATA_BITS` (default 8)
- `SAMPLES_PER_BIT` (default 16)
- `FPGA_CLK_FREQ` (default 100 MHz)
- `BAUD_RATE` (default 115200)

Clock divider values are derived from these, so changing clock speed or baud rate just means changing the parameters.

## Status
There is definitely room for improvement.
For instance, adding buffering would be good.
Further testing and/or better testbenches would also be great.
