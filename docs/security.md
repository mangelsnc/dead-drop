# Security in DeadDrop

This document explains **what DeadDrop protects, against whom, and what it does not protect**. It comes in two parts:

1. **In plain language** — for anyone who uses the app and wants to understand what to expect from it.
2. **Technical version** — for auditors, security researchers and the challenge jury.

Honesty about limits is as important as the guarantees. A privacy tool that promises the impossible is a dangerous tool.

> ⚠️ **Implementation status (2026-10-21):** DeadDrop is in active development. **Transfer encryption is implemented and working. The decoy PIN, at-rest encryption and self-destruct are NOT implemented yet** — they are marked 📋 *Planned* wherever they appear below. Do not rely on any planned feature for your safety.

---

# Part 1 — In plain language

## What DeadDrop protects

### 1. The content of your files during handover ✅ Implemented

When you pass a file with DeadDrop, the content travels protected end to end: it is sealed on the sending device and only opened on the receiving device. No one in between — not even someone recording the screen with another camera — can read it.

### 2. The non-existence of a network trail ✅ Implemented

DeadDrop does not use the internet, WiFi, Bluetooth or cables. The file travels through light: from the screen to the camera. That means **there is no metadata on any server**: no company and no network observer can know that the transfer happened, who took part, or when. It is not that the trail is hidden — it is that it does not exist.

### 3. Your device during a forced search 📋 Planned — no protection today

> ⚠️ **Not yet implemented.** The **decoy PIN** and **self-destruct** described here are planned features. **Today the app has no PIN at all**: whoever opens it sees everything in it, and received files are stored as ordinary files, protected only by your operating system (user account, disk encryption such as FileVault/BitLocker/LUKS if enabled).

When implemented, with the **decoy PIN** configured, if you are forced to open the app you will be able to show fake, credible content while your real files remain invisible. And with **self-destruct** enabled, several failed PIN attempts will irreversibly erase the protected content.

### 4. File integrity ✅ Implemented

DeadDrop verifies that what arrives is exactly what was sent. If even a single byte is missing, the app warns you instead of handing you a corrupt or tampered file.

## What DeadDrop does NOT protect

This is just as important. DeadDrop does **not** protect you from:

- **An already-compromised device.** If your computer has a virus or malware installed (a trojan, a keylogger), that malware can read your files before you send them or after you receive them. DeadDrop protects the channel; it does not cure a sick device.
- **Cameras in the room.** If someone physically records the sender's screen *and also* compromises the receiving device, they could combine both. Against physical surveillance of the place, the defence is choosing the place well.
- **The other person revealing the file.** Once received, the file is in the recipient's hands. DeadDrop cannot stop that person from sharing, printing or handing it over. Trust the recipient as you would when handing them a physical envelope.
- **Your own behaviour.** If you talk about the transfer on a tapped phone, if you arrange to meet the recipient over watched channels, or if you carry the device to a checkpoint announced in your own email, no app can help you. Security is a chain: DeadDrop is the handover link; the other links are yours.
- **Anyone opening the app on your device today.** Until the PIN, at-rest encryption and decoy features ship, assume everything stored in DeadDrop is visible to anyone with access to your unlocked device. When the decoy PIN exists, it will only work if you have configured it *beforehand* and if its content is credible.

## Common-sense advice

- Until the decoy PIN ships: if physical coercion is a realistic scenario for you, use DeadDrop only for the transfer itself and protect your device with your operating system's tools (disk encryption, strong unlock code).
- When the decoy PIN ships: set it up **before** you need it, not the day before a trip, and keep the decoy content credible and up to date.
- Turn on airplane mode on both devices during the transfer if you want a visible, demonstrable guarantee that there is no network.
- Verify your downloads with the published checksums (see below).
- DeadDrop is a tool for in-person handover. For remote communication, combine it with other tools (Signal, Tor) that solve that other problem.

---

# Part 2 — Technical version (for auditors)

> **Status:** this section describes the security design of the MVP. Each row of the tables below carries an explicit implementation status: ✅ *Implemented* means working code exists in `app/lib/` today; 📋 *Planned* means a documented design goal with **no implementation**. The concrete parameters will be frozen with the implementation and any change will be documented here. The code is the final reference; this document is the map.

## Threat model

DeadDrop is designed against these adversaries:

| Adversary | Assumed capability | DeadDrop's response | Status |
|---|---|---|---|
| **Network observer** (ISP, state, company) | Sees and logs all network traffic of both devices | There is no traffic: the channel is optical (screen → camera). Absence of emission verifiable with a spectrum analyser. | ✅ Implemented |
| **RF proximity observer** | Captures Bluetooth/WiFi/radio in the room | No radio in use. | ✅ Implemented |
| **Optical interceptor** | Records the sender's screen with a camera for the entire transfer | The payload travels E2E encrypted (see below): the recording only produces ciphertext. | ✅ Implemented |
| **Adversary with physical access to the device** | Searches the device, installs the app, inspects it | Data at rest encrypted with a key derived from the PIN (Argon2id). Decoy PIN → plausible deniability. Optional self-destruct after N attempts. | 📋 **Planned — no protection today.** Received files are stored unencrypted. |
| **Adversary who coerces the user** | Forces the user to unlock the app | The decoy PIN opens a decoy space indistinguishable from the real one at the app-behaviour level. | 📋 **Planned — no protection today.** There is no PIN and no decoy space. |

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
| Key derivation from PIN (data at rest) | Argon2id (`crypto_pwhash`) with at least interactive parameters | 📋 Planned |
| Data at rest | Database encrypted with a key derived from the PIN; the decoy space and the real space use keys derived from different PINs, with no artefact revealing the existence of two spaces | 📋 Planned |
| Self-destruct | Erasure of the wrapped key + overwriting of the encrypted store (app-level secure erase; the limits of flash wear-levelling will be documented honestly) | 📋 Planned |

## Plausible deniability — properties (planned)

> ⚠️ This section describes the **design goal** for the decoy PIN feature. None of it is implemented today.

- Same binary, same unlock flow for both PINs: no difference in behaviour, timing or interface reveals which PIN was entered.
- The decoy space is a real encrypted space with its own key: it is not a detectable "hidden mode".
- The app stores no indicator that two spaces exist.

## Build verifiability

- **Reproducible builds:** the binary published in Releases can be regenerated from the source code and the pinned toolchain (pinned versions), obtaining a byte-for-byte identical result. Instructions in each release.
- **SHA-256 checksums** published with each binary, signed with the project key.
- **Public CI** on GitHub Actions: anyone can inspect how each artefact was built.
- **MIT licence**, public repo from the MVP's first commit: permanent open audit.

## Vulnerability reporting

If you find a security issue, **do not open a public issue**. Contact us through the channel listed in `SECURITY.md` (to be published with the first release) and we will follow a coordinated disclosure process.

---

*Last updated: 2026-10-21 — added per-row implementation status (implemented vs. planned) throughout. This document is versioned with the project.*
