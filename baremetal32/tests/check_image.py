#!/usr/bin/env python3
"""Static layout checks for the BIOS/IDE image (not a substitute for QEMU)."""
import pathlib
import sys

SECTOR = 512
STAGE2_SECTORS = 8
KERNEL_SECTORS = 64
EXPECTED_SIZE = SECTOR * (1 + STAGE2_SECTORS + KERNEL_SECTORS)


def fail(message: str) -> None:
    raise SystemExit(f"image check failed: {message}")


if len(sys.argv) != 2:
    fail("usage: check_image.py path/to/os.img")
image_path = pathlib.Path(sys.argv[1])
if not image_path.is_file():
    fail(f"missing image: {image_path}")
data = image_path.read_bytes()
if len(data) != EXPECTED_SIZE:
    fail(f"expected {EXPECTED_SIZE} bytes ({EXPECTED_SIZE // SECTOR} sectors), got {len(data)}")
if data[510:512] != b"\x55\xaa":
    fail("MBR signature is not 55 AA at offsets 510..511")
if data[:446] == bytes(446):
    fail("MBR bootstrap area is empty")
stage2 = data[SECTOR:SECTOR * (1 + STAGE2_SECTORS)]
if len(stage2) != 4096 or stage2 == bytes(4096):
    fail("stage2 must occupy exactly sectors 1..8")
kernel = data[SECTOR * (1 + STAGE2_SECTORS):]
if len(kernel) != KERNEL_SECTORS * SECTOR or kernel == bytes(len(kernel)):
    fail("kernel load area must be non-empty and exactly 64 sectors")
print(f"image layout OK: {len(data)} bytes; MBR=512; stage2=4096; kernel-window=32768")
