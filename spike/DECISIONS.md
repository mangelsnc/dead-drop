# DECISIONS.md — Technical Spike: Animated QR + E2E Encryption

> **Status:** validated by simulation. 12/12 tests passing. Metrics in
> `spike/src/benchmark_results.json`.
>
> **Question this spike answers:** can an encrypted file cross from
> a screen to a camera, without network, at a speed usable by a non-technical
> person? **Answer: yes — ~4 KB/s effective, 8 KB in ~2 seconds.**

---

## 1. E2E Encryption: libsodium, ephemeral X25519 + XSalsa20-Poly1305 + Ed25519

**Decision:** use libsodium (PyNaCl in the spike, `sodium_libs` in Flutter)
with this concrete stack:

| Piece | Primitive | Why |
|---|---|---|
| Key exchange | **X25519** (`crypto_box`) | Ephemeral key per transfer → *forward secrecy* for free. Nothing to store, nothing to leak later. |
| Symmetric encryption | **XSalsa20-Poly1305** (AEAD) | Each chunk is authenticated: a damaged frame is **detected and discarded**, never silently corrupts the file. 192-bit nonce → random without collision risk. |
| Manifest signature | **Ed25519** | The receiver knows the file comes from the person in front of them (sender authenticity), not just that "someone encrypted it". |
| Final integrity | **SHA-256** of plaintext, signed | End-to-end verification independent of transport. |

**Why libsodium and not something else:**
- It's the reference in applied crypto: API hard to misuse, no
  dangerous legacy algorithms to choose by mistake.
- Same backend on all Flutter targets via `sodium_libs`
  (iOS/Android/desktop) → the spike measures what the product will do.
- Audited, mature, and its "no options" philosophy fits the requirement
  of an app for non-technical public: we choose, the user doesn't.

**Discarded alternatives:**
- *Hand-rolled AES-GCM*: 96-bit nonce forces strict counter
  management; one failure destroys confidentiality. XSalsa20 avoids it by
  design.
- *RSA/OAEP*: huge keys (a 400+ byte bootstrap QR vs 179),
  no forward secrecy without tricks, slower.
- *age / PGP*: file-oriented with their own format; here we need
  total control of the wire format to fit it into QRs.

---

## 2. Unidirectional channel: fountain code (LT) instead of repetition

**The problem:** the screen emits, the camera receives. **There is no return
channel** — the receiver cannot ask "repeat frame 42". It's a
lossy broadcast.

**Evaluated options:**

| Strategy | Overhead for K chunks | Verdict |
|---|---|---|
| Simple loop sequence | ~K·ln(K) receptions (coupon collector). K=100 → ~460 frames, **4.6× waste** | ❌ |
| Reed–Solomon systematic (fixed K+ε) | ~1.05× but ε must be agreed beforehand and re-done if not enough | ⚠️ rigid |
| **LT code (Luby Transform)** | **~1.1–1.3×, unlimited, any frame works** | ✅ |
| RaptorQ (RFC 6330) | ~1.02×, theoretical optimum | 🔜 production (see below) |

**Decision: LT code with robust-soliton distribution**, implemented in
`fountain.py`:

- The sender generates an **infinite** stream of frames; each frame is the XOR
  of a pseudo-random subset of the K source chunks.
- The receiver decodes by *belief propagation* (peeling): each degree-1
  frame reveals a chunk, which in turn simplifies the others.
- The receiver needs **any** set of ~K·(1+ε) frames — it doesn't matter
  which ones were lost. This eliminates the coupon-collector.

**Measured in the simulator (8 KB, 512 B/chunk, 10% loss):**
overhead **1.31×** — that is, 21 frames delivered for 16 chunks.
At 50% brutal loss the channel still completes (2.56× overhead).

**Why LT and not RaptorQ yet:** RaptorQ adds a *precode* (LDPC) that requires
solving a linear system — more code, more bug surface, and for a
spike the gain (1.31× → 1.05×) doesn't justify the risk. **The product
plan is to migrate to RaptorQ** (there are reference crates and ports) once
the channel is validated; the `LTEncoder`/`LTDecoder` interface is already
designed to swap the codec without touching sender or receiver.

**Real bug found in the spike:** the robust-soliton overflowed for small K
(pivot > K). Fixed with clamp — exactly the kind of thing a
spike exists to find.

---

## 3. QR format: binary, EC-M, ~512 B payload per frame

**Decision:** **byte (8-bit) mode**, error correction **M (15%)**,
auto-fit version, target payload **512 bytes/chunk**.

**Why:**
- *Byte mode*: the ciphertext is arbitrary; numeric/alphanumeric
  modes don't apply and kanji adds nothing portable.
- *EC-M*: measured sweet spot. EC-L gives more capacity but fails more with
  brightness/angle; EC-H withstands more but the QR becomes dense and slow to
  scan. In the benchmark, M balances throughput and robustness.
- *512 B/chunk*: a complete frame (header + nonce + tag + payload) is
  ~577 bytes → fits comfortably in a **QR v25-M (1003 B capacity)**, which a
  mid-range camera scans at 10–15 fps effortlessly. 1024 B
  chunks give more raw throughput (5.8 KB/s in simulation) but worsen the
  fountain efficiency for small files (1.62× overhead) and require
  denser QRs. **512 B is the product default.**

**Binary frame (big-endian):**
```
MAGIC(2) "DD" | version(1) | file_id(8) | seq(4) | seed(4)
| degree(2) | chunk_ids(2×degree) | nonce(24) | ciphertext+tag(N)
```
The `file_id` allows the receiver to ignore frames from another nearby session
(two transfers in the same room). The `seed` allows in production
to reconstruct the `chunk_ids` without transmitting them (byte savings) — in the
spike we carry them explicitly for debuggability.

---

## 4. Session bootstrap: a static QR first

Before the animated sequence, the sender shows **a single static QR**
(179 bytes measured) with: ephemeral public key, receiver's public key
(binding — only that receiver can decrypt), file metadata and the
Ed25519 signature of the manifest.

This solves the cold start: the receiver points, reads a QR, and already
has everything needed to decode the animated stream that comes
after. The receiver's key is shared out of band (shown on their
screen, or exchanged at the start of the meeting).

---

## 5. Benchmark results (simulator, 12 fps)

| File | Chunks | Time | Throughput | Fountain overhead |
|---|---|---|---|---|
| 1 KB | 2 | 0.17 s | 6.1 KB/s | 1.00× |
| 8 KB | 16 | **2.1 s** | **3.9 KB/s** | 1.31× |
| 10 KB | 20 | 4.0 s | 2.6 KB/s | 2.05× |
| 25 KB | 50 | 5.9 s | 4.3 KB/s | 1.22× |
| 50 KB | 100 | 12.2 s | 4.2 KB/s | 1.25× |

**Product reading:**
- **The target use case (documents, keys, messages, small photos
  < 25 KB) crosses in 2–6 seconds.** It's usable.
- The channel **tolerates up to 50% frame loss** and still completes.
- Bit corruption **never** produces a silently corrupt file:
  the AEAD discards it (verified in `test_corruption_never_corrupts_file`).
- **Practical maximum size:** ~50–100 KB per transfer with current UX
  (12–25 s holding the phone). Larger files → split into
  multiple sessions or prior compression (future work).

---

## 6. Flutter port plan (production)

The spike's core logic is **1:1 portable** — it doesn't depend on Python beyond
syntax:

| Spike (Python) | Production (Flutter/Dart) |
|---|---|
| PyNaCl | `sodium_libs` (same libsodium) |
| `qrcode` (PIL) | `qr_flutter` (render) |
| channel simulator | `mobile_scanner` / `camera` (real capture) |
| `fountain.py` LT | direct port to Dart (pure, no deps) |
| CLI | Flutter UI: animated sender screen + receiver camera view |

**What the spike does NOT cover and remains for phase 2:**
- Real scanning performance on physical devices (sustained fps,
  auto-focus, angle tolerance). The simulator assumes 12 fps; it must be
  measured on hardware.
- LT → RaptorQ migration if overhead matters.
- Prior compression (zlib/zstd) for text files.
- Duress mode and self-destruction (product layer, not transport).
