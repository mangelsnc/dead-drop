# Device test plan — Redmi Note 14 + macOS

Build to use: the one from run `40848147548`, on both devices.

> **Both devices must run this same build.** The wire format changed to
> v3 (chunk ids are derived, not transmitted). A v2 device and a v3
> device will not talk to each other, and the failure looks like "it
> scans but nothing decodes".

Check first, on both: **Settings → About** should read
`Version 0.9.1 (…)`. If either says "Development build", that device is
not running a CI build and the rest of the plan is invalid.

---

## Read this before you start

Two things will otherwise read as failures when they are not.

**The chunk count stays near zero for most of a transfer.** Belief
propagation reveals almost nothing until it reaches critical mass, then
cascades. Measured on a 1 MB file at 512 B (k=2048), with perfect
frames: 1 chunk after 250 codes, 12 after 1024, finished at 2308. Judge
progress by the **percentage**, which now counts captured-but-unrevealed
frames. The chunk count is detail.

**The quality bar cannot reach "Good" at a low frame rate.** It measures
what fraction of *camera* frames decoded, over the last 30. The camera
runs at roughly 12–30 fps; the sender at 8. So at best about one camera
frame in three carries a new code, and the rate tops out near 0.3 — just
at the "Weak"/"Reading" boundary. "Good" needs 0.6, which is
unreachable below about 15 fps.

This is a defect in the indicator, not in your aim, and it is why only
the static handshake QR ever showed green. **Do not tune anything to try
to make the bar go green.** Test 6 measures it on purpose; everywhere
else, ignore the bar and watch the percentage.

---

## What the arithmetic says to expect

Pixels per QR module — about 3 is needed, below 2 is hopeless. Camera
column assumes the code fills 60% of a 1280px frame.

| chunk | EC | modules | camera | phone as sender | Mac as sender |
|---|---|---|---|---|---|
| 256 | M | 81 | 9.5 | 4.8 | 8.9 |
| 512 | L | 93 | 8.3 | 4.2 | 7.7 |
| 512 | M | 105 | 7.3 | 3.7 | 6.9 |
| 512 | Q | 125 | 6.1 | 3.1 | 5.8 |
| 1024 | M | 145 | 5.3 | **2.7** | 5.0 |
| 1024 | Q | 169 | 4.5 | **2.3** | 4.3 |

So: every combination should work with the **Mac as sender**. With the
**phone as sender**, 1024 B is below the threshold and is expected to
struggle — that is a known limit, not a bug to report.

Time for 1 MB, at ~1.15 codes per chunk:

| chunk | codes | at 8 fps | at 16 fps |
|---|---|---|---|
| 256 B | ~4710 | 9.8 min | 4.9 min |
| 512 B | ~2355 | 4.9 min | 2.5 min |
| 1024 B | ~1178 | 2.5 min | 1.2 min |

**Use a small file for most tests.** A 50–100 KB photo at 512 B is about
120–230 codes, well under a minute. Keep the 1 MB file for test 5 only.

---

## Before each test

- Both screens at **full brightness**, auto-brightness off.
- No lamp or window reflecting on either screen.
- Hold the phone steady — brace your elbows, or prop it against
  something.
- Start with the code filling **about two thirds** of the camera
  preview. Adjust from there.

Record for each: did it complete, how long, and the final percentage if
it did not.

---

## Test 1 — Mac sends, phone receives (the baseline)

File: a photo of **50–100 KB**.
Settings: whatever the handshake picks. Note them.

1. Phone: Receive a file. Mac: Send a file, pick the photo.
2. Mac scans the phone's handshake QR.
3. Phone scans the Mac.

**Expect:** completes in under a minute. The percentage climbs steadily
even while the chunk count sits near zero.

**Watch for:** the progress block should be visible **above** the camera
without scrolling — including the first time, when the "unknown sender"
prompt also appears. That prompt only shows once per sender; to see it
again, clear the phone's known senders in Settings.

---

## Test 2 — Phone sends, Mac receives

Same file, reversed.

**Expect:** completes. The Mac now captures at 1280×720 rather than
320×240, which is what made this direction fail before.

**Watch for:** the QR on the phone should fill the width without the
frame counter or the buttons overlapping it.

---

## Test 3 — Chunk size sweep (Mac sends)

Same 50–100 KB photo each time, EC left at **M**, fps at **8**.

| chunk | expected |
|---|---|
| 256 | works, slowest |
| 512 | works |
| 1024 | works — the Mac has the screen for it |
| 2048 | only selectable at EC L; the others should be greyed out |

The point of 2048 here is the **UI**, not the transfer: confirm that
picking it disables M, Q and H, and that picking M or Q disables 2048.

---

## Test 4 — Chunk size sweep (phone sends)

Same sweep, phone as sender.

**Expect 256 and 512 to work. Expect 1024 to be poor or to fail** —
2.7 px per module on a phone screen. This is the limit in the table
above, already pinned by a test in the repo. Confirming it behaves as
predicted is the result; it is not a bug.

---

## Test 5 — The 1 MB photo, end to end

Your original case: 1 MB, 512 B, 8 fps, Q, Mac sending.

**Expect ~5 minutes and completion.** The point is to let it run to the
end rather than cancelling, so we find out whether it finishes.

Note the percentage at 1, 2, 3 and 4 minutes. It should rise roughly
linearly. If it stalls — the same number twice a minute apart — that is
a real finding, and worth a screenshot.

Then repeat the same file at **1024 B and 16 fps**, which should take
about 1.2 minutes. Compare.

---

## Test 6 — The quality bar (measurement, not tuning)

Phone receiving, Mac sending, 512 B.

At **8 fps**, then **16 fps**, then **24 fps**, note the best reading
the bar reaches while holding steady at a good distance.

**Expect** Weak/Reading at 8 fps and better at 16–24. This confirms
whether the ceiling is the frame rate, as predicted above. Report the
three readings; the fix is mine, not a setting of yours.

---

## Test 7 — Interruptions

Mid-transfer, with a 1 MB file running (Mac sends, phone receives):

1. Look away for ~10 seconds, then point back. **Expect** it to carry
   on from where it was, not restart.
2. Press Cancel transfer on the phone, then start scanning again.
   **Expect** it to resume without the Mac having to re-scan your key.
3. Let the phone screen time out if it will. **Expect** it not to — the
   receive screen holds a wake lock.

---

## Test 8 — The UI changes from this round

Quick checks, no transfer needed.

- **Phone, Send → Options:** the error correction selector shows four
  even segments, `L / M / Q / H` over `(7%) (15%) (25%) (30%)`, with no
  checkmark and no wrapped text.
- **Mac, same screen:** the selector spans the width instead of
  huddling at the left.
- **Both:** the (i) beside Chunk size, Frame rate and Error correction
  opens an explanation and closes on "Got it".
- **Both:** Settings → About shows a version.

---

## What to send back

For each test: completed yes/no, elapsed time, final percentage, and the
settings used. Screenshots for anything that looks wrong — and for test
6, just the three bar readings.

The things I most want to know:

1. Does test 5 actually finish?
2. Does test 2 (phone → Mac) work now?
3. Does the quality bar improve with frame rate, as predicted?
