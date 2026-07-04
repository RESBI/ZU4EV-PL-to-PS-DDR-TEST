#!/usr/bin/env python3
import argparse
import struct
import sys
import time

try:
    import serial
except ImportError:
    serial = None


SYNC = b"\x55\xAA"
TYPE_START = 0x01
TYPE_ACK = 0x81
TYPE_RESULT = 0x82

STATUS = {
    0x00: "OK",
    0x01: "BUSY",
    0x02: "BAD_ALIGN",
    0x03: "BAD_SIZE",
    0x7F: "BAD_FRAME",
    0x80: "TEST_FAILED",
}


def parse_int(text):
    return int(text, 0)


def checksum(frame_type, payload):
    total = frame_type + len(payload) + sum(payload)
    return (-total) & 0xFF


def make_frame(frame_type, payload):
    return SYNC + bytes([frame_type, len(payload)]) + payload + bytes([checksum(frame_type, payload)])


def read_exact(port, count, deadline):
    data = bytearray()
    while len(data) < count:
        if time.monotonic() > deadline:
            raise TimeoutError("timeout while reading UART")
        chunk = port.read(count - len(data))
        if chunk:
            data.extend(chunk)
    return bytes(data)


def read_frame(port, timeout_s):
    deadline = time.monotonic() + timeout_s
    window = bytearray()
    while True:
        if time.monotonic() > deadline:
            raise TimeoutError("timeout waiting for frame sync")
        b = port.read(1)
        if not b:
            continue
        window += b
        window = window[-2:]
        if bytes(window) == SYNC:
            break

    header = read_exact(port, 2, deadline)
    frame_type = header[0]
    length = header[1]
    payload = read_exact(port, length, deadline)
    csum = read_exact(port, 1, deadline)[0]
    if ((frame_type + length + sum(payload) + csum) & 0xFF) != 0:
        raise ValueError("bad response checksum")
    return frame_type, payload


def decode_result(payload, clk_hz):
    if len(payload) != 58:
        raise ValueError(f"unexpected RESULT length {len(payload)}")
    status = payload[0]
    base, size = struct.unpack_from("<QI", payload, 1)
    flags = payload[13]
    seed = struct.unpack_from("<I", payload, 14)[0]
    wr_cycles, rd_cycles = struct.unpack_from("<QQ", payload, 18)
    errors, first_index = struct.unpack_from("<II", payload, 34)
    first_expected, first_actual = struct.unpack_from("<QQ", payload, 42)
    wr_seconds = wr_cycles / clk_hz if clk_hz and wr_cycles else 0.0
    rd_seconds = rd_cycles / clk_hz if clk_hz and rd_cycles else 0.0
    mib = size / (1024 * 1024)
    wr_mibps = mib / wr_seconds if wr_seconds else 0.0
    rd_mibps = mib / rd_seconds if rd_seconds else 0.0
    return {
        "status": status,
        "status_name": STATUS.get(status, f"0x{status:02X}"),
        "base_addr": base,
        "test_bytes": size,
        "flags": flags,
        "seed": seed,
        "write_cycles": wr_cycles,
        "read_cycles": rd_cycles,
        "write_seconds": wr_seconds,
        "read_seconds": rd_seconds,
        "write_mibps": wr_mibps,
        "read_mibps": rd_mibps,
        "error_count": errors,
        "first_mismatch_index": first_index,
        "first_mismatch_expected": first_expected,
        "first_mismatch_actual": first_actual,
        "pass": status == 0 and errors == 0,
    }


def print_result(result):
    print("PL-PS DDR TEST RESULT")
    print(f"status       : {result['status_name']} (0x{result['status']:02X})")
    print(f"base_addr    : 0x{result['base_addr']:016X}")
    print(f"test_bytes   : 0x{result['test_bytes']:08X} ({result['test_bytes']} bytes)")
    print(f"flags        : 0x{result['flags']:02X}")
    print(f"seed         : 0x{result['seed']:08X}")
    print(f"write_cycles : {result['write_cycles']}")
    print(f"read_cycles  : {result['read_cycles']}")
    print(f"write_time_s : {result['write_seconds']:.9f}")
    print(f"read_time_s  : {result['read_seconds']:.9f}")
    print(f"write_mibps  : {result['write_mibps']:.3f}")
    print(f"read_mibps   : {result['read_mibps']:.3f}")
    print(f"error_count  : {result['error_count']}")
    if result["error_count"]:
        print(f"first_index  : {result['first_mismatch_index']}")
        print(f"first_expect : 0x{result['first_mismatch_expected']:016X}")
        print(f"first_actual : 0x{result['first_mismatch_actual']:016X}")
    print(f"result       : {'PASS' if result['pass'] else 'FAIL'}")


def main():
    parser = argparse.ArgumentParser(description="Host script for PL-to-PS DDR UART test")
    parser.add_argument("--port", default="COM6")
    parser.add_argument("--baud", type=int, default=8_000_000)
    parser.add_argument("--clk-hz", type=float, default=200_000_000.0, help="PL clock frequency used for speed calculation")
    parser.add_argument("--base", type=parse_int, default=0x10000000)
    parser.add_argument("--bytes", dest="test_bytes", type=parse_int, default=0x01000000)
    parser.add_argument("--seed", type=parse_int, default=0x13579BDF)
    parser.add_argument("--flags", type=parse_int, default=0x03, help="0x01 write, 0x02 read/verify, 0x03 both")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--no-flush", action="store_true")
    args = parser.parse_args()

    if serial is None:
        print("pyserial is required: python -m pip install pyserial", file=sys.stderr)
        return 2

    payload = struct.pack("<QII B", args.base, args.test_bytes, args.seed, args.flags & 0xFF)
    frame = make_frame(TYPE_START, payload)

    with serial.Serial(args.port, args.baud, timeout=0.05) as port:
        if not args.no_flush:
            port.reset_input_buffer()
            port.reset_output_buffer()
        port.write(frame)
        port.flush()

        frame_type, ack_payload = read_frame(port, args.timeout)
        if frame_type != TYPE_ACK or len(ack_payload) != 1:
            raise RuntimeError(f"expected ACK, got type=0x{frame_type:02X}, len={len(ack_payload)}")
        ack = ack_payload[0]
        print(f"ACK: {STATUS.get(ack, f'0x{ack:02X}')} (0x{ack:02X})")
        if ack != 0:
            return 1

        while True:
            frame_type, payload = read_frame(port, args.timeout)
            if frame_type == TYPE_RESULT:
                result = decode_result(payload, args.clk_hz)
                print_result(result)
                return 0 if result["pass"] else 1
            print(f"Ignoring frame type 0x{frame_type:02X}")


if __name__ == "__main__":
    raise SystemExit(main())
