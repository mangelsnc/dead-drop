# DeadDrop Vault — coercion resistance

**Date:** 2026-10-24
**Status:** Design, approved for planning
**Supersedes parts of:** `docs/technical-spec.md` §3.4 and §4 (see *Spec corrections*)

---

## Intent

DeadDrop protects a file **while it travels**. Today it stops protecting it the
moment it lands: `receive_page.dart` writes the decrypted bytes wherever the
user points a file picker, in the clear. The transfer is end-to-end encrypted
and the result sits unprotected on the device.

The Vault extends the guarantee to files that have already arrived, for the
case the product exists for: someone is made to hand over or unlock their
phone.

### Who this is for

A journalist crossing a border with a leak. An activist whose phone is taken
at a checkpoint. Someone unlocking their phone with a person watching over
their shoulder. The failure mode is not "data breach" — it is a person in a
room with someone who wants what is on their phone.

---

## Goals

1. Received files can be stored **inside** DeadDrop, encrypted at rest.
2. A user under coercion can open the app and show a **plausible, working**
   environment that is not their real one.
3. Nothing about the app reveals that a second environment exists — or could
   exist.
4. The protection degrades honestly: every limit is stated, nothing is
   promised that the implementation cannot deliver.

## Non-goals

- Protecting against an attacker who has both the device **and** the real
  passphrase. Out of scope; no technical answer exists. The user decided this
  explicitly.
- Protecting against sophisticated forensic analysis with unlimited time.
- Hiding that DeadDrop is installed. The app does not disguise itself.
- Replacing the OS disk encryption. This is a layer on top.

## Anti-goals

Things that would make this a failure even if it worked:

- **Any observable difference between the two environments.** Timing, layout,
  error text, file-count hints, settings entries. One tell voids the feature.
- **Shipping decoy content with the app.** Identical stock files across
  installations are a signature: an attacker who has seen one DeadDrop decoy
  recognises the next. The user supplies their own.
- **Promising erasure the storage medium cannot deliver.** See *Self-destruct*.
- **Making the vault mandatory.** A DeadDrop that always has a locked vault
  advertises that there is something to protect.
- **A UX so punishing that users pick weak passphrases.** Friction is paid in
  entropy. (Tension with the point above; see *Decisions*.)

---

## Shape

### The vault is opt-in, and it is a section — not a lock screen

Off by default. Enabled in Settings. Until then the app behaves exactly as it
does today, and the vault UI does not exist anywhere in the interface.

**The app never gates launch behind a passphrase.** Send and Receive stay
reachable immediately, exactly as now. Once a vault exists, a Vault section
appears; opening *that* asks for the passphrase.

This resolves a contradiction in an earlier draft. A launch prompt that appears
only when a vault exists *is itself the tell*: an attacker seeing a passphrase
screen knows there is something to open, which is precisely what
"indistinguishable" was meant to buy. Putting the passphrase on the section
instead means an unopened vault looks like a feature the user never enabled.

It also keeps the cost off users who do not want the feature: no Argon2id
derivation on every launch.

**Consequence for the decoy:** the environment is scoped to the vault section,
not to the whole app. Inside the vault, the decoy shows its own files and no
Security settings. Outside it, the app is the same for everyone.

### Choosing where a file lands

When a transfer completes, the user picks:

- **Save to device** — current behaviour, plaintext, via the file picker
- **Save to vault** — encrypted, inside the app

If no vault has been set up, the second option is not shown. Not greyed out —
absent.

### Two environments inside the vault, no mode switch

The vault does not know how many environments it holds. It takes the
passphrase, attempts to unwrap each stored environment key, and opens whichever
one succeeds. If none do, "incorrect passphrase".

```
passphrase A ──► unwraps environment 1 ──► real files
passphrase B ──► unwraps environment 2 ──► decoy files
anything else ──► "incorrect passphrase"
```

A wrong passphrase and a non-existent second environment are the same event.
There is no flag, no count, no "duress mode" setting to discover — the Security
section of Settings is absent inside the decoy environment.

### What the attacker sees

A user coerced into opening the vault types the decoy passphrase. The vault
opens: same layout, same typography, same colours, same working actions.
Different files.

The decoy is fully functional — files open, send, and delete. A file that
cannot be opened gives the trick away. Its Settings show no Security section,
so there is nothing to find that suggests a second environment.

Outside the vault the app is identical for everyone, because the vault is a
section rather than a gate. An attacker who never opens it sees an ordinary
DeadDrop.

---

## Decisions made

### Passphrases, not PINs

The spec said "real PIN (minimum 6 digits), decoy PIN (minimum 4)". That is
replaced. Measured, at 10,000 guesses/second against a stolen copy of the
storage:

| Secret | Combinations | Mean time to break |
|---|---|---|
| 4-digit PIN | 10⁴ | 0.5 seconds |
| 6-digit PIN | 10⁶ | 50 seconds |
| 8-digit PIN | 10⁸ | 1.4 hours |
| 10-char alphanumeric | 8.4×10¹⁷ | >1,000,000 years |
| 5-word passphrase | 2.8×10¹⁹ | >45,000,000 years |

Passphrases are the default form offered, because they are easier to type on a
phone than `X7#mQ2!v` at equal or better entropy.

**Rate limiting is required but is not the defence.** It only binds an attacker
who uses the app. One who images the storage and attacks the copy never meets
the counter. Against that attacker only the search space and the per-guess cost
of Argon2id apply — which is why the secret has to be large.

### Strength is enforced, not just displayed

A minimum strength is required to set a passphrase, with a live indicator.

Measure **estimated entropy**, not composition rules. "12 characters with an
uppercase, a digit and a symbol" accepts `Password1!`. A zxcvbn-style estimate
that recognises dictionary words, keyboard patterns and substitutions measures
the thing that matters. *(Builder's call: exact threshold and library.)*

The user's position, recorded: the weakest link is the user, and it is their
life at stake, so they price the risk. The minimum exists because someone
choosing `MiCasa2024` believes they are being careful — they are mistaken
about the risk, not accepting it.

### No biometrics

Face or fingerprint unlock is excluded. It permits exactly one identity, which
destroys the decoy, and it can be used on an unwilling person by holding the
phone to their face. The passphrase is typed every time. Accepted UX cost.

### Identity and TOFU state are per-environment *(my call)*

`IdentityStore` and `TofuStore` are global today — one Ed25519 identity and one
known-senders set, at fixed keys in OS secure storage. They must become
environment-scoped.

If they stay shared, an attacker inside the decoy sees the **real** identity
fingerprint, and every file the victim ever sent is attributable to the same
install. That is a cross-environment correlation the threat model does not
survive, and it voids the point of a separate environment.

The decoy also needs a plausible known-senders history: an empty TOFU list
beside a populated decoy file list is internally incoherent, which the
"coherent" property forbids.

This widens the blast radius — it refactors working crypto plumbing rather than
only adding new code — and the plan should account for that.

### Timing equality covers unlock-to-first-paint *(my call)*

The bound is measured from passphrase submission to the file list being
rendered, not just to key derivation.

Derivation parity alone is insufficient: a decoy holding 4 files paints faster
than a real vault holding 200, and that difference is observable with a
stopwatch. The implementation must not leak content volume through render time.

**Unlock always performs a fixed number of derivations**, whatever the outcome.
Trying environment keys sequentially would make a wrong passphrase cost N
derivations and a correct one cost 1 — an order-of-magnitude tell.

### A `crypto_pwhash` spike is the first task *(my call)*

Nothing in this repo has used Argon2id. `sodium_libs` is pinned at `2.2.1+6`
and discontinued upstream, and the fixed-derivation-count requirement above
means unlock may need N × 64 MB concurrently — a real OOM risk on Android 8,
the minimum target.

Before committing to the §3.4 parameters, verify on a low-end device that
`crypto_pwhash` is exposed by the pinned binding and that the memory cost is
survivable. The parameters may be re-tuned **with justification recorded**;
they were chosen for a 6-digit PIN, and the secret is now a passphrase, so the
original reasoning no longer transfers unexamined.

### Decoy content comes from the user

The app ships no filler. On setting up the decoy environment the user is told
that an empty space is suspicious and prompted to add their own innocuous
files.

### Self-destruct: opt-in, off by default

The original objection stands and is recorded: an attacker can trigger the wipe
deliberately by failing N times, and destroying the data may be exactly what
they want. A serious attacker images the storage first, so the counter never
applies to them. It constrains only an attacker who plays fair.

It stays as a configurable option because the user should price their own
exposure, but it is **off by default** and the UI must state plainly that an
attacker can trigger it on purpose. Someone enabling it is choosing "I would
rather lose this than have it seen."

**It destroys the wrapped key, not the files.** On flash with wear-levelling,
overwriting does not guarantee the bytes leave the chip, so "we erased your
files" would be a false promise. Discarding the few bytes of wrapped key makes
the content unreadable whether or not it physically remains — faster, reliable
on flash, and honest about what it claims.

---

### Platform priority: mobile first

Android and iOS are the primary targets for this feature. Desktop
(Linux/Windows/macOS) follows.

This **inverts** `technical-spec.md` §5.1, which makes desktop P0 and mobile a
P1 stretch goal. Recorded as a deliberate change, not an oversight: the phone
is the natural interface for a camera-and-screen transfer, and it is the device
that gets taken at a checkpoint.

It also matters technically. On Linux a wrapped key in GNOME Keyring is a
**visibly named entry** — an artefact that reveals the vault exists, which the
anti-goals forbid. iOS Keychain and Android Keystore hide it far better. The
desktop artefact problem is real and must be solved before desktop ships; it
does not block mobile.

---

## Constraints

- **Zero home-grown cryptography.** libsodium with default parameters.
  Argon2id via `crypto_pwhash` for key derivation; the existing
  XSalsa20-Poly1305 construction for content.
- **Zero network.** No feature may require connectivity.
- **Identical timing between environments.** Same Argon2id parameters for both.
  Unlock must take the same measurable time whichever passphrase is entered,
  and a wrong passphrase must cost the same as a right one. No artificial delay
  after a failure — that would reveal the app distinguishes cases.
- Flutter 3.24.5, pinned in `.fvmrc`. `sodium_libs` is pinned at `2.2.1+6` and
  is discontinued upstream; do not bump it as part of this work.
- The documentation must mark every part of this as unimplemented until it
  ships. `README.md` and `docs/security.md` currently carry that warning and it
  stays accurate until the code lands.

---

## Left to the builder

- **Storage engine.** SQLCipher versus a custom encrypted file tree was raised
  and deliberately not settled here. Whichever is chosen must leave no artefact
  revealing how many environments exist — including file sizes, counts, and
  directory structure. Argue the choice in the plan.
- Key hierarchy: the shape (passphrase → Argon2id → key-encryption key →
  wrapped per-environment data key) is implied by the self-destruct decision,
  but the exact construction is the builder's, using libsodium primitives.
- Rate-limiter design: backoff curve, where the counter lives, and how it
  survives app restarts without becoming an artefact that reveals state.
- Entropy threshold and estimator library.
- Whether the real and decoy environments are separate stores or one store with
  two wrapped keys — constrained by the indistinguishability requirement above.
- Migration: there are no existing vaults, so there is nothing to migrate.

---

## Spec corrections required

`docs/technical-spec.md` must be updated alongside the implementation:

- **§3.4** is titled "PIN derivation" and specifies PINs. Replace with
  passphrases; the Argon2id parameters themselves (t=3, m=64MB, p=4) stand.
- **§4.2** specifies "Real PIN (minimum 6 digits)" and "Decoy PIN (minimum 4
  digits)". Replace with the passphrase requirement above.
- **§4.4** recommends app-generated decoy content. Replace with user-supplied.
- **§4.8** describes self-destruct as wiping both environments. Clarify that it
  destroys the wrapped keys, and record that it is off by default.
- **§5.1** makes desktop P0 and mobile a P1 stretch goal. For this feature the
  priority is inverted; see *Platform priority*.

---

## Smaller calls *(mine, flagged for review)*

- **A vault with no decoy is allowed.** Enabling the vault creates one
  environment and asks for one passphrase. Adding a decoy is a separate,
  clearly-labelled step. Forcing decoy setup at creation would make the common
  case worse without making anyone safer, but the UI must not let a user
  believe they have coercion resistance when they have only encryption — Goal 4
  applies to the default configuration, not just the documentation.
- **Setup is not "complete" until the decoy has content.** When a user does
  create a decoy, an empty one is worse than none: it reads as a space
  something was removed from. The flow should not present an empty decoy as
  finished.
- **Viewing a vault file must not write plaintext outside the vault.** Handing
  it to the OS to open defeats the feature. The app needs at minimum an
  in-app preview for the common types, and an explicit "export, leaves the
  vault" action for everything else. The builder decides which types; the
  constraint is that silent plaintext export cannot happen.

---

## Testing

The security properties here are mostly *negative* — things that must not be
observable. They need tests that would fail if the property broke:

- Unlock timing: real, decoy, and wrong passphrase within a tight bound of each
  other, measured across repeated runs.
- No artefact on disk distinguishes one environment from two.
- Decoy environment exposes no Security settings entry.
- Wrapped-key destruction leaves content unreadable.
- Strength estimator rejects known-weak passphrases (`Password1!`, `MiCasa2024`)
  and accepts generated passphrases.

A feature whose whole value is indistinguishability cannot be verified by
"it works" — the tests must assert the absence of tells.
