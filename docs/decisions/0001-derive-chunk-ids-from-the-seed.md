# 1. Derive chunk ids from the seed instead of transmitting them

**Status:** accepted, 2026-10-29
**Decided by:** the project owner, on the grounds that DeadDrop is not in
production and has until 2027-02-10 for breaking changes.

## Context

Every frame carries its `chunkIds` list explicitly: a 2-byte `degree`
followed by `degree` 2-byte ids. The length of that list is the fountain
code's degree, which varies by design — the robust soliton distribution
has a long tail, and that tail is what lets the decoder converge.

Because the ids are transmitted, the cost of a high-degree frame is paid
in the QR. Measured with 512-byte chunks over 500 frames:

| chunks (k) | p50 | p90 | p99 | max | frames needing >900 B |
|---|---|---|---|---|---|
| 100 | 2 | 18 | 43 | 87 | 0 / 500 |
| 1 000 | 2 | 20 | 83 | 412 | 2 / 500 |
| 4 600 | 2 | 17 | 148 | 624 | 2 / 500 |

A degree-624 frame carries 1 248 bytes of ids on top of 512 bytes of
data. Roughly 2 frames in 500 need over 900 bytes against a typical 550.
Those frames jump several QR versions, which is visible as an isolated
flash during emission, and the largest exceed the capacity limits the app
enforces, so they are unreadable or not emitted at all.

Capping the degree was measured and rejected. Frames needed to decode, as
a multiple of k:

| k | no cap | cap 16 | cap 32 | cap 64 |
|---|---|---|---|---|
| 100 | 1.53× | 1.43× | 1.47× | 1.53× |
| 500 | 1.27× | 2.44× | 1.43× | 1.25× |
| 1 000 | 1.07× | 2.54× | 2.09× | 1.37× |

At k=1000 a cap of 16 takes the overhead from 1.07× to 2.54×. Capping
breaks the property that makes a fountain code worth using.

## Decision

Remove `chunk_ids` from the frame. The receiver recomputes them.

`LTEncoder.makeFrame` is already deterministic in `(seq, seed)`, and both
travel in every frame; `k` comes from the session header, which the
receiver has before any frame arrives. The derivation is therefore
available to the receiver with no new information on the wire.

The `degree` field stays, for two reasons. It distinguishes the metadata
frame, which has degree 0 and carries no chunks — previously recognised
by an empty id list, a discriminator that disappears with the list. And
it lets the receiver reject a frame whose recomputed degree disagrees,
which catches a desynchronised emitter rather than silently decoding
against the wrong chunks.

## Consequences

Every frame becomes the same size, which removes the flash, and the
average frame shrinks — a typical degree-2 frame loses 4 bytes, but the
tail loses hundreds, so denser chunk sizes become viable at the same QR
version.

This is a wire format change. Per `docs/versioning.md` it forces a MAJOR
even before 1.0. A receiver on the old format and an emitter on the new
one will not interoperate; both sides must be rebuilt together. Accepted
because nothing is deployed.

The derivation must stay identical on both sides forever. It already had
to be — the decoder's chunk ids were only ever meaningful because the
encoder generated them deterministically — but previously a divergence
would have been caught by the transmitted ids disagreeing with reality.
Now a divergence silently corrupts a transfer. The guard is the shared
implementation plus the degree cross-check, and a test that pins the
derivation against fixed vectors so a refactor cannot move it.
