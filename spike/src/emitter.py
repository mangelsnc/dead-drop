"""
emitter.py — DeadDrop sender: file → encrypted fountain-coded QR frames.

Pipeline
--------
    file bytes
      → open_session()          (ephemeral X25519 + signed manifest header)
      → split into K chunks     (fixed chunk_size, last one padded)
      → LTEncoder               (endless XOR-combined frames)
      → per frame: encrypt payload with session key (AEAD)
      → pack into binary frame
      → render as QR image

The emitter exposes `next_frame()` — a pull API the UI drives at the
display refresh rate (e.g. 10–15 fps). Frames loop forever; the receiver
stops when the fountain decoder completes.
"""

from __future__ import annotations

import itertools
from pathlib import Path

from nacl.utils import random as nacl_random

from crypto import Identity, ReceiverKeypair, Session, SessionHeader, open_session
from fountain import LTEncoder
from qrframe import Frame, frame_to_qr_image


class Emitter:
    def __init__(
        self,
        file_bytes: bytes,
        receiver_keypair: ReceiverKeypair,
        sender_identity: Identity | None = None,
        chunk_size: int = 512,
    ):
        self.identity = sender_identity or Identity.generate()
        self.session: Session
        self.header: SessionHeader
        self.session, self.header = open_session(
            plaintext=file_bytes,
            chunk_size=chunk_size,
            receiver_pk=receiver_keypair.public_key,
            sender_identity=self.identity,
        )
        self.fountain = LTEncoder(self.session.chunks)
        self._seq = itertools.count(0)
        # One PRNG seed per transfer — frames derive from it deterministically
        self.transfer_seed = int.from_bytes(nacl_random(4), "big")

    # -- bootstrap ---------------------------------------------------------

    def bootstrap_qr_payload(self) -> bytes:
        """Bytes for the single static QR that starts the session."""
        return self.header.pack()

    # -- frame stream ------------------------------------------------------

    def next_frame(self) -> Frame:
        """Produce the next encrypted fountain frame."""
        seq = next(self._seq)
        chunk_ids, xored = self.fountain.make_frame(seq, self.transfer_seed)
        # Encrypt the XORed payload as one AEAD unit.
        # Box.encrypt returns an EncryptedMessage with .nonce and .ciphertext.
        enc = self.session.box.encrypt(xored)
        nonce, ct = enc.nonce, enc.ciphertext
        return Frame(
            file_id=self.session.file_id,
            seq=seq,
            seed=self.transfer_seed,
            chunk_ids=chunk_ids,
            nonce=nonce,
            payload=ct,
        )

    def next_frame_qr(self, ec: str = "M"):
        """Next frame rendered as a QR PIL image."""
        return frame_to_qr_image(self.next_frame().pack(), ec=ec)


def emit_file(
    path: str | Path,
    receiver_keypair: ReceiverKeypair,
    out_dir: str | Path,
    n_frames: int,
    chunk_size: int = 512,
    ec: str = "M",
) -> dict:
    """CLI helper: read a file, emit N QR frames as PNGs into out_dir.

    Returns stats used by the simulator/report.
    """
    data = Path(path).read_bytes()
    em = Emitter(data, receiver_keypair, chunk_size=chunk_size)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    (out / "00_bootstrap.bin").write_bytes(em.bootstrap_qr_payload())
    sizes = []
    for i in range(n_frames):
        frame = em.next_frame()
        img = frame_to_qr_image(frame.pack(), ec=ec)
        img.save(out / f"frame_{i:05d}.png")
        sizes.append(len(frame.pack()))

    return {
        "file_bytes": len(data),
        "chunk_size": chunk_size,
        "chunk_count": em.session.chunk_count,
        "frames_emitted": n_frames,
        "frame_bytes_min": min(sizes),
        "frame_bytes_max": max(sizes),
        "frame_bytes_avg": sum(sizes) / len(sizes),
        "ec_level": ec,
    }
