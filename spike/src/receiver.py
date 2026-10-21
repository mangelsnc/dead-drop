"""
receiver.py — DeadDrop receiver: QR frames → decrypted, verified file.

Pipeline
--------
    bootstrap QR (once)
      → accept_session()        (verify signature, derive shared key)
    for each scanned frame:
      → Frame.unpack()
      → filter by file_id       (ignore frames from other sessions)
      → decrypt payload (AEAD)  — bad frames are dropped, not fatal
      → LTDecoder.add_frame()   (belief propagation)
    when decoder.done:
      → reassemble, unpad to total_size
      → verify BLAKE2b against signed manifest
      → return plaintext
"""

from __future__ import annotations

from nacl.signing import VerifyKey

from crypto import (
    ReceiverKeypair, ReceiverSession, accept_session, DeadDropCryptoError,
)
from fountain import LTDecoder
from qrframe import Frame


class Receiver:
    def __init__(self, keypair: ReceiverKeypair):
        self.keypair = keypair
        self.session: ReceiverSession | None = None
        self.decoder: LTDecoder | None = None
        self.frames_dropped = 0
        self.frames_ignored_other_session = 0

    # -- bootstrap ---------------------------------------------------------

    def start_session(
        self,
        bootstrap_payload: bytes,
        sender_verify_key: VerifyKey | None = None,
    ) -> None:
        """Consume the one-time bootstrap QR and arm the decoder."""
        self.session = accept_session(
            bootstrap_payload, self.keypair, sender_verify_key,
        )
        h = self.session.header
        self.decoder = LTDecoder(k=h.chunk_count, chunk_size=h.chunk_size)

    # -- frame intake ------------------------------------------------------

    def feed_frame(self, frame_bytes: bytes) -> bool:
        """Process one scanned frame. True if it advanced decoding."""
        if self.session is None or self.decoder is None:
            raise RuntimeError("call start_session() first")
        if self.decoder.done:
            return False

        try:
            frame = Frame.unpack(frame_bytes)
        except (ValueError, Exception):
            self.frames_dropped += 1
            return False

        if frame.file_id != self.session.header.file_id:
            self.frames_ignored_other_session += 1
            return False

        try:
            payload = self.session.decrypt_chunk(frame.nonce, frame.payload)
        except DeadDropCryptoError:
            self.frames_dropped += 1
            return False

        return self.decoder.add_frame(frame.chunk_ids, payload)

    # -- result ------------------------------------------------------------

    @property
    def done(self) -> bool:
        return self.decoder is not None and self.decoder.done

    @property
    def progress(self) -> float:
        if self.decoder is None or self.decoder.k == 0:
            return 0.0
        return len(self.decoder.decoded) / self.decoder.k

    def finish(self) -> bytes:
        """Reassemble + verify + unpad. Raises if integrity check fails."""
        if not self.done:
            raise RuntimeError("transfer incomplete")
        assert self.session is not None and self.decoder is not None
        padded = self.decoder.reassemble()
        plaintext = padded[: self.session.header.total_size]
        if not self.session.verify_file(plaintext):
            raise DeadDropCryptoError("file integrity check failed (BLAKE2b mismatch)")
        return plaintext
