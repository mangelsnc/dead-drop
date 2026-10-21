"""
test_spike.py — unit + integration tests for the DeadDrop spike.

Run: .venv/bin/python -m pytest test_spike.py -v
(or plain: .venv/bin/python test_spike.py)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from crypto import (
    Identity, ReceiverKeypair, open_session, accept_session,
    DeadDropCryptoError, SessionHeader,
)
from fountain import LTEncoder, LTDecoder, robust_soliton_cdf
from qrframe import Frame, frame_to_qr_image, QR_CAPACITY
from emitter import Emitter
from receiver import Receiver
from simulator import run_transfer, ChannelParams


# ---------------------------------------------------------------------------
# crypto
# ---------------------------------------------------------------------------

def test_session_roundtrip():
    pt = b"hello air gap" * 100
    rk = ReceiverKeypair.generate()
    ident = Identity.generate()
    sess, header = open_session(pt, 256, rk.public_key, ident)

    rs = accept_session(header.pack(), rk, ident.verify_key)
    assert rs.header.total_size == len(pt)
    assert rs.header.chunk_count == sess.chunk_count

    nonce, ct = sess.encrypt_chunk(0)
    dec = rs.decrypt_chunk(nonce, ct)
    assert dec == sess.chunks[0]


def test_wrong_receiver_rejected():
    pt = b"secret"
    rk1, rk2 = ReceiverKeypair.generate(), ReceiverKeypair.generate()
    _, header = open_session(pt, 256, rk1.public_key, Identity.generate())
    try:
        accept_session(header.pack(), rk2)
        assert False, "should have raised"
    except DeadDropCryptoError:
        pass


def test_bad_signature_rejected():
    pt = b"secret"
    rk = ReceiverKeypair.generate()
    id_a, id_b = Identity.generate(), Identity.generate()
    _, header = open_session(pt, 256, rk.public_key, id_a)
    try:
        accept_session(header.pack(), rk, id_b.verify_key)  # wrong signer
        assert False
    except DeadDropCryptoError:
        pass


def test_tampered_chunk_rejected():
    pt = b"x" * 512
    rk = ReceiverKeypair.generate()
    sess, header = open_session(pt, 256, rk.public_key, Identity.generate())
    rs = accept_session(header.pack(), rk)
    nonce, ct = sess.encrypt_chunk(0)
    bad = bytearray(ct); bad[0] ^= 1
    try:
        rs.decrypt_chunk(nonce, bytes(bad))
        assert False
    except DeadDropCryptoError:
        pass


def test_manifest_hash_matches_dart_blake2b():
    """Cross-platform known-answer test for the manifest hash.

    The manifest hash is BLAKE2b-256 (libsodium crypto_generichash in the
    Dart app, hashlib.blake2b(digest_size=32) here). These vectors are also
    asserted in app/test/integration_test.dart — matching values on both
    sides prove the spike and the app produce identical manifest hashes.
    """
    import hashlib

    vectors = {
        b"": "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8",
        b"hello air gap": "0c8708c306b81c0af1073ef22378f781d3ecdd9acb0404da866dc1891cd6d858",
        bytes(range(256)): "39a7eb9fedc19aabc83425c6755dd90e6f9d0c804964a1f4aaeea3b9fb599835",
    }
    for data, expected_hex in vectors.items():
        assert hashlib.blake2b(data, digest_size=32).hexdigest() == expected_hex, data

    # End-to-end: open_session must embed the BLAKE2b manifest hash.
    pt = b"verify me end to end"
    rk = ReceiverKeypair.generate()
    sess, header = open_session(pt, 256, rk.public_key, Identity.generate())
    assert header.manifest_hash == hashlib.blake2b(pt, digest_size=32).digest()

    rs = accept_session(header.pack(), rk)
    assert rs.verify_file(pt) is True
    tampered = bytearray(pt); tampered[0] ^= 1
    assert rs.verify_file(bytes(tampered)) is False


# ---------------------------------------------------------------------------
# fountain
# ---------------------------------------------------------------------------

def test_lt_roundtrip_no_loss():
    chunks = [bytes([i]) * 64 for i in range(20)]
    enc = LTEncoder(chunks)
    dec = LTDecoder(k=20, chunk_size=64)
    seq = 0
    while not dec.done and seq < 500:
        ids, payload = enc.make_frame(seq, seed=7)
        dec.add_frame(ids, payload)
        seq += 1
    assert dec.done
    assert dec.reassemble() == b"".join(chunks)
    # Should complete with modest overhead (< 3x even for tiny K)
    assert dec.frames_received <= 60


def test_lt_deterministic_frames():
    chunks = [b"abcd" * 16] * 10
    enc = LTEncoder(chunks)
    ids1, p1 = enc.make_frame(5, seed=99)
    ids2, p2 = enc.make_frame(5, seed=99)
    assert ids1 == ids2 and p1 == p2


def test_robust_soliton_normalized():
    cdf = robust_soliton_cdf(50)
    assert abs(cdf[-1] - 1.0) < 1e-9
    assert all(b >= a for a, b in zip(cdf, cdf[1:]))  # monotonic


# ---------------------------------------------------------------------------
# qrframe
# ---------------------------------------------------------------------------

def test_frame_pack_unpack():
    f = Frame(file_id=b"12345678", seq=42, seed=7,
              chunk_ids=[1, 5, 9], nonce=b"n" * 24, payload=b"PAYLOAD")
    f2 = Frame.unpack(f.pack())
    assert f2.seq == 42 and f2.chunk_ids == [1, 5, 9] and f2.payload == b"PAYLOAD"


def test_frame_fits_qr():
    """A 512-byte-chunk frame must fit in a real QR at EC-M."""
    rk = ReceiverKeypair.generate()
    em = Emitter(b"y" * 2048, rk, chunk_size=512)
    packed = em.next_frame().pack()
    img = frame_to_qr_image(packed, ec="M")
    assert img.width > 0
    # v25-M holds 1003 bytes; our frame should be well under
    assert len(packed) <= QR_CAPACITY[25]["M"]


# ---------------------------------------------------------------------------
# end-to-end
# ---------------------------------------------------------------------------

def test_end_to_end_clean_channel():
    data = os.urandom(4096)
    res = run_transfer(data, chunk_size=512,
                       channel=ChannelParams(frame_loss=0.0, decode_fail=0.0, corrupt=0.0))
    assert res.completed and res.integrity_ok


def test_end_to_end_lossy_channel():
    data = os.urandom(4096)
    res = run_transfer(data, chunk_size=512,
                       channel=ChannelParams(frame_loss=0.3, decode_fail=0.05, corrupt=0.01),
                       rng_seed=123)
    assert res.completed and res.integrity_ok


def test_corruption_never_corrupts_file():
    """With AEAD, bit flips cause drops — never silent corruption."""
    data = os.urandom(2048)
    res = run_transfer(data, chunk_size=256,
                       channel=ChannelParams(frame_loss=0.0, decode_fail=0.0, corrupt=0.5),
                       rng_seed=7)
    assert not res.completed or res.integrity_ok


if __name__ == "__main__":
    # Run without pytest
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except Exception as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e}")
    print(f"\n{len(fns) - failed}/{len(fns)} tests passed")
    sys.exit(1 if failed else 0)
