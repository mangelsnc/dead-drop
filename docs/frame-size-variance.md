# Frame size varies with fountain degree

**Status:** open problem, not yet decided. Affects the wire format, so it
needs a decision before it is implemented.

## What is observed

During emission the displayed QR occasionally changes size sharply — a
visible flash, isolated rather than continuous. Reported on both macOS
and Android, at 512-byte chunks with a 2.3 MB file.

## Why it happens

A frame carries its `chunkIds` list explicitly, and the length of that
list is the fountain code's *degree*, which varies by design. The robust
soliton distribution is supposed to have a long tail — that tail is what
lets the decoder converge — but because the ids are transmitted, the cost
of a high-degree frame is paid in the QR.

Measured with 512-byte chunks (`LTEncoder`, 500 frames per row):

| chunks (k) | p50 | p90 | p99 | max | frames needing >900 B |
|---|---|---|---|---|---|
| 100 | 2 | 18 | 43 | 87 | 0 / 500 |
| 1 000 | 2 | 20 | 83 | 412 | 2 / 500 |
| 4 600 | 2 | 17 | 148 | 624 | 2 / 500 |

A degree-624 frame carries 1 248 bytes of ids on top of 512 bytes of
data: more than three times the size of a typical frame. Roughly 2 in 500
frames need over 900 bytes. That matches the reported symptom — rare and
isolated, not every frame.

This is not only cosmetic. Those frames jump several QR versions, and the
largest cannot be rendered within the capacity limits the app enforces,
so they are either unreadable or not emitted at all.

## Options

**Cap the degree in the emitter.** One line, no format change. Measured
cost in frames needed to decode, as a multiple of k:

| k | no cap | cap 16 | cap 32 | cap 64 |
|---|---|---|---|---|
| 100 | 1.53× | 1.43× | 1.47× | 1.53× |
| 500 | 1.27× | 2.44× | 1.43× | 1.25× |
| 1 000 | 1.07× | 2.54× | 2.09× | 1.37× |

**Rejected.** At k=1000 a cap of 16 takes the overhead from 1.07× to
2.54×, and even a cap of 64 costs 1.37×. Capping breaks the property that
makes a fountain code worth using, and more than doubles transfer time on
a large file.

**Derive the ids from the seed on the receiver.** `makeFrame` is already
deterministic in `(seq, seed)` — the receiver has both, and the seed
travels in every frame. It currently uses the transmitted ids instead of
recomputing them. Dropping the list makes every frame exactly the same
size, which removes the flash entirely and shrinks the average frame.

This is the better answer and it is a **wire format change**, which per
`docs/versioning.md` forces a MAJOR even before 1.0. It needs a written
decision first. Open questions for that decision: whether the receiver
should still validate recomputed ids against anything, and what happens
to a receiver that joins mid-transfer (it already learns the seed from
any frame, so probably nothing).

## Not to be confused with

The metadata frame flashing, which was a different cause with the same
symptom and is fixed: a filename-only frame was 37 modules against 141
for a data chunk, so every 32nd frame changed geometry completely. It is
now padded to the chunk size inside the encrypted payload.
