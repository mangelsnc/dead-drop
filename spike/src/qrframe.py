"""
qrframe.py — QR frame packing, rendering and parsing for DeadDrop.

A "frame" is one QR code in the animated sequence. This module owns the
binary wire format and the QR encode/decode glue, so emitter and receiver
always agree on the bytes on the wire.

Frame layout (binary, big-endian):
    MAGIC(2)      "DD"
    version(1)    protocol version
    file_id(8)    random transfer id (lets receiver ignore other sessions)
    frame_seq(4)  monotonically increasing frame number
    seed(4)       PRNG seed for this frame's chunk selection
    degree(2)     number of chunk ids
    chunk_ids     degree × 2 bytes each
    nonce(24)     XSalsa20-Poly1305 nonce for the payload
    payload(N)    encrypted+tagged XOR chunk (chunk_size + 16 bytes)

QR parameters
-------------
* Mode: **byte (8-bit)** — arbitrary ciphertext, no alphanumeric tricks.
* Error correction: **M (15%)** by default — sweet spot between damage
  resistance and capacity for a clean screen→camera path; L/M/Q/H are
  benchmarked in the simulator.
* Version: auto-fit up to **v40** (2,953 bytes at EC-L, 1,852 at EC-M,
  1,273 at EC-Q, 863 at EC-H). The spike defaults to a conservative
  payload per frame so even mid-range phones scan reliably at 10–15 fps.
"""

from __future__ import annotations

import io
import struct
from dataclasses import dataclass

import qrcode
from qrcode.constants import (
    ERROR_CORRECT_L, ERROR_CORRECT_M, ERROR_CORRECT_Q, ERROR_CORRECT_H,
)
from PIL import Image

from crypto import MAGIC, VERSION, NONCE_SIZE, FILE_ID_SIZE

EC_LEVELS = {"L": ERROR_CORRECT_L, "M": ERROR_CORRECT_M,
             "Q": ERROR_CORRECT_Q, "H": ERROR_CORRECT_H}

# QR byte-mode capacity per version at each EC level (versions 1..40).
# Source: ISO/IEC 18004 tables. Only the versions we might plausibly use
# for screen→camera (v10..v40) are listed to keep the table small.
QR_CAPACITY = {
    # version: {EC: byte-mode capacity}
    10: {"L": 346, "M": 274, "Q": 216, "H": 154},
    15: {"L": 523, "M": 415, "Q": 295, "H": 223},
    20: {"L": 861, "M": 669, "Q": 485, "H": 367},
    25: {"L": 1279, "M": 1003, "Q": 733, "H": 559},
    30: {"L": 1735, "M": 1371, "Q": 1007, "H": 775},
    35: {"L": 2303, "M": 1815, "Q": 1343, "H": 1039},
    40: {"L": 2953, "M": 2331, "Q": 1663, "H": 1273},
}

FRAME_HEADER = struct.Struct(">2sB8sIIH")   # magic, ver, file_id, seq, seed, degree
CHUNK_ID = struct.Struct(">H")


@dataclass
class Frame:
    file_id: bytes
    seq: int
    seed: int
    chunk_ids: list[int]
    nonce: bytes
    payload: bytes

    def pack(self) -> bytes:
        out = bytearray()
        out += FRAME_HEADER.pack(MAGIC, VERSION, self.file_id,
                                 self.seq, self.seed, len(self.chunk_ids))
        for cid in self.chunk_ids:
            out += CHUNK_ID.pack(cid)
        out += self.nonce
        out += self.payload
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> "Frame":
        magic, version, file_id, seq, seed, degree = \
            FRAME_HEADER.unpack(data[:FRAME_HEADER.size])
        if magic != MAGIC or version != VERSION:
            raise ValueError("not a DeadDrop frame")
        off = FRAME_HEADER.size
        chunk_ids = []
        for _ in range(degree):
            (cid,) = CHUNK_ID.unpack(data[off:off + 2])
            chunk_ids.append(cid)
            off += 2
        nonce = data[off:off + NONCE_SIZE]
        off += NONCE_SIZE
        payload = data[off:]
        return cls(file_id=file_id, seq=seq, seed=seed,
                   chunk_ids=chunk_ids, nonce=nonce, payload=payload)


def frame_to_qr_image(frame_bytes: bytes, ec: str = "M",
                      box_size: int = 8, border: int = 2) -> Image.Image:
    """Render one frame as a QR PIL image (RGB)."""
    qr = qrcode.QRCode(
        version=None,  # auto-fit
        error_correction=EC_LEVELS[ec],
        box_size=box_size,
        border=border,
    )
    qr.add_data(frame_bytes)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    return img.convert("RGB")


def qr_capacity_at(version: int, ec: str) -> int:
    """Byte-mode capacity for a given QR version + EC level."""
    versions = sorted(QR_CAPACITY)
    # nearest known version at or below
    v = max((x for x in versions if x <= version), default=versions[0])
    return QR_CAPACITY[v][ec]
