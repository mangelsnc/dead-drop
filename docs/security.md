# Security in DeadDrop

This document explains **what DeadDrop protects, against whom, and what it does not protect**. It comes in two parts:

1. **In plain language** — for anyone who uses the app and wants to understand what to expect from it.
2. **Technical version** — for auditors, security researchers and the challenge jury.

Honesty about limits is as important as the guarantees. A privacy tool that promises the impossible is a dangerous tool.

> ⚠️ **Implementation status (2026-10-25):** DeadDrop is in active development. **Transfer encryption, the vault (at-rest encryption), the decoy environment and self-destruct are now implemented.** Self-destruct is **off by default** — it does nothing unless you turn it on yourself in Settings. This work has been exercised by the automated test suite and by hand on Android and Linux devices; it has **not yet been tested on iOS or macOS**. Read the limits in this document — especially the passphrase and self-destruct sections — before relying on any of it, and particularly before a border crossing or any situation where you might be searched.

---

# Part 1 — In plain language

## What DeadDrop protects

### 1. The content of your files during handover ✅ Implemented

When you pass a file with DeadDrop, the content travels protected end to end: it is sealed on the sending device and only opened on the receiving device. No one in between — not even someone recording the screen with another camera — can read it.

### 2. The non-existence of a network trail ✅ Implemented

DeadDrop does not use the internet, WiFi, Bluetooth or cables. The file travels through light: from the screen to the camera. That means **there is no metadata on any server**: no company and no network observer can know that the transfer happened, who took part, or when. It is not that the trail is hidden — it is that it does not exist.

### 3. Your device during a forced search ✅ Implemented (vault is optional; iOS/macOS untested)

DeadDrop has a **vault**: a passphrase-protected place to store received files, separate from your device's ordinary file storage. Files you choose to save into the vault are encrypted at rest. You can also set up a **decoy passphrase**: a second, independent environment inside the same vault, protected by a different passphrase. Opening the app and entering the real passphrase shows your real files; entering the decoy passphrase shows only whatever you have put in the decoy. Nothing about the app's behaviour, timing, or interface reveals that a decoy exists, or that you have one, to someone who only has the decoy passphrase.

**You must set this up before you need it.** The vault is a feature you opt into, not something that protects you automatically: a file saved to your device outside the vault (e.g. through your OS file picker rather than "save to vault") is not protected by any of this. A decoy you never populated with credible content is not convincing — the app does not generate decoy content for you; you have to put your own files into it.

**Self-destruct is available and off by default.** If you turn it on in Settings, 10 consecutive failed passphrase attempts will discard the keys protecting both the real and the decoy environment, making their contents permanently unrecoverable. Turning it on is a real trade-off — read "Self-destruct: what it actually does" in the technical section below before enabling it; in particular, it can be triggered deliberately by an attacker who simply keeps guessing, and it does not erase the files themselves, only the keys.

### 4. File integrity ✅ Implemented

DeadDrop verifies that what arrives is exactly what was sent. If even a single byte is missing, the app warns you instead of handing you a corrupt or tampered file.

## What DeadDrop does NOT protect

This is just as important. DeadDrop does **not** protect you from:

- **An already-compromised device.** If your computer has a virus or malware installed (a trojan, a keylogger), that malware can read your files before you send them or after you receive them — including inside an unlocked vault. DeadDrop protects the channel and, once unlocked, the vault's own storage; it does not cure a sick device.
- **Cameras in the room.** If someone physically records the sender's screen *and also* compromises the receiving device, they could combine both. Against physical surveillance of the place, the defence is choosing the place well.
- **The other person revealing the file.** Once received, the file is in the recipient's hands. DeadDrop cannot stop that person from sharing, printing or handing it over. Trust the recipient as you would when handing them a physical envelope.
- **Your own behaviour.** If you talk about the transfer on a tapped phone, if you arrange to meet the recipient over watched channels, or if you carry the device to a checkpoint announced in your own email, no app can help you. Security is a chain: DeadDrop is the handover link; the other links are yours.
- **Files you never put in the vault.** Anything saved outside the vault (e.g. through your OS's own file picker instead of "save to vault") is an ordinary file, protected only by your operating system (user account, disk encryption such as FileVault/BitLocker/LUKS if enabled). The vault only protects what you deliberately store inside it.
- **A decoy you have not prepared.** The decoy only works if you set it up *beforehand* with content you have chosen, and keep it credible. There is no built-in fake content — an empty or thin decoy is itself suspicious.
- **Someone forcing you to reveal the real passphrase.** If an attacker knows a decoy might exist and is willing to keep pressuring you past the first passphrase, no technical measure can stop them from eventually getting the real one. The decoy buys you a plausible stopping point, not an unbreakable one.
- **Your passphrase being weaker than it looks.** A phrase that scores as "strong" by length and character variety can still be an easy guess if it is a well-known quote or saying — see "A note on passphrase strength" below.
- **An attacker who copies your device's storage and attacks it offline.** The app's rate limiting only slows someone typing passphrases into the running app. Someone who images your storage and attacks the copy on their own hardware is not slowed by it at all — your passphrase's actual length and randomness is the only thing protecting you from that attacker. Use a generated passphrase rather than one you make up yourself.
- **Self-destruct erasing the files from the storage medium.** Self-destruct discards the keys that protect your files, not the files' bytes. On the flash storage phones and SSDs use, the app cannot guarantee that discarded data is physically gone — see the technical section.
- **A generated passphrase you copy to the clipboard.** The app lets you copy a generated passphrase so you can save it somewhere, which is convenient but puts it, in plaintext, on your operating system's ordinary clipboard. That clipboard may sync across your other devices (e.g. a universal/cloud clipboard) or be readable by other apps on the same device. Clear your clipboard, or avoid copying the passphrase, if that exposure matters for your situation.

## Common-sense advice

- Set up the vault, and the decoy if you want one, **before** you need them, not the day before a trip — and keep the decoy's content credible and current.
- Prefer the app's **generated passphrase** over typing your own. A memorable sentence you make up yourself is often weaker than it feels (see below); a generated passphrase gives you a concrete guarantee instead.
- If you enable self-destruct, understand first that it can be triggered on purpose by an attacker who just keeps guessing, and that it discards keys, not files — read the technical section before turning it on.
- Turn on airplane mode on both devices during the transfer if you want a visible, demonstrable guarantee that there is no network.
- Verify your downloads with the published checksums (see below).
- DeadDrop is a tool for in-person handover. For remote communication, combine it with other tools (Signal, Tor) that solve that other problem.

## A note on passphrase strength

The app estimates how strong a passphrase is as you type it, but that estimate has a real blind spot: it has no way to know that a phrase is *famous*. A well-known line like "tobeornottobethatisthequestion" scores roughly 88 bits by the estimator's own arithmetic — comfortably "strong" — while an attacker who simply tries well-known quotes and sayings first might only need to try somewhere in the range of 20-27 bits' worth of guesses to land on it. The estimator measures character-level unpredictability; it does not and cannot measure how many other people might type the same words. This is exactly why the app offers to **generate** a passphrase for you by default: a generated passphrase's strength is a mathematical guarantee (every word drawn uniformly at random from a fixed list), not an estimate. If you choose to type your own phrase instead, treat the strength meter as a floor, not a promise.

---

# Part 2 — Technical version (for auditors)

> **Status:** this section describes the security design of the MVP. Each row of the tables below carries an explicit implementation status: ✅ *Implemented* means working code exists in `app/lib/` today; 📋 *Planned* means a documented design goal with **no implementation**. The concrete parameters will be frozen with the implementation and any change will be documented here. The code is the final reference; this document is the map.
>
> The vault, decoy environment and self-destruct described below are covered by the automated test suite (`app/test/vault/`), which runs on desktop hardware under emulation, and have been exercised by hand on Android and Linux devices. **They have not yet been run on iOS or macOS** — that gap is open and should be closed before anyone relies on this under real coercion on an Apple device.
>
> Hand-testing is not the same as an audit. No independent party has reviewed this code.

## Threat model

DeadDrop is designed against these adversaries:

| Adversary | Assumed capability | DeadDrop's response | Status |
|---|---|---|---|
| **Network observer** (ISP, state, company) | Sees and logs all network traffic of both devices | There is no traffic: the channel is optical (screen → camera). Absence of emission verifiable with a spectrum analyser. | ✅ Implemented |
| **RF proximity observer** | Captures Bluetooth/WiFi/radio in the room | No radio in use. | ✅ Implemented |
| **Optical interceptor** | Records the sender's screen with a camera for the entire transfer | The payload travels E2E encrypted (see below): the recording only produces ciphertext. | ✅ Implemented |
| **Adversary with physical access to the device** | Searches the device, installs the app, inspects it | Files saved into the vault are encrypted at rest with a key derived from a passphrase (Argon2id). Optional self-destruct discards the wrapped keys after N failed attempts. | ✅ **Implemented for files stored in the vault.** Files saved outside the vault (via the OS file picker rather than "save to vault") are not protected by DeadDrop and rely entirely on OS-level protection. |
| **Adversary who coerces the user** | Forces the user to unlock the app | The decoy passphrase opens a second, independently-keyed environment indistinguishable from the real one in behaviour and unlock timing. | ✅ **Implemented**, with the limits below: the decoy must be populated by the user beforehand (no auto-generated content), a determined attacker can still coerce the real passphrase specifically, and this has not yet been tested on iOS or macOS. |

Out of scope (explicitly declared):

- Device compromised at the OS/malware level (rootkits, keyloggers, Pegasus). DeadDrop cannot protect a compromised host; it reduces its network exposure to zero during the transfer, which is what is within its reach.
- Adversary combining full optical recording **and** compromise of the receiving device **and** obtaining its keys.
- Physical covert channel (acoustic/thermal/power-consumption analysis of the screen). Theoretical, outside the model for a product tool.

## Data channel

- **Direction:** one-way sender → receiver in the MVP (role swap with a button).
- **Medium:** animated QR codes (LT fountain code over QR frames, with resume on frame loss — implemented; see `docs/technical-spec.md`).
- **Handshake:** at the start of the session, the receiver shows a static QR with its ephemeral public key; the sender scans it. Not even the keys touch a network. ✅ Implemented
- **Session integrity:** the manifest hash is verified on completion; the receiver confirms the received file matches. ✅ Implemented

## Cryptography

Project rule: **libsodium with default parameters. Zero home-grown cryptography.**

| Use | Primitive (libsodium) | Status |
|---|---|---|
| Session key agreement | X25519, ephemeral per-session keys → forward secrecy | ✅ Implemented |
| Payload encryption | XSalsa20-Poly1305, AEAD with per-chunk authentication | ✅ Implemented |
| Session manifest signature | Ed25519 over the session header | ✅ Implemented |
| File integrity hash | BLAKE2b-256 (`crypto_generichash`), end-to-end manifest check | ✅ Implemented |
| Key derivation from passphrase (data at rest) | Argon2id (`crypto_pwhash`), libsodium's interactive parameter set | ✅ Implemented (`app/lib/src/vault/pwhash.dart`) |
| Data at rest | Each environment's files are encrypted under its own data key; that data key is itself sealed ("wrapped") with `crypto_secretbox` under a key derived from that environment's passphrase. The real and decoy environments use independently-derived keys, share one on-disk store, and nothing in file names, directory structure, file count or file sizes reveals whether a decoy exists | ✅ Implemented (`app/lib/src/vault/vault_keys.dart`, `vault_store.dart`) |
| Self-destruct | Discards the wrapped data keys for both environments after 10 consecutive failed unlock attempts, when the user has explicitly enabled it. Does **not** overwrite the encrypted file contents on disk — see "Self-destruct: what it actually does" below for why, and its limits | ✅ Implemented, off by default (`app/lib/src/vault/attempt_guard.dart`) |

## Plausible deniability — properties

- **Same binary, same unlock flow for both passphrases.** `tryUnlock` (`app/lib/src/vault/vault_session.dart`) always performs exactly one Argon2id derivation per environment slot — real, decoy, or empty — and never returns early once it finds a match. An empty slot (no decoy configured) is derived against using a fixed dummy ciphertext, so its cost is identical to a filled one. `app/test/vault/vault_session_test.dart` proves the derivation count is constant across outcomes; `app/test/vault/timing_test.dart` proves the resulting wall-clock time is indistinguishable, bounding the spread between real/decoy/wrong-passphrase medians to under 80ms under this project's pinned toolchain (see that file for the measurement and how the bound was chosen).
- **The rate-limiting delay precedes every attempt, never follows a failure.** A pause that only appears after a wrong passphrase would itself be a tell. `AttemptGuard` waits before the attempt, identically regardless of what is about to be typed.
- **The decoy space is a real, independently-keyed encrypted environment**, not a detectable "hidden mode" — whatever the user stores in it is as genuinely protected as the real environment.
- **The app stores no indicator that two spaces exist.** The failed-attempt counter's storage key exists whether or not a vault does at all, and is written on both success and failure, so its mere presence (or the act of writing to it) never signals anything.
- **The decoy signs as someone else, and keeps its own address book.** The device identity and the known-senders list are scoped so the decoy environment has its own. An attacker inside it cannot read the real environment's fingerprint, which would otherwise make every file the user has ever sent attributable to the same install, and cannot see who the user has received from. The real environment and the no-vault case deliberately *share* one identity and one address book: they are the same device presenting itself to the same people, and splitting them meant this device's fingerprint changed depending on whether the vault happened to be open, so correspondents had to re-confirm the same sender as a stranger. `app/test/vault/environment_scoping_test.dart` pins both halves of that.
- **What is not covered:** the decoy's *content* must still look credible, and that is entirely on the user — see "A note on passphrase strength" and the decoy-content limits above. Indistinguishable unlock behaviour does not make an empty or implausible decoy convincing.

## Self-destruct: what it actually does

Self-destruct is **off by default**. If enabled, 10 consecutive failed unlock attempts cause the app to discard both environments' wrapped data keys (`VaultController._destroyEverySlot`, which always destroys *both* slots — a surviving decoy would itself prove there had been something to erase).

Read this before turning it on:

- **It discards keys; it does not erase files.** The encrypted file contents are left on disk. Without the wrapped key, they are computationally unrecoverable to anyone without the passphrase — but the bytes themselves are not overwritten.
- **On flash storage with wear-levelling (the case for essentially all phones, SSDs, and most modern storage), erasure cannot be promised even if the app tried to overwrite the data.** The flash controller may have already moved the physical blocks elsewhere, leaving old copies behind that the app has no way to address or overwrite. This is a known, structural limit of flash storage, not a shortcut this implementation took.
- **A wipe interrupted mid-flight (power loss, app kill) can leave one slot destroyed and the other intact.** The code keeps attempting every slot even if one fails, but it cannot guarantee both complete if the process dies partway through.
- **An attacker can trigger it deliberately.** Self-destruct cannot tell a locked-out owner apart from an attacker who simply keeps entering wrong passphrases on purpose to destroy the evidence before it can be examined further. There is no way to add that distinction without giving the counter information it structurally cannot have.
- **Rate limiting (and therefore self-destruct) only binds an attacker working through the running app.** Someone who copies the device's storage and attacks it offline, on their own hardware, never encounters the attempt counter at all — they can try passphrases as fast as their hardware allows, indefinitely, with no risk of triggering a wipe. Self-destruct is not a defence against that attacker; passphrase entropy is (see "A note on passphrase strength" above).

If any of this is unacceptable for your situation, leave self-destruct off and rely on passphrase strength alone — a strong passphrase is secure against an offline attacker whether or not self-destruct is enabled, while self-destruct carries a real risk of accidental, irreversible data loss and no benefit against that same offline attacker.

## Deleting a vault, and what that promises

Deleting a vault is a different act from self-destruct, with a different promise. Self-destruct runs under an attacker's hands and must leave a device that looks like it never had a vault *in use*, so it discards keys and leaves the on-disk shape alone. Deleting is the owner at the controls asking for the thing to be gone, so the directories and files go too.

- **Both environments always go together.** Any environment's passphrase deletes the whole vault, and the dialog says so beforehand without ever naming a decoy. This is not a convenience: an option to erase "just this one" can only exist where there is more than one, and a vault left holding a single slot where every untouched vault holds two announces that a second environment was removed. A user coerced into deleting "their vault" with the decoy passphrase therefore destroys everything, which is the honest outcome — not a decoy wiped while the real environment waits to be found.
- **It asks for a passphrase.** An unlocked phone in someone else's hands must not be enough to destroy the owner's files. The attempt goes through the same rate limiter as an unlock, so the dialog is not an unlimited oracle for guessing a passphrase.
- **If you have forgotten every passphrase, the app cannot delete the vault for you.** Delete the application's data through your operating system instead. This is the deliberate cost of the previous point.
- **It does not promise the bytes are gone.** The wrapped keys are overwritten before the files are unlinked, which makes the sealed content unrecoverable to anyone without the passphrase. The file contents themselves are unlinked, not overwritten, and on flash storage with wear-levelling even overwriting would not guarantee erasure — the same structural limit described under self-destruct above.

## Build verifiability

- **Reproducible builds:** the binary published in Releases can be regenerated from the source code and the pinned toolchain (pinned versions), obtaining a byte-for-byte identical result. Instructions in each release.
- **SHA-256 checksums** published with each binary, signed with the project key.
- **Public CI** on GitHub Actions: anyone can inspect how each artefact was built.
- **MIT licence**, public repo from the MVP's first commit: permanent open audit.

## Vulnerability reporting

If you find a security issue, **do not open a public issue**. Contact us through the channel listed in `SECURITY.md` (to be published with the first release) and we will follow a coordinated disclosure process.

---

*Last updated: 2026-10-28 — recorded how the device identity and the known-senders list are scoped across environments. 2026-10-27 — documented deleting a vault (both environments always, passphrase required, what erasure does and does not promise). 2026-10-25 — the vault, decoy environment and self-destruct moved from planned to implemented; documented their actual shipped shape (user-supplied decoy content, passphrase rather than PIN, self-destruct off by default) and the limits that come with it (flash erasure, deliberate triggering, clipboard exposure, phrase predictability, offline attack, iOS/macOS untested). This document is versioned with the project.*
