"""
fountain.py — Luby Transform (LT) fountain code for the QR channel.

Why a fountain code?
--------------------
The QR channel is a *one-way, lossy broadcast*: the emitter loops frames on
screen, the camera catches what it catches. There is no back-channel to say
"resend frame 42". Classic ARQ is impossible, and plain repetition wastes
bandwidth (coupon-collector problem: to receive K distinct frames by random
sampling you need ~K·ln(K) receptions — for K=100 that's ~460, i.e. 4.6×
overhead).

An LT code solves this: the emitter produces an *unbounded* stream of
encoded frames, each the XOR of a pseudo-random subset of the K source
chunks. The receiver only needs ~K·(1+ε) *any* frames (ε ≈ 5–10%) to decode
everything by belief propagation — no matter which frames were lost.

This module implements the encoder and the belief-propagation decoder with
an ideal-soliton-ish degree distribution (robust soliton simplified for the
spike; production would use Raptor/RaptorQ with precode, see DECISIONES.md).

Determinism
-----------
Both sides derive the chunk subset of frame `seq` from a shared PRNG seeded
with `seed`, so the frame header only carries `seed` + `seq`, not the full
chunk list — saving precious QR bytes. (In the spike we carry the explicit
chunk-id list for debuggability; the seeded variant is implemented and
tested in `compact=True` mode.)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Deterministic PRNG (splitmix32-style mixing + xorshift32)
# ---------------------------------------------------------------------------
#
# Ported 1:1 from app/lib/src/prng.dart. `random.Random` is NOT usable for
# cross-implementation determinism: its algorithm is CPython-specific and its
# seeding accepts arbitrary-precision ints (which is why the spike never
# showed the 32-bit-truncation bug the Dart side had). The generator below is
# fully specified in 32-bit arithmetic and produces the identical stream in
# both implementations — pinned by golden-vector tests on both sides.

_M32 = 0xFFFFFFFF


def _mul32(a: int, b: int) -> int:
    """Low 32 bits of a*b, computed so the result matches Dart exactly."""
    a_lo, a_hi = a & 0xFFFF, (a >> 16) & 0xFFFF
    b_lo, b_hi = b & 0xFFFF, (b >> 16) & 0xFFFF
    mid = ((a_hi * b_lo + a_lo * b_hi) & 0xFFFF) << 16
    return (a_lo * b_lo + mid) & _M32


def mix_seed(seed: int, seq: int) -> int:
    """splitmix32-style finalizer over seed + seq*phi. Bijective over 32 bits."""
    z = (seed + _mul32(seq, 0x9E3779B9)) & _M32
    z = _mul32(z ^ (z >> 16), 0x21F0AAAD)
    z = _mul32(z ^ (z >> 15), 0x735A2D97)
    return (z ^ (z >> 15)) & _M32


class DeterministicRandom:
    """xorshift32 (Marsaglia). State 0 is remapped (fixed point)."""

    def __init__(self, seed: int):
        s = seed & _M32
        self._state = s if s != 0 else 0x6D2B79F5

    def next_uint32(self) -> int:
        x = self._state
        x = (x ^ ((x << 13) & _M32)) & _M32
        x = (x ^ (x >> 17)) & _M32
        x = (x ^ ((x << 5) & _M32)) & _M32
        self._state = x
        return x

    def random(self) -> float:
        """Uniform double in [0, 1) — same name as random.Random for drop-in use."""
        return self.next_uint32() / 0x100000000

    def next_int(self, mx: int) -> int:
        """Uniform int in [0, mx) via multiply-divide (no modulo bias)."""
        if mx <= 0:
            raise ValueError("max must be positive")
        return (self.next_uint32() * mx) // 0x100000000


# ---------------------------------------------------------------------------
# Degree distribution (robust soliton, simplified)
# ---------------------------------------------------------------------------

def robust_soliton_cdf(k: int, c: float = 0.05, delta: float = 0.5) -> list[float]:
    """CDF of the robust soliton distribution over degrees 1..k.

    Ideal soliton ρ(d) plus a 'robust' spike τ(d) that guarantees enough
    low-degree packets to keep belief propagation alive, normalised.
    """
    rho = [0.0] * (k + 1)
    rho[1] = 1.0 / k
    for d in range(2, k + 1):
        rho[d] = 1.0 / (d * (d - 1))

    r = c * math.log(k / delta) * math.sqrt(k) if k > 1 else 1.0
    tau = [0.0] * (k + 1)
    # pivot must stay within [1, k] — for small k the raw k/r can exceed k
    pivot = max(1, min(int(k / r), k)) if r > 0 else 1
    for d in range(1, pivot):
        tau[d] = r / (d * k)
    if 1 <= pivot <= k:
        tau[pivot] += r * math.log(r / delta) / k if r > 0 else 0.0

    z = sum(rho) + sum(tau)
    cdf, acc = [], 0.0
    for d in range(1, k + 1):
        acc += (rho[d] + tau[d]) / z
        cdf.append(acc)
    cdf[-1] = 1.0
    return cdf


def sample_degree(rng, cdf: list[float]) -> int:
    u = rng.random()
    for d, p in enumerate(cdf, start=1):
        if u <= p:
            return d
    return len(cdf)


# ---------------------------------------------------------------------------
# Encoder
# ---------------------------------------------------------------------------

class LTEncoder:
    """Turns K source chunks into an endless stream of encoded frames."""

    def __init__(self, chunks: list[bytes]):
        if not chunks:
            raise ValueError("need at least one chunk")
        self.k = len(chunks)
        self.chunk_size = len(chunks[0])
        assert all(len(c) == self.chunk_size for c in chunks), "chunks must be padded to equal size"
        self.chunks = chunks
        self.cdf = robust_soliton_cdf(self.k)

    def make_frame(self, seq: int, seed: int) -> tuple[list[int], bytes]:
        """Produce encoded frame #(seq) under PRNG seed.

        Returns (chunk_ids, payload) where payload = XOR of the chosen
        chunks. Deterministic for a given (seq, seed).
        """
        rng = DeterministicRandom(mix_seed(seed, seq))
        degree = min(sample_degree(rng, self.cdf), self.k)
        # Fisher-Yates on the identity permutation, driven by the
        # deterministic generator. random.Random.sample is not usable here:
        # its algorithm is CPython-specific and not portable to Dart.
        indices = list(range(self.k))
        for i in range(self.k - 1, 0, -1):
            j = rng.next_int(i + 1)
            indices[i], indices[j] = indices[j], indices[i]
        chunk_ids = sorted(indices[:degree])

        payload = bytearray(self.chunk_size)
        for cid in chunk_ids:
            src = self.chunks[cid]
            for i in range(self.chunk_size):
                payload[i] ^= src[i]
        return chunk_ids, bytes(payload)


# ---------------------------------------------------------------------------
# Decoder (belief propagation / peeling)
# ---------------------------------------------------------------------------

@dataclass
class LTDecoder:
    """Accumulates encoded frames until all K source chunks are recovered."""

    k: int
    chunk_size: int
    # chunk_id -> recovered plaintext chunk
    decoded: dict[int, bytes] = field(default_factory=dict)
    # list of [set_of_chunk_ids, payload]
    pending: list[list] = field(default_factory=list)
    frames_received: int = 0
    frames_useful: int = 0

    @property
    def done(self) -> bool:
        return len(self.decoded) == self.k

    @property
    def efficiency(self) -> float:
        """Useful frames / received frames (1.0 = no redundancy wasted)."""
        return self.frames_useful / self.frames_received if self.frames_received else 0.0

    def add_frame(self, chunk_ids: list[int], payload: bytes) -> bool:
        """Feed one encoded frame. Returns True if it made progress."""
        self.frames_received += 1
        ids = set(chunk_ids)
        buf = bytearray(payload)

        # Peel with already-known chunks
        for cid in list(ids):
            if cid in self.decoded:
                known = self.decoded[cid]
                for i in range(self.chunk_size):
                    buf[i] ^= known[i]
                ids.discard(cid)

        if not ids:
            return False  # fully redundant frame

        if len(ids) == 1:
            self._resolve(ids.pop(), bytes(buf))
            return True

        self.pending.append([ids, bytes(buf)])
        return False

    def _resolve(self, cid: int, chunk: bytes) -> None:
        if cid in self.decoded:
            return
        self.decoded[cid] = chunk
        self.frames_useful += 1
        # Cascade: try to peel pending frames with this new chunk
        changed = True
        while changed:
            changed = False
            still_pending = []
            for ids, buf in self.pending:
                ids = set(ids)
                buf = bytearray(buf)
                for known_id in list(ids):
                    if known_id in self.decoded:
                        known = self.decoded[known_id]
                        for i in range(self.chunk_size):
                            buf[i] ^= known[i]
                        ids.discard(known_id)
                if not ids:
                    changed = True  # frame became fully redundant
                    continue
                if len(ids) == 1:
                    self.decoded[ids.pop()] = bytes(buf)
                    self.frames_useful += 1
                    changed = True
                    continue
                still_pending.append([ids, bytes(buf)])
            self.pending = still_pending

    def reassemble(self) -> bytes:
        """Return the K decoded chunks concatenated (still padded)."""
        if not self.done:
            raise RuntimeError(f"decode incomplete: {len(self.decoded)}/{self.k}")
        return b"".join(self.decoded[i] for i in range(self.k))
