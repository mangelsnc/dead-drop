"""
crypto.py — E2E encryption layer for DeadDrop (spike).

Design goals
------------
* Real libsodium primitives (via PyNaCl) — the exact same algorithms the
  production Flutter app will use through `sodium_libs`, so spike numbers
  and security properties carry over 1:1.
* Anonymous, one-shot, forward-secret sessions: the sender generates an
  *ephemeral* X25519 keypair per transfer and the receiver publishes a
  short-lived public key (out of band — typed, shown as a static QR, or
  pre-shared between the two people meeting). Nothing is stored.
* Authenticated encryption with associated data (AEAD): every chunk is
  individually authenticated, so a flipped QR frame is detected and
  discarded instead of corrupting the file.

Primitives (libsodium)
----------------------
* Key exchange : X25519          (crypto_box / crypto_kx)
* Cipher       : XSalsa20-Poly1305 (crypto_secretbox / crypto_box)
* Signatures   : Ed25519         (crypto_sign) — sender authenticity
* Hash         : BLAKE2b         (file manifest integrity)

Wire format
-----------
The transfer is split in two layers:

1. **Session bootstrap** (one small static QR or typed code):
       MAGIC(2) || version(1) || sender_eph_pk(32) || receiver_pk(32)
       || file_id(8) || total_size(4) || chunk_count(2) || chunk_size(2)
       || blake2b(manifest)(32) || Ed25519_signature(64)

2. **Data frames** (the animated QR sequence):
       MAGIC(2) || version(1) || file_id(8) || frame_seq(4)
       || seed(4) || degree(1) || chunk_ids(variable) || nonce(24)
       || ciphertext+tag(variable)

Everything is encrypted with a session key derived from
X25519(sender_eph_sk, receiver_pk), so only the intended receiver can
decrypt — and each transfer uses fresh keys (forward secrecy).
"""

from __future__ import annotations

import hashlib
import hmac
import struct
from dataclasses import dataclass

from nacl.public import PrivateKey, PublicKey, Box
from nacl.signing import SigningKey, VerifyKey
from nacl.utils import random as nacl_random
from nacl.exceptions import CryptoError

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MAGIC = b"DD"                # protocol magic, 2 bytes
VERSION = 1                  # spike protocol version
NONCE_SIZE = 24              # XSalsa20-Poly1305 nonce
TAG_SIZE = 16                # Poly1305 tag (appended to ciphertext)
PK_SIZE = 32                 # X25519 public key
SIG_SIZE = 64                # Ed25519 signature
HASH_SIZE = 32               # BLAKE2b-256 (libsodium crypto_generichash)
FILE_ID_SIZE = 8


class DeadDropCryptoError(Exception):
    """Raised on any cryptographic verification failure."""


# ---------------------------------------------------------------------------
# Identities
# ---------------------------------------------------------------------------

@dataclass
class Identity:
    """Long-term-ish Ed25519 signing identity (per install, per user).

    In the spike this is generated in-memory; the app would store it in the
    OS keychain. It authenticates the *sender*, so the receiver knows the
    file comes from the person standing in front of them.
    """
    signing_key: SigningKey

    @classmethod
    def generate(cls) -> "Identity":
        return cls(SigningKey.generate())

    @property
    def verify_key(self) -> VerifyKey:
        return self.signing_key.verify_key

    def sign(self, data: bytes) -> bytes:
        return self.signing_key.sign(data).signature


@dataclass
class ReceiverKeypair:
    """Ephemeral X25519 keypair the receiver shows to the sender."""
    private_key: PrivateKey

    @classmethod
    def generate(cls) -> "ReceiverKeypair":
        return cls(PrivateKey.generate())

    @property
    def public_key(self) -> PublicKey:
        return self.private_key.public_key


# ---------------------------------------------------------------------------
# Session bootstrap
# ---------------------------------------------------------------------------

@dataclass
class SessionHeader:
    """Everything the receiver needs to start decoding — sent once."""
    sender_eph_pk: bytes       # 32  ephemeral X25519 public key
    receiver_pk: bytes         # 32  receiver's public key (binding)
    file_id: bytes             # 8   random transfer id
    total_size: int            # 4   plaintext file size in bytes
    chunk_count: int           # 2   number of source chunks (K)
    chunk_size: int            # 2   plaintext bytes per chunk
    manifest_hash: bytes       # 32  BLAKE2b-256 of the plaintext file
    signature: bytes           # 64  Ed25519 sig over all previous fields

    STRUCT = struct.Struct(">2sB32s32s8sIHH32s64s")

    def pack(self) -> bytes:
        return self.STRUCT.pack(
            MAGIC, VERSION,
            self.sender_eph_pk, self.receiver_pk, self.file_id,
            self.total_size, self.chunk_count, self.chunk_size,
            self.manifest_hash, self.signature,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "SessionHeader":
        (magic, version, spk, rpk, fid, total, cc, cs, mh, sig) = \
            cls.STRUCT.unpack(data)
        if magic != MAGIC:
            raise DeadDropCryptoError("bad magic")
        if version != VERSION:
            raise DeadDropCryptoError(f"unsupported version {version}")
        return cls(spk, rpk, fid, total, cc, cs, mh, sig)

    def signed_payload(self) -> bytes:
        """The exact bytes covered by the signature."""
        return self.STRUCT.pack(
            MAGIC, VERSION,
            self.sender_eph_pk, self.receiver_pk, self.file_id,
            self.total_size, self.chunk_count, self.chunk_size,
            self.manifest_hash, b"\x00" * SIG_SIZE,
        )[:-SIG_SIZE]


def open_session(
    plaintext: bytes,
    chunk_size: int,
    receiver_pk: PublicKey,
    sender_identity: Identity,
) -> tuple["Session", SessionHeader]:
    """Sender side: build the encrypted session + bootstrap header."""
    eph_sk = PrivateKey.generate()
    box = Box(eph_sk, receiver_pk)

    file_id = nacl_random(FILE_ID_SIZE)
    manifest_hash = hashlib.blake2b(plaintext, digest_size=32).digest()
    chunk_count = (len(plaintext) + chunk_size - 1) // chunk_size

    header = SessionHeader(
        sender_eph_pk=bytes(eph_sk.public_key),
        receiver_pk=bytes(receiver_pk),
        file_id=file_id,
        total_size=len(plaintext),
        chunk_count=chunk_count,
        chunk_size=chunk_size,
        manifest_hash=manifest_hash,
        signature=b"\x00" * SIG_SIZE,  # placeholder, signed below
    )
    header.signature = sender_identity.sign(header.signed_payload())

    session = Session(box=box, file_id=file_id,
                      chunk_count=chunk_count, chunk_size=chunk_size,
                      plaintext=plaintext)
    return session, header


def accept_session(
    header_bytes: bytes,
    receiver_keypair: ReceiverKeypair,
    sender_verify_key: VerifyKey | None = None,
) -> "ReceiverSession":
    """Receiver side: parse + verify the bootstrap header."""
    header = SessionHeader.unpack(header_bytes)

    if header.receiver_pk != bytes(receiver_keypair.public_key):
        raise DeadDropCryptoError("session not addressed to this receiver")

    if sender_verify_key is not None:
        try:
            sender_verify_key.verify(header.signed_payload(), header.signature)
        except CryptoError as e:
            raise DeadDropCryptoError("sender signature invalid") from e

    box = Box(receiver_keypair.private_key, PublicKey(header.sender_eph_pk))
    return ReceiverSession(box=box, header=header)


# ---------------------------------------------------------------------------
# Chunk encryption
# ---------------------------------------------------------------------------

class Session:
    """Sender-side encrypted session: turns plaintext chunks into frames."""

    def __init__(self, box: Box, file_id: bytes, chunk_count: int,
                 chunk_size: int, plaintext: bytes):
        self.box = box
        self.file_id = file_id
        self.chunk_count = chunk_count
        self.chunk_size = chunk_size
        # Pre-split into source chunks (padded last chunk)
        self.chunks: list[bytes] = [
            plaintext[i * chunk_size:(i + 1) * chunk_size].ljust(chunk_size, b"\x00")
            for i in range(chunk_count)
        ]

    def encrypt_chunk(self, chunk_id: int, nonce: bytes | None = None) -> tuple[bytes, bytes]:
        """Encrypt one source chunk. Returns (nonce, ciphertext+tag)."""
        if not 0 <= chunk_id < self.chunk_count:
            raise ValueError("chunk_id out of range")
        nonce = nonce or nacl_random(NONCE_SIZE)
        ct = self.box.encrypt(self.chunks[chunk_id], nonce).ciphertext
        return nonce, ct


class ReceiverSession:
    """Receiver-side session: decrypts frames back into chunks."""

    def __init__(self, box: Box, header: SessionHeader):
        self.box = box
        self.header = header

    def decrypt_chunk(self, nonce: bytes, ciphertext: bytes) -> bytes:
        try:
            return self.box.decrypt(ciphertext, nonce)
        except CryptoError as e:
            raise DeadDropCryptoError("chunk authentication failed") from e

    def verify_file(self, plaintext: bytes) -> bool:
        """Final integrity check against the signed manifest hash."""
        digest = hashlib.blake2b(plaintext, digest_size=32).digest()
        return hmac.compare_digest(digest, self.header.manifest_hash)
