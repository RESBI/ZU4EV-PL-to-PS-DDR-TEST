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

### START, TYPE = 0x01, LEN = 17

Payload:

```text
offset size field
0      8    base_addr
8      4    test_bytes
12     4    pattern_seed
16     1    flags
```

Flags:

- bit 0, `0x01`: write pattern to DDR.
- bit 1, `0x02`: read DDR and verify. If write is not enabled, read bandwidth is measured but data comparison is skipped.
- `0x00`: treated as `0x03` for write plus read/verify.

Hardware requirements:

- `base_addr` must be 128-byte aligned.
- `test_bytes` must be non-zero and 128-byte aligned.

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

### RESULT, TYPE = 0x82, LEN = 58

Payload:

```text
offset size field
0      1    status, 0x00 means pass
1      8    base_addr
9      4    test_bytes
13     1    flags
14     4    pattern_seed
18     8    write_cycles
26     8    read_cycles
34     4    error_count
38     4    first_mismatch_index, AXI beat index
42     8    first_mismatch_expected
50     8    first_mismatch_actual
```

`write_cycles` and `read_cycles` are raw PL clock cycle counts. The FPGA does
not divide these into throughput. The host computes elapsed time and average
MiB/s using the PL clock frequency, default `200,000,000 Hz`.

The current PL tester uses a lane-safe 64-bit pattern where each adjacent pair
of 64-bit AXI beats carries the same 32-bit value in both lanes. This validates
DDR traffic at 128-bit pair granularity and avoids false failures on PS AXI
paths that duplicate 64-bit half-beats during width conversion.

`error_count` counts AXI response errors and, when write plus read/verify is enabled, data mismatches.
