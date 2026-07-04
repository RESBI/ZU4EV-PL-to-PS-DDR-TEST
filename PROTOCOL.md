# PL-PS DDR Test UART Protocol

UART settings are `8,000,000 baud, 8N1` by default.

All multi-byte integer fields are little-endian.

## Frame Format

```text
55 AA TYPE LEN PAYLOAD CHECKSUM
```

- `55 AA`: sync bytes.
- `TYPE`: frame type.
- `LEN`: payload length in bytes.
- `CHECKSUM`: two's complement checksum over `TYPE`, `LEN`, and all payload bytes.

Checksum rule:

```text
(TYPE + LEN + sum(PAYLOAD) + CHECKSUM) & 0xFF == 0
```

## Host to PL

### QUERY_CONFIG, TYPE = 0x02, LEN = 0

Requests the FPGA's currently active address translation configuration. This
command has no payload and does not start a DDR test.

The FPGA responds with `MAP_CONFIG`, type `0x83`.

### START, TYPE = 0x01, LEN = 17 or LEN = 21

Payload:

```text
offset size field
0      8    base_addr
8      4    test_bytes
12     4    pattern_seed
16     1    flags
```

The preferred 64-bit-size START format is `LEN = 21`:

```text
offset size field
0      8    base_addr
8      8    test_bytes
16     4    pattern_seed
20     1    flags
```

Flags:

- bit 0, `0x01`: write pattern to DDR.
- bit 1, `0x02`: read DDR and verify. If write is not enabled, read bandwidth is measured but data comparison is skipped.
- `0x00`: treated as `0x03` for write plus read/verify.

Hardware requirements:

- `base_addr` must be 128-byte aligned.
- `test_bytes` must be non-zero and 128-byte aligned.

### START With Address Mapping, TYPE = 0x01, LEN = 34 or LEN = 38

The FPGA accepts an extended START frame that enables host-configurable
logical-to-physical DDR address translation. The current host script sends this
extended frame by default. Use `--no-addr-map` to send the legacy 17-byte START
frame for low-window-only tests.

Payload:

```text
offset size field
0      8    base_addr, logical address
8      4    test_bytes
12     4    pattern_seed
16     1    flags
17     1    addr_map_flags
18     8    logical_split
26     8    physical_high_base
```

The preferred mapped START format uses 64-bit `test_bytes` and `LEN = 38`:

```text
offset size field
0      8    base_addr, logical address
8      8    test_bytes
16     4    pattern_seed
20     1    flags
21     1    addr_map_flags
22     8    logical_split
30     8    physical_high_base
```

Address mapping flags:

- bit 0, `0x01`: enable two-segment address translation.

When enabled, the FPGA maps burst start addresses as follows:

```text
if logical_addr < logical_split:
    axi_addr = logical_addr
else:
    axi_addr = physical_high_base + (logical_addr - logical_split)
```

For the tested ZU4EV board, the default host mapping is:

```text
logical_split      = 0x0000000080000000
physical_high_base = 0x0000000800000000
```

This lets a host test range cross the logical 2 GiB boundary while the FPGA
issues AXI transactions to the PS DDR high-address window. The preferred host
format uses 64-bit `test_bytes`, so an exact 4 GiB transfer size
(`0x100000000`) can be represented in one command.

## PL to Host

### ACK, TYPE = 0x81, LEN = 1

Payload:

```text
offset size field
0      1    status
```

Status:

- `0x00`: command accepted.
- `0x01`: tester busy.
- `0x02`: bad base alignment.
- `0x03`: bad size.
- `0x7F`: malformed frame or checksum error.

### RESULT, TYPE = 0x82, LEN = 62

Payload:

```text
offset size field
0      1    status, 0x00 means pass
1      8    base_addr
9      8    test_bytes
17     1    flags
18     4    pattern_seed
22     8    write_cycles
30     8    read_cycles
38     4    error_count
42     4    first_mismatch_index, AXI beat index
46     8    first_mismatch_expected
54     8    first_mismatch_actual
```

Older bitstreams used `RESULT LEN = 58` with a 32-bit `test_bytes` field. The
host decoder still accepts that format for compatibility.

`write_cycles` and `read_cycles` are raw PL clock cycle counts. The FPGA does
not divide these into throughput. The host computes elapsed time and average
MiB/s using the PL clock frequency, default `200,000,000 Hz`.

The current PL tester uses a lane-safe 64-bit pattern where each adjacent pair
of 64-bit AXI beats carries the same 32-bit value in both lanes. This validates
DDR traffic at 128-bit pair granularity and avoids false failures on PS AXI
paths that duplicate 64-bit half-beats during width conversion.

`error_count` counts AXI response errors and, when write plus read/verify is enabled, data mismatches.

### MAP_CONFIG, TYPE = 0x83, LEN = 18

Payload:

```text
offset size field
0      1    busy, 1 when the tester is running or has an unsent result
1      1    addr_map_flags
2      8    logical_split
10     8    physical_high_base
```

`addr_map_flags bit 0` means the two-segment logical-to-physical address
translation is enabled.
