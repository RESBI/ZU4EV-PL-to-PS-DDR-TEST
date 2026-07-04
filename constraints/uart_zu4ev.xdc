# VMC_RTSB ZU4EV constraints, matching the Mandelbrot UART/clock reference.

# Board reference clock: 200 MHz single-ended oscillator on E12.
create_clock -name sys_clk -period 5.000 [get_ports sys_clk]
set_property PACKAGE_PIN E12 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS25 [get_ports sys_clk]

set_property PACKAGE_PIN D12 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS25 [get_ports uart_rx]

set_property PACKAGE_PIN C12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS25 [get_ports uart_tx]

set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
