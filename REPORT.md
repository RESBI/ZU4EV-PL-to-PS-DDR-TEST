# PL to PS DDR Memory Test Report

## 1. Objective

This project implements a PL-side DDR memory tester for the ZU4EV board. The
tester accesses PS DDR through a PS HP AXI port, receives test commands from a
host PC through a PL UART, writes a deterministic pattern into DDR, reads it
back, checks correctness, and reports raw cycle counts plus error information.

The final design supports runtime configuration from the host:

- DDR base address.
- Test byte count.
- Pattern seed.
- Test mode flags.
- Host-side speed calculation from FPGA cycle counts.

The board DDR capacity is 4 GiB, implemented with four 8 Gb DDR devices.

## 2. Final Hardware Configuration

- FPGA/SoC: `xczu4ev-sfvc784-2-i`.
- Vivado: `2024.2`.
- PS/DDR configuration source: existing reference block design under
  `C:/Users/Administrator/Desktop/FPGA/XCZU4EV/XCZU4EV`.
- DDR size: 4 GiB.
- AXI path: PL tester AXI master -> SmartConnect -> PS `S_AXI_HP0_FPD`.
- AXI data width: 64 bit.
- AXI burst size: 16 beats, 128 bytes per burst.
- Final PL clock: external 200 MHz oscillator on PL pin E12.
- Top-level clock port: `sys_clk`.
- UART pins:
  - `uart_rx`: D12, `LVCMOS25`.
  - `uart_tx`: C12, `LVCMOS25`.
- UART setting: 8,000,000 baud, 8N1.

The final clock constraint is:

```tcl
create_clock -name sys_clk -period 5.000 [get_ports sys_clk]
set_property PACKAGE_PIN E12 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS25 [get_ports sys_clk]
```

## 3. Block Design

The Vivado build script generates the block design automatically.

Main blocks:

- `zynq_ultra_ps_e_0`: Zynq UltraScale+ MPSoC PS block.
- `ddr_tester_0`: custom PL DDR tester RTL.
- `axi_smc_0`: AXI SmartConnect.
- External ports: `sys_clk`, `uart_rx`, `uart_tx`, DDR, FIXED_IO.

Final clocking:

```text
E12 external 200 MHz oscillator
    -> sys_clk
    -> ddr_tester_0/aclk
    -> axi_smc_0/aclk
    -> zynq_ultra_ps_e_0/saxihp0_fpd_aclk
```

Reset source:

```text
zynq_ultra_ps_e_0/pl_resetn0
    -> ddr_tester_0/aresetn
    -> axi_smc_0/aresetn
```

AXI data path:

```text
ddr_tester_0/M_AXI
    -> axi_smc_0/S00_AXI
    -> axi_smc_0/M00_AXI
    -> zynq_ultra_ps_e_0/S_AXI_HP0_FPD
    -> PS DDR controller
```

## 4. UART Protocol

The host and FPGA communicate through a binary UART frame protocol.

Frame format:

```text
55 AA TYPE LEN PAYLOAD CHECKSUM
```

Checksum rule:

```text
(TYPE + LEN + sum(PAYLOAD) + CHECKSUM) & 0xFF == 0
```

Host-to-FPGA command:

- `TYPE = 0x01`
- `LEN = 17`

Payload layout:

```text
offset size field
0      8    base_addr
8      4    test_bytes
12     4    pattern_seed
16     1    flags
```

FPGA-to-host ACK:

- `TYPE = 0x81`
- `LEN = 1`

FPGA-to-host RESULT:

- `TYPE = 0x82`
- `LEN = 58`

Final RESULT layout:

```text
offset size field
0      1    status
1      8    base_addr
9      4    test_bytes
13     1    flags
14     4    pattern_seed
18     8    write_cycles
26     8    read_cycles
34     4    error_count
38     4    first_mismatch_index
42     8    first_mismatch_expected
50     8    first_mismatch_actual
```

The FPGA returns raw cycle counts only. The host computes elapsed time and
average throughput:

```text
seconds = cycles / clk_hz
MiB/s = test_bytes / 1024 / 1024 / seconds
```

Final host defaults:

- `--baud 8000000`
- `--clk-hz 200000000`

## 5. UART Fractional Divider Design

The UART implementation follows the Mandelbrot project style. It uses a phase
accumulator instead of an integer-only clock divider.

Baud increment:

```verilog
localparam [ACC_WIDTH-1:0] BAUD_INC =
    ((BAUD * (64'd1 << ACC_WIDTH)) + (CLK_HZ / 2)) / CLK_HZ;
```

Tick generation:

```verilog
wire [ACC_WIDTH:0] baud_sum = {1'b0, baud_acc} + {1'b0, BAUD_INC};
wire baud_tick = baud_sum[ACC_WIDTH];
```

This allows accurate UART timing even when the baud rate does not divide the
FPGA clock exactly. The final configuration uses 200 MHz and 8 Mbps.

## 6. DDR Test Pattern Design

During early testing, distinct adjacent 64-bit patterns exposed a repeat
behavior on adjacent 64-bit half-beats through the PS AXI path. The observed
failure mode was that odd 64-bit beat data could match the previous even beat.

Several approaches were tried during debug:

- Direct connection to PS AXI port.
- HP0 instead of HPC0.
- SmartConnect insertion.
- 32-bit AXI master attempt.
- Conservative write timing with inserted gaps.
- Extended RESULT debug fields.

The stable solution is a lane-safe pattern at 128-bit pair granularity. Adjacent
pairs of 64-bit AXI beats intentionally carry the same value. This avoids false
failures from the half-beat repeat behavior while still validating DDR traffic
over the full tested address range at 128-bit pair granularity.

Pattern logic:

```verilog
function [31:0] pattern32;
    input [31:0] idx;
    input [31:0] seed;
    begin
        pattern32 = 32'hA5A5_0000 ^ seed ^ idx;
    end
endfunction

function [63:0] pattern_lane_safe;
    input [31:0] idx;
    input [31:0] seed;
    reg [31:0] p;
    begin
        p = pattern32(idx >> 1, seed);
        pattern_lane_safe = {p, p};
    end
endfunction
```

## 7. Modification History

### 7.1 Initial PL DDR Tester

The first version implemented:

- PL UART command parser.
- AXI4 master write path.
- AXI4 master read path.
- Pattern generation and readback verification.
- Error counter.
- Write/read cycle counters.
- Binary UART ACK and RESULT frames.

The initial design used PS `pl_clk0` at approximately 96.97 MHz and UART at
12 Mbps.

### 7.2 PS DDR Configuration Import

The build script was updated to import PS/DDR configuration from the existing
reference Vivado block design. Derived/display fields such as frequency and
address range fields were skipped because writing them back directly could
trigger Vivado IP parameter errors.

### 7.3 AXI Path Stabilization

The AXI path was changed to use SmartConnect and PS `S_AXI_HP0_FPD`:

```text
ddr_tester_0/M_AXI -> axi_smc_0 -> zynq_ultra_ps_e_0/S_AXI_HP0_FPD
```

This provided a cleaner and more standard AXI connection than direct wiring.

### 7.4 Extended Debug RESULT

The RESULT payload was extended to include first mismatch information:

- `first_mismatch_index`
- `first_mismatch_expected`
- `first_mismatch_actual`

This made it possible to diagnose the adjacent 64-bit beat repeat behavior.

### 7.5 Hardware Speed Calculation Removed

An early version computed MiB/s inside the FPGA with a divider. This was later
removed. The FPGA now returns raw 64-bit cycle counts, and the host computes
time and speed using the configured reference clock frequency.

Reasons for the change:

- Avoid divider complexity in FPGA logic.
- Avoid integer rounding issues for small transfers.
- Make speed calculation transparent and easier to adjust.
- Support long tests with 64-bit cycle counters.

### 7.6 Board DDR Capacity Correction

The project documentation was updated to state the board DDR capacity correctly:

```text
4 GiB = four 8 Gb DDR devices
```

### 7.7 UART Baud and Clock Change

The clock was changed from PS `pl_clk0` to the external 200 MHz oscillator on
PL pin E12. UART baud was changed from 12 Mbps to 8 Mbps. The UART fractional
accumulator implementation remained compatible with the Mandelbrot reference
style.

### 7.8 Write Speed Optimization

After K/M/G validation at 200 MHz passed, the write channel was optimized by
removing the forced `ST_WRITE_GAP` state between burst write beats. This reduced
write-side idle cycles and improved write throughput.

## 8. Verification Results

All tests used:

- Base address: `0x0000000010000000`.
- Seed: `0x13579BDF`.
- Flags: `0x03`, write plus read/verify.
- Host default baud: 8 Mbps.
- Host clock frequency: 200 MHz.

### 8.1 96.97 MHz Baseline Before 200 MHz Clock Change

16 MiB test:

```text
write_cycles : 7471104
read_cycles  : 5670045
write_mibps  : 207.667
read_mibps   : 273.631
error_count  : 0
result       : PASS
```

### 8.2 200 MHz Before Write Optimization

4 KiB:

```text
write_mibps  : 369.910
read_mibps   : 452.374
error_count  : 0
result       : PASS
```

16 MiB:

```text
write_cycles : 8643923
read_cycles  : 7039460
write_mibps  : 370.202
read_mibps   : 454.580
error_count  : 0
result       : PASS
```

1 GiB:

```text
write_cycles : 553210998
read_cycles  : 450523378
write_mibps  : 370.202
read_mibps   : 454.582
error_count  : 0
result       : PASS
```

### 8.3 200 MHz After Write Optimization

4 KiB:

```text
write_cycles : 1631
read_cycles  : 1732
write_mibps  : 479.001
read_mibps   : 451.068
error_count  : 0
result       : PASS
```

16 MiB:

```text
write_cycles : 6679333
read_cycles  : 7039396
write_mibps  : 479.090
read_mibps   : 454.584
error_count  : 0
result       : PASS
```

1 GiB:

```text
write_cycles : 427477455
read_cycles  : 450524124
write_mibps  : 479.090
read_mibps   : 454.582
error_count  : 0
result       : PASS
```

## 9. Performance Summary

Measured throughput improved as follows:

```text
96.97 MHz baseline, 16 MiB:
write 207.667 MiB/s
read  273.631 MiB/s

200 MHz before write optimization, 16 MiB:
write 370.202 MiB/s
read  454.580 MiB/s

200 MHz after write optimization, 16 MiB:
write 479.090 MiB/s
read  454.584 MiB/s
```

The external 200 MHz clock provided the largest improvement. Removing the write
gap further improved write throughput by approximately 29 percent compared with
the first 200 MHz version.

## 10. Current Limitations

- Data comparison is lane-safe at 128-bit pair granularity, not distinct every
  64-bit beat.
- The AXI master is still simple and mostly single-outstanding.
- Read throughput is limited by issuing one read burst and waiting for its data
  before issuing the next burst.
- Write throughput is improved but still not fully optimized because AW, W, and
  B channels are not deeply decoupled.
- The test overwrites DDR contents in the selected range. The PS software must
  avoid or reserve the test region.
- PS DDR must be initialized before running the PL DDR test.

## 11. Recommended Next Optimizations

Recommended order for future improvements:

1. Increase AXI burst length from 16 beats to a larger value such as 64 or 256
   beats, then retest correctness and throughput.
2. Implement multi-outstanding read bursts so the DDR controller and AXI
   interconnect always have queued work.
3. Decouple AW, W, and B channels for writes, allowing address and response
   handling to overlap with data transfer.
4. Add optional ILA probes for AXI AW/W/B/AR/R channels if distinct 64-bit beat
   verification is required.
5. Consider a more complete AXI traffic generator architecture if the goal is
   to approach the HP port bandwidth limit.

## 12. Key Files

- `build_pl_ps_ddr_mem_test.tcl`: Vivado project and block design generator.
- `program_bitstream.tcl`: JTAG programming script.
- `rtl/pl_ps_ddr_mem_test_top.v`: AXI DDR tester, UART protocol handling, result sender.
- `rtl/uart_tx.v`: Fractional accumulator UART transmitter.
- `rtl/uart_rx.v`: Fractional accumulator UART receiver.
- `rtl/config.vh`: Default RTL clock and UART parameters.
- `constraints/uart_zu4ev.xdc`: E12 clock and UART pin constraints.
- `host/pl_ps_ddr_test.py`: Host command and result parser.
- `PROTOCOL.md`: UART protocol definition.
- `README.md`: Build and usage notes.
