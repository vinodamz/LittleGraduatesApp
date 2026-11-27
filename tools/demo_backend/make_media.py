"""Generate a synthetic gallery PNG using only Python's standard library."""
import struct
import sys
import zlib
from pathlib import Path


def png_bytes(width=640, height=480):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend((220, 75, 125) if (x // 80 + y // 80) % 2 else (245, 225, 180))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    Path(sys.argv[1]).write_bytes(png_bytes())
