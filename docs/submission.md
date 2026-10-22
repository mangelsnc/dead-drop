# DeadDrop — #cryptograFREE Submission

> **⚠️ Reconstruction notice (internal — remove before submitting).**
> The original `submission.md` was authored on 2026-10-18 but was never committed to
> git and was lost when the working environment reset. This file is a **faithful
> reconstruction** built on 2026-10-21 from the authoritative source documents that
> remain in the repo (`value-proposition.md`, `technical-spec.md`, `security.md`,
> `user-guide.md`, `reproducibility-verification.md`, `spike/DECISIONS.md`). Every
> claim below is traceable to one of those documents. It incorporates the improvements
> from the cross-review (`docs/submission-review.md`). **The team must re-validate this
> against any surviving copy of the original before it is treated as final.**

**Challenge:** #cryptograFREE — RootedCON + Criptored
**Project:** DeadDrop
**Repository:** https://github.com/mangelsnc/dead-drop (public, MIT)
**Submission deadline:** 28-Dec-2026 23:59 (mainland Spain time)

---

## 1. Title and summary

**DeadDrop — air-gapped, encrypted file transfer between two devices, with no network.**

DeadDrop lets two people in the same room exchange encrypted files using only a screen
and a camera — animated QR codes, no network, no Bluetooth, no USB. End-to-end
encryption with libsodium protects files before they leave the sender's device; a
decoy PIN opens a convincing fake environment if the user is ever forced to unlock the
app. Built for journalists, activists, lawyers and ordinary citizens, DeadDrop is
cross-platform (Windows, macOS, Linux), open source, and designed so that anyone — no
technical knowledge required — can hand a file to someone standing next to them
without leaving a trace.

*(≈95 words.)*

---

## 2. The problem

Modern encryption protects data **in transit over the network** and **at rest on
disk**, but it leaves one critical moment uncovered: **the physical handover of
sensitive information between two people who cannot afford to leave a trace.**

Today, two people face to face who want to exchange a file without exposing it have
only bad options:

- **Send it over the internet** (email, messaging, cloud): leaves metadata on
  third-party servers — *who talks to whom, when, and how much* — even if the content
  is encrypted.
- **Bluetooth / AirDrop / local network:** they emit detectable signals and are
  recorded in system logs.
- **A USB drive:** a classic malware vector and the first thing seized at a checkpoint.

Three concrete people need this solved (full scenarios in `docs/value-proposition.md`):

- **The journalist** handing a leak to her newsroom before crossing a border.
- **The activist** passing evidence of arbitrary detention to a lawyer, assuming his
  device is already watched.
- **The ordinary citizen** who simply does not want her personal documents passing
  through third-party servers.

**Why now.** The challenge frames privacy as a fundamental right in accelerated
erosion, and DeadDrop is built directly on the articles the challenge cites:

- **UDHR Art. 12** — no arbitrary interference with correspondence. DeadDrop restores
  it in the act of transfer: there is no observable correspondence because there is no
  channel.
- **UDHR Art. 19** — the right to *seek, receive and impart* information regardless of
  frontiers. Network surveillance turns that right into a physical risk; DeadDrop
  protects it.
- **UDHR Art. 20** — freedom of association. An air-gapped transfer generates no edges
  in any observable social graph.

Three converging pressures make this urgent: EU mass-scanning debates ("Chat Control")
pushing surveillance toward metadata and devices; commercial state malware (Pegasus)
proving the connected device is the weak link; and physical coercion — the vector
conventional disk encryption does not address.

---

## 3. The solution

**DeadDrop moves a file between two devices as light.** The sender's screen renders a
sequence of animated QR codes; the receiver's camera reads them. Nothing is emitted
over any radio, cable, or network — the transfer works with airplane mode visibly on
in both devices.

How it works, at a high level:

1. **Optical handshake.** The receiver shows a static QR containing its ephemeral
   public key; the sender scans it. Not even the keys touch a network.
2. **End-to-end encryption.** The file is encrypted on the sender's device with
   libsodium (X25519 key exchange + XSalsa20-Poly1305 authenticated encryption), and
   the session header is signed with Ed25519 so the receiver knows the file comes from
   the person in front of them.
3. **Fountain-coded transfer.** The encrypted file is split into chunks and encoded
   with an LT fountain code, so the receiver simply scans until it has enough frames —
   lost or misread frames are absorbed by design (the channel is lossy; the protocol
   is built for it).
4. **Duress mode (planned).** A decoy PIN opens a convincing fake environment while
   real data stays invisible; optional self-destruct after failed attempts.

**Why it is different.** As of today, DeadDrop is the only tool that combines four
properties in a single open-source, cross-platform product (full comparison table in
`docs/value-proposition.md` §4):

1. **Real air-gap** — the data channel is optical; the absence of emission is
   verifiable.
2. **End-to-end encryption** with an optical key exchange.
3. **Built-in plausible deniability** (decoy PIN, self-destruct).
4. **Designed for non-technical users** — three steps, no configuration, no exposed
   cryptographic concepts.

Existing tools (AirGap, libcimbar/txqr, magic-wormhole, OnionShare, LocalSend,
VeraCrypt, USB) each solve **one** of these. None solves all four at once.

---

## 4. Challenge category coverage

DeadDrop covers **4 of the 5** challenge categories with a single end-to-end solution,
and takes an honest position on the fifth.

- **Anonymity:** there is no network metadata to anonymise, because there is no
  network. Structural anonymity, not probabilistic.
- **Encryption:** E2E with libsodium; ephemeral per-session keys; forward secrecy.
- **Local machine:** everything happens on-device; the app works 100% offline; the
  planned duress mode protects the device itself.
- **Evasion:** the air-gap evades the surveillance channel by design (there is no
  channel to monitor). **The application binary requests no network permission, and
  the transfer completes in airplane mode** — the evasion is demonstrable, not just
  claimed.
- **Steganography (honest position):** the QR channel is overt, not covert — DeadDrop
  does not hide that a transfer is happening, only what is transferred and between
  whom. We deliberately do not overclaim this category; a steganographic mode (hiding
  the frames inside an innocuous image or video) is documented as future work with an
  extension point reserved in the protocol.

---

## 5. Ease of use for a non-technical audience

The non-technical person rules the UX — this is a stated, non-negotiable project rule.
The test question for every feature is: *"would someone who doesn't know what a public
key is understand this?"*

- **Three-step flow:** pick a file → show the QR → confirm receipt. No configuration,
  no accounts, no visible cryptographic vocabulary.
- **Plain-language documentation:** `docs/user-guide.md` and an in-app flow written
  for non-technical readers, in Spanish and English.
- **Banned vocabulary:** the UI never exposes terms like "public key," "nonce," or
  "fountain code"; the README explains the whole mechanic in 30 seconds with a single
  diagram.

> **Usability evidence — status.** A moderated usability test **protocol** has been
> defined (`docs/usability-test.md`) with target participant profiles, test tasks, and
> hypotheses. **No human testing sessions have been conducted yet** — the protocol is
> ready for execution before the MVP freeze. High-fidelity mockups and a WCAG 2.1 AA
> accessibility audit are being re-integrated into the repository (see
> `docs/submission-review.md`, Finding F1). *(We do not cite usability figures we
> cannot stand behind.)*

---

## 6. Technical and code quality

**Stack.** Flutter (single codebase → Windows, macOS, Linux, and mobile) + libsodium
for all cryptography. Zero home-grown cryptography: every primitive is libsodium with
default parameters.

**Measured, reproducible performance** (from `spike/src/benchmark_results.json`,
matching `docs/technical-spec.md` §6.2):

| Metric | Target | Measured (spike) |
|---|---|---|
| Effective throughput | ≥ 3 KB/s | **3.9 KB/s** (8 KB, 512 B chunks, 10% loss) |
| Frame-loss tolerance | ≥ 30% | **50%** (completes with half the frames lost) |
| Fountain overhead | ≤ 1.5× | **1.31×** (21 frames for 16 chunks) |
| Max file size (MVP) | — | **100 KB** (~25 s of camera hold) |

**Build verifiability.** The Linux build is **bit-for-bit reproducible**: the same
commit and pinned toolchain produce an identical SHA-256 hash of the binary. This is
experimentally verified and documented in **`docs/reproducibility-verification.md`**,
with the root cause of non-reproducibility, the packaging fix, and CI enforcement.
`docs/reproducible-builds.md` documents the process; SHA-256 checksums are published
with each release; CI is public on GitHub Actions.

**Testing.** An integration test suite covers the round-trip happy path (1 KB / 100 KB
/ 1 MB) and 50% frame-loss recovery. Protocol and crypto changes require boundary,
malformed-input, and adversarial-input tests.

**Normative documentation.** A 49 KB technical specification (`docs/technical-spec.md`)
with the wire format, test vectors, and a security checklist; a security model
(`docs/security.md`) that states plainly what is and is not protected.

---

## 7. MVP plan (delivery 10-Feb-2027)

**In the MVP:** one-way animated-QR transfer with fountain-code error correction and
resume on frame loss; E2E encryption with libsodium; **Windows, macOS and Linux
builds**; duress mode (decoy PIN); optional self-destruct; the 3-step UX;
plain-language documentation (ES/EN); reproducible builds with public CI; open source
(MIT) from day one.

**Platform compliance.** Windows, macOS and Linux are a **non-negotiable challenge
requirement, and all three compile in CI today.** The MVP prioritisation (P0/P1) is a
*polish* ordering, not a capability statement — the required desktop platforms are not
deferred; they are built continuously by CI. Mobile (Android/iOS) is scored by the
challenge as *extra* and is on the post-MVP roadmap.

**Out of the MVP (with rationale, full table in `value-proposition.md` §6):**
simultaneous two-way transfer; steganographic mode; multi-file/folder trees;
password-manager/hardware-key integration; "room" mode (>2 devices); translations
beyond ES/EN.

**Cut-off criterion:** anything not indispensable for the live demo to work in front
of the jury is not built before 10-Feb-2027. The priority is a small, solid, auditable
core that can be demonstrated live.

**Timeline:** internal submission target **21-Dec-2026**; official deadline 28-Dec-2026
23:59 (mainland Spain); MVP 10-Feb-2027; jury decision 28-Feb-2027; award ceremony at
RootedCON 2027 (ANON track, 6-Mar-2027).

---

## 8. Team and license

DeadDrop is open source under the **MIT license**, public from the first commit, with
all decisions, code and documentation in the open
(`https://github.com/mangelsnc/dead-drop`).

**Legal and ethical standing** (full analysis in `docs/security.md` and the legal
review): DeadDrop is 100% legal and ethical by design. It is auditable open source,
exfiltrates nothing, does not hide its own existence, and frames its use within
fundamental rights (GDPR-compliant; consistent with ECtHR *Podchasov* 2024; in the
tradition of VeraCrypt/Rubberhose plausible-deniability precedents). On dual-use: every
privacy tool (Tor, Signal, VeraCrypt) is dual-use; the right to privacy is not
conditioned on prior innocence.

---

*Version 1.2 · 2026-10-22 · Reconstructed from authoritative in-repo sources. F0
resolved: usability-test.md corrected to protocol-only (no fabricated results).*
