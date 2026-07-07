#!/usr/bin/env python3
"""UART debug capture for the PL-PS DDR tester.

Opens the PL UART at the tester baud rate and continuously prints raw bytes
with timestamps. Useful as a low-level debug tool when the main test script
is not producing expected frames, or when watching tester traffic during
JTAG boot.

Modes:
  python tools/uart_capture.py --port COM6            # passive capture
  python tools/uart_capture.py --port COM6 --query    # send QUERY_CONFIG, show reply
  python tools/uart_capture.py --port COM6 --send-hex 55AA020087   # send raw bytes
"""
import argparse
import datetime
import sys
import time

try:
    import serial
except ImportError:
    print("pyserial not installed: python -m pip install pyserial")
    sys.exit(1)

SYNC = b"\x55\xAA"
TYPE_QUERY_CONFIG = 0x02


def checksum(frame_type, payload):
    total = frame_type + len(payload) + sum(payload)
    return (-total) & 0xFF


def make_query_frame():
    payload = b""
    return SYNC + bytes([TYPE_QUERY_CONFIG, len(payload)]) + payload + bytes([checksum(TYPE_QUERY_CONFIG, payload)])


def hexdump(data):
    hexs = " ".join(f"{b:02X}" for b in data)
    asci = "".join(chr(b) if 32 <= b < 127 else "." for b in data)
    return f"{hexs}  |{asci}|"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM6")
    ap.add_argument("--baud", type=int, default=8000000)
    ap.add_argument("--timeout", type=float, default=0.2, help="per-read timeout (s)")
    ap.add_argument("--duration", type=float, default=0.0, help="capture duration (s), 0=forever")
    ap.add_argument("--query", action="store_true", help="send QUERY_CONFIG frame then capture")
    ap.add_argument("--send-hex", default=None, help="send raw hex bytes then capture")
    ap.add_argument("--flush", action="store_true", help="flush RX buffer on open")
    args = ap.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=args.timeout)
    except Exception as e:
        print(f"ERROR opening {args.port}: {e}")
        sys.exit(1)

    print(f"[{ts()}] opened {args.port} @ {args.baud} baud")
    if args.flush:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        print(f"[{ts()}] buffers flushed")

    if args.send_hex:
        raw = bytes.fromhex(args.send_hex)
        ser.write(raw)
        print(f"[{ts()}] sent {len(raw)} bytes: {hexdump(raw)}")

    if args.query:
        frame = make_query_frame()
        ser.reset_input_buffer()
        ser.write(frame)
        print(f"[{ts()}] sent QUERY_CONFIG: {hexdump(frame)}")

    start = time.monotonic()
    buf = bytearray()
    try:
        while True:
            if args.duration > 0 and (time.monotonic() - start) > args.duration:
                break
            chunk = ser.read(64)
            if chunk:
                buf.extend(chunk)
                print(f"[{ts()}] +{len(chunk):3d}  {hexdump(chunk)}")
                sys.stdout.flush()
    except KeyboardInterrupt:
        print(f"\n[{ts()}] stopped by user")
    finally:
        ser.close()

    if buf:
        print(f"\n[{ts()}] total captured: {len(buf)} bytes")
        print(hexdump(bytes(buf)))


def ts():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


if __name__ == "__main__":
    main()
