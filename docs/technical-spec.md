# DeadDrop — Technical Specification v1

**Version:** 1.0
**Date:** 2026-10-17
**Author:** Marco Delgado (CTO)
**Status:** Governing document — contract between design, development, and documentation

---

## Purpose

This document is the **single source of truth** for what DeadDrop v1 is and how it works. Any developer should be able to read this spec and build the system without ambiguity. Any designer should understand the technical constraints their UI must respect. Any auditor should be able to verify the implementation matches the spec.

**Scope:** DeadDrop v1 MVP (deadline: 2027-02-10). Features marked as "v2" or "future work" are explicitly out of scope for the MVP.

**References:**
- Spike validation: `spike/` (throughput, crypto, fountain code) and `spike/DECISIONES.md`
- Duress mode design: `design/duress-flow.md`
- UX flows: `design/send-flow.md`, `design/receive-flow.md`
- Legal review: `docs/legal-review.md`

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Transfer Protocol](#2-transfer-protocol)
3. [Cryptography](#3-cryptography)
4. [Duress Mode](#4-duress-mode)
5. [Platforms](#5-platforms)
6. [Limits and Performance Targets](#6-limits-and-performance-targets)
7. [Internal API](#7-internal-api)

---

## 1. Architecture

### 1.1 System overview

DeadDrop is a **peer-to-peer, air-gapped file transfer application**. Two devices exchange encrypted files via an optical channel: the sender's screen displays animated QR codes, the receiver's camera reads them. No network, no Bluetooth, no USB — just light.

```
+------------------------------------------------------------------+
|                         SENDER DEVICE                            |
|  +--------+   +--------+   +----------+   +-----------+          |
|  |  File  |-->| Crypto |-->| Fountain |-->|    QR     |          |
|  |  Input |   | Engine |   | Encoder  |   | Renderer  |          |
|  +--------+   +--------+   +----------+   +-----------+          |
|                                                  |               |
|                                                  v               |
|                                            +-----------+         |
|                                            |  Screen   |         |
|                                            | (animated |         |
|                                            |   QRs)    |         |
|                                            +-----------+         |
+---------------------------------------------------|--------------+
                                                    |
                                               light (optical)
                                                    |
+---------------------------------------------------|--------------+
|                        RECEIVER DEVICE            |              |
|                                                   v              |
|                                            +-----------+         |
|                                            |  Camera   |         |
|                                            +-----------+         |
|                                                  |               |
|  +--------+   +--------+   +----------+   +-----------+          |
|  | Output |<--| Crypto |<--| Fountain |<--|    QR     |          |
|  |  File  |   | Engine |   | Decoder  |   | Scanner   |          |
|  +--------+   +--------+   +----------+   +-----------+          |
+------------------------------------------------------------------+
```

### 1.2 Module breakdown

DeadDrop is organized into **six core modules**, each with a single responsibility:

| Module | Responsibility | Key interfaces |
|---|---|---|
| **Emitter** | Orchestrates the send flow: file selection, encryption, QR generation | `EmitterSession`, `FilePicker`, `ProgressReporter` |
| **Receiver** | Orchestrates the receive flow: camera, QR scan, decryption, file output | `ReceiverSession`, `CameraController`, `ProgressReporter` |
| **Crypto Engine** | All cryptographic operations: key exchange, encryption, decryption, signatures | `CryptoContext`, `SessionKeys`, `Identity` |
| **QR Engine** | QR code generation (sender) and scanning (receiver) | `QRRenderer`, `QRScanner`, `FrameEncoder`, `FrameDecoder` |
| **Fountain Codec** | LT code encoding/decoding for loss-tolerant transfer | `FountainEncoder`, `FountainDecoder` |
| **Storage** | Local file persistence, encrypted at rest, duress mode separation | `SecureStorage`, `EnvironmentManager` |

**Design principles:**
- **Modularity:** each module is independently testable. The crypto engine doesn't know about QRs; the QR engine doesn't know about files.
- **No network stack:** the app has zero network code. The only I/O is file system, camera, and screen.
- **Offline-first:** everything works without internet. No accounts, no telemetry, no cloud sync.

### 1.3 Component diagram (detailed)

```
+--------------------------------------------------------------------+
|                       DeadDrop Application                         |
+--------------------------------------------------------------------+
|  +--------------------------------------------------------------+  |
|  |                         UI Layer                             |  |
|  |  +----------+  +----------+  +----------+  +----------+      |  |
|  |  |   Home   |  |   Send   |  | Receive  |  | Settings |      |  |
|  |  |  Screen  |  |  Screen  |  |  Screen  |  |  Screen  |      |  |
|  |  +----------+  +----------+  +----------+  +----------+      |  |
|  +--------------------------------------------------------------+  |
|  +---------------------------+---------------------------------+   |
|  |                     Business Logic                          |   |
|  |  +--------------+                    +--------------+       |   |
|  |  |   Emitter    |<------------------>|   Receiver   |       |   |
|  |  |   Session    |                    |   Session    |       |   |
|  |  +--------------+                    +--------------+       |   |
|  |  +------+-------------------------------------+------+      |   |
|  |  |            Crypto Engine                          |      |   |
|  |  |  - X25519 key exchange                            |      |   |
|  |  |  - XSalsa20-Poly1305 AEAD                         |      |   |
|  |  |  - Ed25519 signatures                             |      |   |
|  |  |  - Argon2id PIN derivation                        |      |   |
|  |  +---------------------------------------------------+      |   |
|  |  +------+----------+                   +------+----------+  |   |
|  |  |  Fountain       |                   |  Fountain       |  |   |
|  |  |  Encoder (LT)   |                   |  Decoder (LT)   |  |   |
|  |  +-----------------+                   +-----------------+  |   |
|  |  +------+----------+                   +------+----------+  |   |
|  |  |   QR Renderer   |                   |   QR Scanner    |  |   |
|  |  |  (qr_flutter)   |                   | (mobile_scanner)|  |   |
|  |  +-----------------+                   +-----------------+  |   |
|  +--------------------------------------------------------------+  |
|  +---------------------------+---------------------------------+   |
|  |                    Storage Layer                            |   |
|  |  +--------------+                    +--------------+       |   |
|  |  |   Secure     |<------------------>| Environment  |       |   |
|  |  |   Storage    |                    |   Manager    |       |   |
|  |  |  (encrypted) |                    | (real/decoy) |       |   |
|  |  +--------------+                    +--------------+       |   |
|  +--------------------------------------------------------------+  |
+--------------------------------------------------------------------+
```

### 1.4 Data flow: sending a file

1. **User selects file** -> `EmitterSession.create(file_path)`
2. **Crypto engine generates ephemeral X25519 keypair** -> `CryptoContext.generate_ephemeral_keypair()`
3. **File is hashed (SHA-256)** -> manifest created
4. **Manifest is signed with sender's Ed25519 identity key** -> `SessionHeader`
5. **Session header is encoded as a static QR** -> displayed to receiver
6. **File is split into chunks (512 bytes each)** -> `FountainEncoder`
7. **Each chunk is encrypted with XSalsa20-Poly1305** -> `CryptoContext.encrypt_chunk()`
8. **Fountain encoder generates LT-encoded frames** -> XOR of random chunk subsets
9. **Each frame is rendered as a QR code** -> `QRRenderer.render(frame)`
10. **QRs are displayed in a loop at 12 fps** -> screen

### 1.5 Data flow: receiving a file

1. **User opens camera** -> `ReceiverSession.start()`
2. **Camera scans static session QR** -> `QRScanner.scan()` -> `SessionHeader`
3. **Crypto engine verifies sender signature** -> `CryptoContext.verify_signature()`
4. **Crypto engine derives session key** -> `X25519(receiver_sk, sender_eph_pk)`
5. **Camera scans animated QR frames** -> `FrameDecoder.decode(qr_data)`
6. **Each frame is decrypted** -> `CryptoContext.decrypt_chunk()`
7. **Fountain decoder accumulates frames** -> `FountainDecoder.add_frame()`
8. **When enough frames received (~1.3x chunk count), decode** -> `FountainDecoder.reassemble()`
9. **Verify SHA-256 hash of reassembled file** -> manifest check
10. **Save file to secure storage** -> `SecureStorage.save(file)`

---

## 2. Transfer Protocol

### 2.1 Overview

The transfer protocol is a **one-way, lossy broadcast channel**. The sender emits an unbounded stream of QR frames; the receiver captures whatever it can. There is no back-channel — the receiver cannot request retransmissions. This is solved with a **fountain code** (LT code): any subset of ~1.3x the source chunks is sufficient to decode the file.

**Key properties:**
- **Unidirectional:** sender -> receiver only
- **Lossy:** frames can be dropped, corrupted, or misread
- **Rateless:** the sender generates an infinite stream; the receiver stops when it has enough
- **Self-authenticating:** every frame is individually authenticated (AEAD)

### 2.2 Frame format

All frames are binary, big-endian. Two frame types exist: **session header** (one static QR) and **data frames** (animated QR sequence).

#### 2.2.1 Session header (static QR, sent once)

```
+----------+---------+----------------+----------------+----------+
|  MAGIC   | VERSION | SENDER_EPH_PK  |  RECEIVER_PK | FILE_ID  |
|  2 bytes | 1 byte  |    32 bytes    |    32 bytes  | 8 bytes  |
|  "DD"    |   0x01  |  X25519 public | X25519 public|  random  |
+----------+---------+----------------+--------------+----------+
+------------+-------------+------------+---------------------------+
| TOTAL_SIZE | CHUNK_COUNT | CHUNK_SIZE |     MANIFEST_HASH         |
|  4 bytes   |   2 bytes   |   2 bytes  |       32 bytes            |
|  uint32    |   uint16    |   uint16   |  SHA-256 of plaintext     |
+------------+-------------+------------+---------------------------+
+--------------------------------------------------------------------+
|                          SIGNATURE                                 |
|                          64 bytes                                  |
|              Ed25519 signature over all previous fields            |
+--------------------------------------------------------------------+
```

**Total size:** 179 bytes (fits comfortably in a QR v10-M, capacity 274 bytes)

**Field descriptions:**
- `MAGIC`: protocol identifier, always `0x4444` ("DD" in ASCII)
- `VERSION`: protocol version, currently `0x01`
- `SENDER_EPH_PK`: sender's ephemeral X25519 public key (generated fresh per transfer)
- `RECEIVER_PK`: receiver's X25519 public key (shared out-of-band before transfer)
- `FILE_ID`: random 8-byte transfer identifier (prevents cross-session confusion)
- `TOTAL_SIZE`: plaintext file size in bytes (before encryption)
- `CHUNK_COUNT`: number of source chunks (K in fountain code terminology)
- `CHUNK_SIZE`: plaintext bytes per chunk (default: 512)
- `MANIFEST_HASH`: SHA-256 of the plaintext file (end-to-end integrity check)
- `SIGNATURE`: Ed25519 signature over all previous fields (sender authenticity)

#### 2.2.2 Data frame (animated QR sequence)

```
+----------+---------+----------+----------+----------+----------+
|  MAGIC   | VERSION | FILE_ID  |   SEQ    |   SEED   |  DEGREE  |
|  2 bytes | 1 byte  | 8 bytes  | 4 bytes  | 4 bytes  | 2 bytes  |
|  "DD"    |   0x01  |  random  |  uint32  |  uint32  |  uint16  |
+----------+---------+----------+----------+----------+----------+
+---------------------+--------------+----------------------------+
|     CHUNK_IDS       |    NONCE     |      CIPHERTEXT + TAG      |
|  2 bytes x DEGREE   |   24 bytes   |       variable             |
|  uint16 array       |  XSalsa20    |  (chunk_size + 16 bytes)   |
+---------------------+--------------+----------------------------+
```

**Typical size:** 577 bytes for a 512-byte chunk (fits in QR v25-M, capacity 1003 bytes)

**Field descriptions:**
- `MAGIC`, `VERSION`, `FILE_ID`: same as session header
- `SEQ`: monotonically increasing frame sequence number (0, 1, 2, ...)
- `SEED`: PRNG seed for this frame's chunk selection (allows receiver to reconstruct chunk IDs without transmitting them — future optimization)
- `DEGREE`: number of source chunks XORed in this frame (sampled from robust soliton distribution)
- `CHUNK_IDS`: explicit list of chunk indices XORed in this frame (in the MVP; production will derive from SEED)
- `NONCE`: random 24-byte nonce for XSalsa20-Poly1305
- `CIPHERTEXT + TAG`: encrypted and authenticated chunk payload (chunk_size bytes plaintext + 16 bytes Poly1305 tag)

### 2.3 Fountain code (LT code)

#### 2.3.1 Why a fountain code?

The QR channel is **one-way and lossy**. The receiver cannot ask for retransmissions. Without a fountain code, the receiver must capture **every single frame** — if frame 42 is lost, the transfer fails. This is unacceptable.

A **fountain code** solves this: the sender generates an **infinite stream** of encoded frames, each the XOR of a pseudo-random subset of the K source chunks. The receiver only needs **any** ~K*(1+eps) frames (eps ~ 0.1-0.3) to decode everything via **belief propagation** (peeling).

**Measured performance (spike, 8 KB file, 512 B chunks, 10% frame loss):**
- Overhead: **1.31x** (21 frames delivered for 16 chunks)
- Tolerates up to **50% frame loss** and still completes
- No coupon-collector problem (unlike naive repetition)

#### 2.3.2 LT code parameters

- **Degree distribution:** Robust Soliton with parameters c=0.05, delta=0.5
- **Encoding:** for each frame, sample degree d from the distribution, select d random chunks, XOR them
- **Decoding:** belief propagation — each degree-1 frame reveals a chunk, which simplifies other frames
- **Determinism:** chunk selection is derived from `(seed, seq)` via a fully specified 32-bit PRNG, so both sides can reconstruct it bit-for-bit on any platform (future: transmit only seed, not chunk_ids). The construction is `mixSeed(seed, seq)` (splitmix32-style bijective mixing) feeding a xorshift32 generator with explicit Fisher-Yates subset selection — see `app/lib/src/prng.dart` and `spike/src/fountain.py`, which produce identical streams (pinned by golden-vector tests in `app/test/prng_test.dart`). It replaces `dart:math.Random((seed << 32) ^ seq)`, which silently truncated the seed to 32 bits and whose algorithm is not specified across platforms. **Note:** this PRNG is a selection algorithm, not a cryptographic primitive — all cryptography remains in libsodium.

#### 2.3.3 Chunk size selection

**Measured throughput (spike, 12 fps, 10% loss, EC-M):**

| Chunk size | Chunks (8 KB) | Throughput | Overhead | Verdict |
|---|---|---|---|---|
| 256 B | 32 | 2.3 KB/s | 1.13x | Too many frames, slow |
| **512 B** | **16** | **3.9 KB/s** | **1.31x** | **Sweet spot** |
| 768 B | 11 | 5.2 KB/s | 1.36x | Denser QR, harder to scan |
| 1024 B | 8 | 5.8 KB/s | 1.63x | Inefficient fountain, dense QR |

**Decision: 512 bytes per chunk.** Balances throughput, QR density, and fountain efficiency. Validated in the spike.

### 2.4 Error detection and handling

**Per-frame integrity:** every frame is encrypted with XSalsa20-Poly1305 (AEAD). If a frame is corrupted (bit flips, partial scan), the Poly1305 tag check fails and the frame is **discarded**. It never corrupts the file.

**End-to-end integrity:** after fountain decoding, the receiver computes SHA-256 of the reassembled plaintext and compares it to the `MANIFEST_HASH` in the session header. Mismatch = transfer failed (should never happen if AEAD is working).

**Frame loss:** the fountain code tolerates arbitrary frame loss. The receiver just keeps scanning until it has enough frames. No timeout — the user decides when to give up.

**Cross-session contamination:** the `FILE_ID` field (8 random bytes) prevents frames from one transfer being mixed into another. The receiver ignores frames with a mismatched `FILE_ID`.

### 2.5 Metadata format

The session header (section 2.2.1) is the only metadata transmitted. It contains:
- Cryptographic parameters (public keys, signature)
- File parameters (size, chunk count, chunk size)
- Integrity check (SHA-256 hash)

**No filename is transmitted in the clear.** The filename is part of the encrypted payload (inside the first chunk), so it never appears in plaintext on the wire.

### 2.6 Transfer flow (sequence diagram)

```
SENDER                                    RECEIVER
  |                                          |
  |  1. Generate ephemeral X25519 keypair    |
  |  2. Read receiver's public key (OOB)     |
  |  3. Compute session key                  |
  |  4. Hash file (SHA-256)                  |
  |  5. Sign manifest (Ed25519)              |
  |                                          |
  |----- Session Header QR (static) -------->|
  |                                          |  6. Scan session QR
  |                                          |  7. Verify signature
  |                                          |  8. Compute session key
  |                                          |
  |  9. Split file into chunks               |
  | 10. For each frame:                      |
  |     - Sample degree from robust soliton  |
  |     - Select random chunks               |
  |     - XOR chunks                         |
  |     - Encrypt with XSalsa20-Poly1305     |
  |     - Render as QR                       |
  |                                          |
  |----- Data Frame QR (animated, 12 fps) -->|
  |                                          | 11. Scan frame
  |                                          | 12. Decrypt chunk
  |                                          | 13. Add to fountain decoder
  |                                          | 14. If enough frames: decode
  |                                          | 15. Verify SHA-256
  |                                          | 16. Save file
```

---

## 3. Cryptography

### 3.1 Algorithm stack

| Purpose | Algorithm | Library | Justification |
|---|---|---|---|
| **Key exchange** | X25519 (Curve25519 ECDH) | libsodium `crypto_box` | Fast, modern, forward secrecy (ephemeral keys) |
| **Symmetric encryption** | XSalsa20-Poly1305 (AEAD) | libsodium `crypto_secretbox` | 192-bit nonce (no counter management), authenticated |
| **Signatures** | Ed25519 | libsodium `crypto_sign` | Fast, deterministic, sender authenticity |
| **Hashing** | SHA-256 | libsodium `crypto_hash_sha256` | Standard, file integrity |
| **PIN derivation** | Argon2id | libsodium `crypto_pwhash` | Memory-hard, GPU-resistant, PIN -> encryption key |

**Why libsodium:**
- Audited, mature, reference implementation
- Hard to misuse (no dangerous options)
- Same backend on all platforms via `sodium_libs` (Flutter)
- Used by Signal, Wire, magic-wormhole

**Alternatives considered and rejected:**
- **AES-GCM:** 96-bit nonce requires strict counter management; a nonce reuse destroys confidentiality. XSalsa20's 192-bit nonce allows random generation without collision risk.
- **RSA:** huge keys (a 2048-bit RSA public key is 256 bytes vs 32 bytes for X25519), no forward secrecy without tricks, slower.
- **age/PGP:** file-oriented formats with their own container structure; we need raw control over the wire format for QR embedding.

### 3.2 Key hierarchy

```
+------------------------------------------------------------------+
|                    LONG-TERM IDENTITY                            |
|  Ed25519 signing keypair (per install, stored in OS keychain)    |
|  Purpose: authenticate the sender ("this file comes from me")    |
+------------------------------------------------------------------+
                              |
                              | signs
                              v
+------------------------------------------------------------------+
|                   SESSION HEADER (manifest)                      |
|  Contains: ephemeral public key, file hash, chunk params         |
+------------------------------------------------------------------+
                              |
                              | establishes
                              v
+------------------------------------------------------------------+
|                  EPHEMERAL SESSION KEYS                          |
|  X25519 keypair (sender, per transfer)                           |
|  X25519 keypair (receiver, per transfer or pre-shared)           |
|  Shared secret: X25519(sender_eph_sk, receiver_pk)               |
|  Purpose: encrypt file chunks, forward secrecy                   |
+------------------------------------------------------------------+
                              |
                              | encrypts
                              v
+------------------------------------------------------------------+
|                      FILE CHUNKS                                 |
|  Each chunk encrypted with XSalsa20-Poly1305                     |
|  Random 24-byte nonce per chunk                                  |
|  16-byte Poly1305 tag appended                                   |
+------------------------------------------------------------------+
```

**Key properties:**
- **Forward secrecy:** ephemeral X25519 keys are generated per transfer and never stored. Compromising the device later reveals nothing about past transfers.
- **Sender authenticity:** the Ed25519 signature on the session header proves the file comes from the person holding the sender device (not a MITM).
- **Receiver binding:** the session header includes the receiver's public key, so only that receiver can decrypt.

### 3.3 Handshake protocol

The handshake is **asynchronous and one-way**: the sender shows a QR, the receiver scans it. No interactive negotiation.

**Steps:**

1. **Receiver generates an X25519 keypair** and displays the public key to the sender (out-of-band):
   - Option A: receiver shows a static QR with their public key (32 bytes), sender scans it
   - Option B: receiver reads out a short verbal code (6 words from a wordlist, encoding the public key fingerprint), sender types it in
   - Option C: public key is pre-shared (e.g., printed on a business card, exchanged at the start of a meeting)

2. **Sender generates an ephemeral X25519 keypair** for this transfer

3. **Sender computes the shared secret:** `session_key = X25519(sender_eph_sk, receiver_pk)`

4. **Sender creates the session header** (section 2.2.1) with:
   - Ephemeral public key
   - Receiver's public key (binding)
   - File metadata (size, chunk count, chunk size)
   - SHA-256 hash of the plaintext file
   - Ed25519 signature over all fields

5. **Sender displays the session header as a static QR**

6. **Receiver scans the session header QR**, verifies the signature, and computes the same shared secret: `session_key = X25519(receiver_sk, sender_eph_pk)`

7. **Sender starts emitting encrypted data frames** (section 2.2.2)

8. **Receiver decrypts and decodes frames** until the file is complete

**Security properties:**
- **No MITM:** the receiver's public key is shared out-of-band (physically), so an attacker cannot substitute it without being physically present and detected.
- **Forward secrecy:** ephemeral keys are deleted after the transfer. A later device compromise reveals nothing.
- **Authentication:** the Ed25519 signature proves the sender's identity (if the receiver knows the sender's long-term public key).

### 3.4 PIN derivation (for duress mode)

When the user sets a PIN (real or decoy), the app derives an encryption key from it using **Argon2id**:

```
encryption_key = Argon2id(
    password = PIN,
    salt = random(16 bytes, stored),
    time_cost = 3,
    memory_cost = 64 MB,
    parallelism = 4,
    output_length = 32 bytes
)
```

**Parameters justification:**
- **Time cost 3:** ~0.5 seconds on a mid-range phone (2026 hardware). Slow enough to frustrate brute force, fast enough to not annoy the user.
- **Memory cost 64 MB:** makes GPU/ASIC attacks expensive (Argon2id's memory hardness is its key property).
- **Parallelism 4:** uses multiple cores for speed without reducing security.

**Critical requirement:** deriving the key from the decoy PIN must take **exactly as long** as from the real PIN. Same Argon2id parameters, same iteration count. If one is faster, an attacker with a stopwatch knows there are two modes.

### 3.5 Random number generation

All randomness comes from libsodium's `randombytes_buf()`, which uses:
- **Linux:** `getrandom()` syscall
- **Windows:** `BCryptGenRandom()`
- **macOS/iOS:** `SecRandomCopyBytes()`
- **Android:** `/dev/urandom` (backed by the kernel's CSPRNG)

No custom RNG, no seeding from weak sources (time, PID, etc.).

---

## 4. Duress Mode

### 4.1 Threat model

**Scenario:** the user is physically coerced into unlocking DeadDrop (border checkpoint, police search, abusive partner, etc.). The attacker:
- Has physical access to the device
- Can observe the screen
- Can navigate the app
- Has limited time (minutes, not hours)
- May have basic forensic tools (file system access)

**Goal:** the attacker must believe they have accessed the user's real data, while the real data remains hidden and inaccessible.

**Non-goals:**
- Protection against a sophisticated forensic analyst with unlimited time (if they image the device and analyze it for days, they may find anomalies)
- Protection against the user being forced to reveal the real PIN under torture (no technical solution exists for this)

### 4.2 Two-PIN model

The user configures **two PINs**:
- **Real PIN** (minimum 6 digits): unlocks the real environment with the user's actual files
- **Decoy PIN** (minimum 4 digits): unlocks a fake environment with plausible decoy files

**Key properties:**
- **Indistinguishable:** the app looks and behaves identically with either PIN. No visual difference, no hint, no indicator.
- **Plausible deniability:** there is no way to prove a second environment exists. The app doesn't know how many environments exist — it tries to decrypt with the entered PIN; if it works, it opens that environment.
- **Separate storage:** each environment has its own encrypted file tree, encrypted with a key derived from its PIN.

### 4.3 Environment separation

```
+------------------------------------------------------------------+
|                      App Data Directory                          |
+------------------------------------------------------------------+
|  +-----------------------------------------------------------+   |
|  |              Real Environment (encrypted)                 |   |
|  |  - Encrypted with key derived from real PIN               |   |
|  |  - Contains: user's actual files, history, settings       |   |
|  |  - File names encrypted (never in cleartext)              |   |
|  +-----------------------------------------------------------+   |
|  +-----------------------------------------------------------+   |
|  |              Decoy Environment (encrypted)                |   |
|  |  - Encrypted with key derived from decoy PIN              |   |
|  |  - Contains: fake files, fake history, copied settings    |   |
|  |  - Looks like a normal, boring user's data                |   |
|  +-----------------------------------------------------------+   |
|  Both environments coexist in the same directory.                |
|  No distinguishable headers, no identifiable padding.            |
|  Total size is indistinguishable from random padding.            |
+------------------------------------------------------------------+
```

**Implementation:**
- Each environment is a separate encrypted database (SQLite with SQLCipher, or a custom encrypted file tree)
- The encryption key is derived from the PIN via Argon2id (section 3.4)
- The app attempts decryption with the entered PIN; if it succeeds, that environment opens
- If decryption fails, "Incorrect PIN" (no hint whether the PIN is wrong or the environment doesn't exist)

### 4.4 Decoy environment content

The decoy environment must be **boringly normal**. If it looks fake, it's useless.

**Auto-generated decoy content (recommended):**
- 3-5 generic photos (landscapes, food, pets — from a built-in library of stock images)
- 2-3 PDFs (a cooking recipe, a gym schedule, a generic invoice template)
- 1-2 text notes (shopping list, reminder)
- A fake but coherent send/receive history (timestamps, file names, sizes)

**Manual decoy content (advanced):**
- The user selects their own decoy files from their device
- Useful for personalization, but requires more effort

**Critical properties:**
- **Functional:** decoy files can be previewed, sent, and deleted. A file that "can't be opened" gives the trick away.
- **Coherent:** file names, sizes, and timestamps must be internally consistent (e.g., a photo from "last summer" shouldn't have a creation date of tomorrow).
- **Boring:** no interesting content. Vacation photos, recipes, gym schedules. Nothing that would make an attacker suspicious or curious.

### 4.5 Behavioral indistinguishability

**Timing:**
- PIN entry -> key derivation -> environment unlock takes **exactly the same time** for both PINs (same Argon2id parameters)
- No artificial delay after an incorrect PIN (that would reveal there are two modes)

**UI:**
- The login screen is **identical** regardless of which PIN is entered
- The home screen is **identical** in layout, colors, typography — only the content differs
- Settings menu in the decoy environment **does not show** the "Duress mode" section (no trace it exists)

**Behavior:**
- The user **can use the app normally** in decoy mode: send and receive files. Everything works. Files are saved to the decoy environment, not the real one.
- The activity log in the decoy environment shows only decoy activity
- Speed, sound, appearance settings are **copied from the real environment** for consistency

### 4.6 What the attacker sees

When the attacker enters the decoy PIN:

```
+--------------------------------------+
|            DeadDrop                  |
|    +-------------------------+       |
|    |    Send file            |       |
|    +-------------------------+       |
|    +-------------------------+       |
|    |    Receive file         |       |
|    +-------------------------+       |
|  Recent:                             |
|  - summer-beach.jpg  3.1 MB          |
|  - paella-recipe.pdf 450 KB          |
|  - mom-birthday.jpg  2.8 MB          |
|              Settings                |
+--------------------------------------+
```

**Identical to the real home screen.** Same typography, same colors, same buttons. The only difference is the content.

If the attacker navigates to Settings:
- They see "General" and "Advanced" sections
- They **do not see** a "Security" section (which contains "Duress mode" in the real environment)
- No trace that duress mode exists

### 4.7 What the attacker can never see

- Real files
- Real history
- The existence of duress mode
- The existence of a second environment
- Any hint that the decoy PIN is not the real PIN

### 4.8 Self-destruct (optional, v2)

**Feature:** after N failed PIN attempts (e.g., 10), the app wipes both environments.

**UX decision (from the duress-mode design):**
- Failed attempts count toward a **global counter** (not per-environment)
- If self-destruct fires, **wipe both environments** (a surviving decoy would reveal there was something to erase)

**Status:** v2 feature, not in the MVP. Requires careful UX design to avoid accidental triggers.

---

## 5. Platforms

### 5.1 Target platforms

| Platform | Priority | Status | Notes |
|---|---|---|---|
| **Windows** | P0 (MVP) | Planned | Windows 10+ (64-bit), Flutter desktop |
| **macOS** | P0 (MVP) | Planned | macOS 11+ (Big Sur and later), Flutter desktop |
| **Linux** | P0 (MVP) | Planned | Ubuntu 20.04+, Fedora 35+, AppImage + .deb |
| **Android** | P1 (post-MVP) | Stretch goal | Android 8.0+ (API 26+), if time allows |
| **iOS** | P1 (post-MVP) | Stretch goal | iOS 14+, if time allows |

**MVP focus:** Windows, macOS, Linux (desktop). Mobile is a stretch goal — the core use case (journalist with a laptop) is desktop-first.

### 5.2 Technology stack

| Layer | Technology | Justification |
|---|---|---|
| **UI framework** | Flutter 3.x | Single codebase for all platforms, native performance, mature |
| **Language** | Dart 3.x | Flutter's language, modern, null-safe |
| **Crypto** | libsodium via `sodium_libs` | Audited, same backend on all platforms |
| **QR rendering** | `qr_flutter` | Mature, customizable, pure Dart |
| **QR scanning** | `mobile_scanner` | Fast, cross-platform, supports all QR formats |
| **Camera** | `camera` plugin | Official Flutter plugin, cross-platform |
| **File picker** | `file_picker` | Cross-platform file selection |
| **Secure storage** | `flutter_secure_storage` | OS keychain integration (Keychain on macOS/iOS, Keystore on Android, DPAPI on Windows, libsecret on Linux) |
| **Local database** | `sqflite` (SQLite) | Mature, cross-platform, encrypted via SQLCipher |

### 5.3 Native dependencies

| Platform | Dependency | Purpose |
|---|---|---|
| **All** | libsodium (bundled via `sodium_libs`) | Cryptography |
| **Windows** | Visual C++ Redistributable | libsodium runtime |
| **macOS** | None (libsodium is statically linked) | — |
| **Linux** | libsecret-1-0 | Secure storage (GNOME Keyring / KDE Wallet) |
| **Android** | None (all dependencies bundled) | — |
| **iOS** | None (all dependencies bundled) | — |

### 5.4 Build matrix

| Platform | Build tool | Output format | CI |
|---|---|---|---|
| **Windows** | Flutter build windows | `.exe` installer (Inno Setup) | GitHub Actions |
| **macOS** | Flutter build macos | `.dmg` (unsigned, Gatekeeper bypass documented) | GitHub Actions |
| **Linux** | Flutter build linux | `.AppImage` + `.deb` | GitHub Actions |
| **Android** | Flutter build apk | `.apk` (unsigned, sideload) | GitHub Actions |
| **iOS** | Flutter build ios | `.ipa` (unsigned, TestFlight) | GitHub Actions (macOS runner) |

**Reproducible builds:** all builds must be reproducible (same source -> same binary hash). CI publishes SHA-256 checksums; users can verify locally.

### 5.5 Platform-specific considerations

**Windows:**
- SmartScreen warning on unsigned `.exe` — documented in install guide
- DPAPI for secure storage (tied to user account)

**macOS:**
- Gatekeeper warning on unsigned `.dmg` — documented (right-click -> Open)
- Keychain for secure storage
- Notarization is out of scope for MVP (requires Apple Developer account, $99/year)

**Linux:**
- AppImage is the primary distribution format (no installation required)
- `.deb` for Debian/Ubuntu users who prefer package managers
- libsecret for secure storage (GNOME Keyring / KDE Wallet)

**Android:**
- Camera permission required (runtime permission, Android 6+)
- Scoped storage (Android 10+) — files saved to app-specific directory by default

**iOS:**
- Camera permission required (Info.plist declaration)
- App Sandbox — files saved to app container
- TestFlight distribution (no App Store review for MVP)

---

## 6. Limits and Performance Targets

### 6.1 File size limits

| Metric | Limit | Justification |
|---|---|---|
| **Minimum file size** | 1 byte | No lower bound |
| **Maximum file size (MVP)** | **100 KB** | UX constraint: 100 KB at 4 KB/s = 25 seconds of holding the camera steady. Longer is fatiguing. |
| **Maximum file size (v2)** | 1 MB | Requires compression (zstd) and multi-session transfer (split into chunks, transfer in batches) |

**Measured transfer times (spike, 12 fps, 10% loss):**
- 1 KB: 0.17 seconds
- 8 KB: 2.1 seconds
- 25 KB: 5.9 seconds
- 50 KB: 12.2 seconds
- 100 KB: ~25 seconds (extrapolated)

**Target use case:** documents, photos, keys, messages — typically < 25 KB. Transfers complete in 2-6 seconds.

### 6.2 Throughput targets

| Metric | Target | Measured (spike) |
|---|---|---|
| **Effective throughput** | >= 3 KB/s | **3.9 KB/s** (8 KB file, 512 B chunks, 10% loss) |
| **Frame rate** | 12 fps | 12 fps (simulated; hardware validation pending) |
| **Frame loss tolerance** | >= 30% | **50%** (completes even with half the frames lost) |
| **Fountain overhead** | <= 1.5x | **1.31x** (21 frames for 16 chunks) |

**Bottleneck:** camera frame rate and QR decode speed. The spike assumes 12 fps; real hardware may be slower (10 fps) or faster (15 fps). The protocol is adaptive — the receiver just scans until it has enough frames.

### 6.3 Timeouts

| Operation | Timeout | Behavior on timeout |
|---|---|---|
| **Session header scan** | 30 seconds | "No transfer detected. Make sure the sender is showing the QR code." |
| **Data frame scan** | No timeout | The receiver keeps scanning indefinitely. The user decides when to give up. |
| **PIN entry** | No timeout | No lockout (that would reveal there are two modes). Internal rate limiting: invisible exponential delay after 5 failed attempts. |
| **File save** | 10 seconds | "Could not save the file. Check that you have enough space." |

### 6.4 Resource limits

| Resource | Limit | Justification |
|---|---|---|
| **Memory (sender)** | < 100 MB | File is loaded into memory, chunked, encrypted. 100 KB file + overhead ~ 1 MB. QR rendering is the largest consumer. |
| **Memory (receiver)** | < 150 MB | Fountain decoder buffers frames in memory. 100 KB file + 1.3x overhead ~ 130 KB. Camera preview is the largest consumer. |
| **Disk (app)** | < 50 MB | App binary + libraries |
| **Disk (data)** | User-managed | Received files are saved to user-chosen location. App data (encrypted environments) grows with usage. |
| **CPU** | < 50% on mid-range hardware | Crypto is fast (libsodium is optimized). QR rendering and camera preview are the main consumers. |

### 6.5 Camera and screen requirements

| Component | Minimum | Recommended |
|---|---|---|
| **Screen (sender)** | 800x600, 60 Hz | 1920x1080, 60 Hz |
| **Camera (receiver)** | 720p, 10 fps | 1080p, 30 fps |
| **Lighting** | Indoor office lighting | Bright, even lighting (avoid glare on screen) |
| **Distance** | 10-50 cm | 20-30 cm (arm's length) |

**QR code size on screen:** the QR is rendered at 512x512 pixels (scalable). At 20-30 cm distance, a mid-range phone camera can decode it reliably.

---

## 7. Internal API

### 7.1 Module interfaces

Each module exposes a clean, typed API. Internal APIs are **not** public — they are contracts between modules, not for external consumers.

#### 7.1.1 Crypto Engine

```dart
/// Cryptographic context for a DeadDrop session.
abstract class CryptoContext {
  /// Generate a long-term Ed25519 identity keypair (per install).
  Future<Identity> generateIdentity();

  /// Load the identity from secure storage (or generate if first run).
  Future<Identity> loadOrCreateIdentity();

  /// Generate an ephemeral X25519 keypair for a transfer.
  Future<EphemeralKeypair> generateEphemeralKeypair();

  /// Create a sender session: encrypt file, sign manifest.
  Future<SenderSession> createSenderSession({
    required Uint8List plaintext,
    required PublicKey receiverPk,
    required Identity senderIdentity,
    int chunkSize = 512,
  });

  /// Create a receiver session: verify manifest, prepare decryption.
  Future<ReceiverSession> createReceiverSession({
    required Uint8List sessionHeaderBytes,
    required EphemeralKeypair receiverKeypair,
    PublicKey? senderVerifyKey, // optional: verify sender identity
  });

  /// Derive an encryption key from a PIN (for duress mode).
  Future<SecretKey> deriveKeyFromPin({
    required String pin,
    required Uint8List salt,
  });
}

/// Sender-side session: encrypts chunks.
abstract class SenderSession {
  SessionHeader get header;
  Future<EncryptedChunk> encryptChunk(int chunkId);
}

/// Receiver-side session: decrypts chunks.
abstract class ReceiverSession {
  SessionHeader get header;
  Future<Uint8List> decryptChunk(EncryptedChunk chunk);
  Future<bool> verifyFileIntegrity(Uint8List plaintext);
}
```

#### 7.1.2 Fountain Codec

```dart
/// LT code encoder: turns K source chunks into an infinite stream of frames.
abstract class FountainEncoder {
  /// Create an encoder for a list of source chunks.
  factory FountainEncoder(List<Uint8List> chunks);

  /// Generate the next encoded frame.
  EncodedFrame nextFrame();
}

/// LT code decoder: accumulates frames until all K chunks are recovered.
abstract class FountainDecoder {
  /// Create a decoder for K chunks of a given size.
  factory FountainDecoder(int chunkCount, int chunkSize);

  /// Add a received frame. Returns true if it made progress.
  bool addFrame(EncodedFrame frame);

  /// Check if decoding is complete.
  bool get isComplete;

  /// Reassemble the decoded chunks into the original data.
  Uint8List reassemble();

  /// Progress metrics (for UI feedback).
  int get framesReceived;
  int get framesUseful;
  double get efficiency;
}
```

#### 7.1.3 QR Engine

```dart
/// QR code renderer (sender side).
abstract class QRRenderer {
  /// Render a frame as a QR code image.
  Future<Image> render(Uint8List frameBytes, {int size = 512});
}

/// QR code scanner (receiver side).
abstract class QRScanner {
  /// Start scanning. Emits a stream of decoded QR payloads.
  Stream<Uint8List> startScanning();

  /// Stop scanning.
  Future<void> stopScanning();
}
```

#### 7.1.4 Storage

```dart
/// Secure, encrypted local storage.
abstract class SecureStorage {
  /// Save a file to the current environment.
  Future<void> saveFile(String name, Uint8List data);

  /// List files in the current environment.
  Future<List<FileMetadata>> listFiles();

  /// Read a file from the current environment.
  Future<Uint8List> readFile(String fileId);

  /// Delete a file from the current environment.
  Future<void> deleteFile(String fileId);
}

/// Environment manager: handles real vs. decoy environments.
abstract class EnvironmentManager {
  /// Unlock an environment with a PIN. Returns null if PIN is wrong.
  Future<Environment?> unlock(String pin);

  /// Create a new environment (real or decoy).
  Future<Environment> createEnvironment(String pin, {bool isDecoy});

  /// Check if duress mode is configured.
  Future<bool> isDuressModeEnabled();

  /// Populate the decoy environment with fake files.
  Future<void> populateDecoyEnvironment(Environment env);
}
```

#### 7.1.5 Emitter / Receiver

```dart
/// Orchestrates the send flow.
abstract class EmitterSession {
  /// Create a new send session for a file.
  static Future<EmitterSession> create(String filePath);

  /// Get the session header QR (static, shown first).
  Future<Image> getSessionHeaderQR();

  /// Start emitting data frames (animated QR sequence).
  Stream<Image> startEmitting();

  /// Stop emitting.
  Future<void> stop();

  /// Progress metrics.
  int get framesEmitted;
  double get elapsedSeconds;
}

/// Orchestrates the receive flow.
abstract class ReceiverSession {
  /// Create a new receive session.
  static Future<ReceiverSession> create();

  /// Start scanning for the session header.
  Future<void> scanSessionHeader();

  /// Start scanning for data frames.
  Stream<ReceiveProgress> startReceiving();

  /// Stop receiving.
  Future<void> stop();

  /// Save the received file.
  Future<void> saveFile(String outputPath);
}

/// Progress metrics for the receive flow.
class ReceiveProgress {
  final int framesReceived;
  final int framesUseful;
  final double percentComplete;
  final bool isComplete;
}
```

### 7.2 Data structures

```dart
/// Session header (transmitted as a static QR).
class SessionHeader {
  final Uint8List senderEphemeralPk; // 32 bytes
  final Uint8List receiverPk;        // 32 bytes
  final Uint8List fileId;            // 8 bytes
  final int totalSize;               // bytes
  final int chunkCount;              // K
  final int chunkSize;               // bytes per chunk
  final Uint8List manifestHash;      // SHA-256 of plaintext
  final Uint8List signature;         // Ed25519 signature

  Uint8List pack();
  static SessionHeader unpack(Uint8List bytes);
}

/// Encoded frame (transmitted as an animated QR).
class EncodedFrame {
  final Uint8List fileId;       // 8 bytes
  final int seq;                // frame sequence number
  final int seed;               // PRNG seed
  final List<int> chunkIds;     // chunk indices XORed in this frame
  final Uint8List nonce;        // 24 bytes
  final Uint8List ciphertext;   // encrypted chunk + Poly1305 tag

  Uint8List pack();
  static EncodedFrame unpack(Uint8List bytes);
}

/// File metadata (stored in secure storage).
class FileMetadata {
  final String id;
  final String name;         // encrypted
  final int size;
  final DateTime receivedAt;
  final String senderFingerprint; // Ed25519 public key fingerprint
}
```

### 7.3 Error handling

All modules use a common error hierarchy:

```dart
abstract class DeadDropError implements Exception {
  String get message;
  String get userMessage; // human-readable, non-technical
}

class CryptoError extends DeadDropError {
  // Signature verification failed, decryption failed, etc.
}

class FountainError extends DeadDropError {
  // Decoding failed, insufficient frames, etc.
}

class QRError extends DeadDropError {
  // QR decode failed, camera unavailable, etc.
}

class StorageError extends DeadDropError {
  // Disk full, permission denied, etc.
}
```

**User-facing error messages** are always in plain language, no jargon:
- Bad: "XSalsa20-Poly1305 authentication failed"
- Good: "The file is corrupted. Ask the sender to try again."

---

## Appendix A: Wire format reference

### Session header (179 bytes)

```
Offset  Size  Field
------  ----  -----
0       2     MAGIC ("DD")
2       1     VERSION (0x01)
3       32    SENDER_EPH_PK
35      32    RECEIVER_PK
67      8     FILE_ID
75      4     TOTAL_SIZE (uint32 BE)
79      2     CHUNK_COUNT (uint16 BE)
81      2     CHUNK_SIZE (uint16 BE)
83      32    MANIFEST_HASH (SHA-256)
115     64    SIGNATURE (Ed25519)
```

### Data frame (variable size, ~577 bytes for 512 B chunk)

```
Offset  Size  Field
------  ----  -----
0       2     MAGIC ("DD")
2       1     VERSION (0x01)
3       8     FILE_ID
11      4     SEQ (uint32 BE)
15      4     SEED (uint32 BE)
19      2     DEGREE (uint16 BE)
21      2xD   CHUNK_IDS (uint16 BE array)
21+2D   24    NONCE
45+2D   N     CIPHERTEXT + TAG (N = chunk_size + 16)
```

---

## Appendix B: Test vectors

**TODO (phase 2):** generate canonical test vectors for:
- Session header encoding/decoding
- Data frame encoding/decoding
- LT fountain encoding/decoding (fixed seed)
- Crypto roundtrip (known plaintext -> known ciphertext)

These will be in `/tests/vectors/` and must pass on all platforms.

---

## Appendix C: Security checklist

- [x] Ephemeral keys per transfer (forward secrecy)
- [x] AEAD on every chunk (no silent corruption)
- [x] Sender authentication via Ed25519 signature
- [x] Receiver binding (only intended receiver can decrypt)
- [x] SHA-256 file integrity check
- [x] Argon2id for PIN derivation (memory-hard)
- [x] Identical timing for real vs. decoy PIN
- [x] No network code in the app
- [x] No telemetry, no analytics, no crash reporting
- [x] Secure storage via OS keychain
- [x] File names encrypted (never in cleartext)
- [x] Cross-session protection via FILE_ID
- [ ] Reproducible builds (CI, phase 2)
- [ ] External security audit (post-MVP)

---

## Appendix D: Open questions (for v2)

1. **RaptorQ migration:** LT code overhead is 1.31x. RaptorQ (RFC 6330) achieves ~1.02x. Worth migrating if throughput becomes a bottleneck.
2. **Compression:** zstd compression before encryption could 2-3x effective throughput for text files. Adds complexity; defer to v2.
3. **Multi-file transfer:** current spec is single-file. Multi-file requires a manifest of manifests; defer to v2.
4. **Bidirectional transfer:** current spec is one-way. Bidirectional requires both devices to alternate sender/receiver roles; defer to v2.
5. **Verbal code fallback:** if the camera can't scan the session header QR, fall back to a 6-word verbal code (BIP39 wordlist). Requires UX design; defer to v2.

---

**End of specification.**

*This document is version 1.0. Changes require CTO approval and a version bump. Last updated: 2026-10-17.*