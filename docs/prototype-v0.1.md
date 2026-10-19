# DeadDrop v0.1 — Functional Prototype

This document describes the v0.1 end-to-end prototype: what it does, how the
wire protocol maps to the UI, and what is intentionally left out.

## What v0.1 does

A complete, encrypted, air-gapped transfer between two devices running the
app (or two windows on one machine for development):

1. **Handshake (QR).** The receiver opens *Receive a file* and shows a
   static QR containing its ephemeral X25519 public key:
   `DD1.<base64url({"t":"dd-key","v":1,"pk":"<hex>"})>`.
   The sender opens *Send a file* → *Scan receiver key QR* and captures it
   with the camera. No typing, no copy-paste.
2. **File selection + parameters.** The sender picks a file and can adjust
   chunk size (256–1024 B), frame rate (4–24 fps) and QR error-correction
   level (L/M/Q/H).
3. **Session bootstrap (static QR, 4 s).** The sender derives the shared
   secret (X25519), signs the manifest (Ed25519) and shows the 179-byte
   session header as a static QR.
4. **Data stream (animated QRs).** The sender emits an unbounded stream of
   LT-fountain-coded, XSalsa20-Poly1305-encrypted frames. Frame sequence 0
   carries the original file name inside the encrypted channel; from
   sequence 1 on, frames carry file data.
5. **Reception.** The receiver scans frames, shows live progress
   (chunks decoded / total, frames scanned), reassembles the file via
   belief propagation, verifies the SHA-256 manifest hash, and offers to
   save it under its original name.

## Transport envelope

All QR payloads are printable ASCII: `DD1.<base64url(bytes)>`. This makes
the channel robust across the text-oriented QR stack (qr_flutter rendering,
mobile_scanner / ZXing / ML Kit scanning) at the cost of ~33% more QR
density — invisible in practice at the chunk sizes we use.

## Intentionally out of scope for v0.1

- **Duress mode / PIN unlock** — separate task, spec §4.
- **Secure storage** — received files are written where the user chooses.
- **Sender identity verification UI** — the receiver verifies the signature
  cryptographically when given the sender's verify key, but there is no
  contact management UI yet.
- **Mobile camera tuning** (torch, focus lock, auto-exposure hints).
- **The demo video** — recorded separately once this build is on devices.

## Verifying the prototype

```bash
cd app
flutter test    # includes timed 1KB / 100KB / 1MB end-to-end transfers
```

Benchmark lines look like:

```
[benchmark] 1MB: 8420 ms, 2621 frames for 2048 chunks (overhead 1.28x), 124.5 KB/s pipeline throughput
```

(Pipeline throughput measures the software encode→decode path only; the
optical channel at 12 fps is the bottleneck in real use — see spike results.)
