# DeadDrop

**Pass files from one device to another with no internet, no cables, no Bluetooth. Just the screen and the camera.**

And if someone forces you to open the app, a decoy PIN shows a fake, convincing environment while your real files remain invisible.

---

## Why does DeadDrop exist?

Imagine you have documents on your laptop that you need to hand over **in person** to someone standing one metre away. Today your options are bad:

- **Sending them over the internet** (email, WhatsApp, cloud): even encrypted, you leave a permanent trail on third-party servers: who sends, who receives, when.
- **Bluetooth or AirDrop**: they emit detectable signals and get logged by the system.
- **A USB drive**: the first thing seized at a checkpoint, and a classic malware vector.

DeadDrop solves this: one device's screen shows animated QR codes, the other device's camera reads them, and the file crosses **end-to-end protected without a single byte touching any network**. You can turn on airplane mode in front of anyone and the transfer works just the same.

**Who is it for?** For the journalist handing a leak to her newsroom. For the activist passing evidence to a lawyer. For anyone who wants to hand over personal documents without them passing through third-party servers. Privacy is a right (Articles 12, 19 and 20 of the Universal Declaration of Human Rights), not a technical privilege.

---

## How it works in 30 seconds

```
  Device A (sends)                       Device B (receives)
┌─────────────────────┐                  ┌─────────────────────┐
│                     │                  │                     │
│   ▓▓▓▓▓  ▓▓▓▓▓     │   light only,   │                     │
│   ▓ QR ▓→▓ QR ▓→   │ ═══════════════► │      📷 camera      │
│   ▓▓▓▓▓  ▓▓▓▓▓     │   no radio,     │                     │
│                     │   no network    │                     │
└─────────────────────┘                  └─────────────────────┘
   Pick a file → the screen               Point the camera
   shows animated codes                  → receive the file
```

1. **You pick the file** on the sending device.
2. **Animated QR codes appear** on its screen (the file travels inside them, protected so only the recipient can open it).
3. **The other device points its camera** and receives the file. Done.

No accounts, no configuration, no servers, no logs.

---

## Installation

Download the installer for your system from the [Releases](../../releases) page (or build from source — see [CONTRIBUTING.md](CONTRIBUTING.md)):

### Windows
1. Download `DeadDrop-x.y.z-windows.exe`.
2. Run it (if Windows SmartScreen warns you, click "More info" → "Run anyway").
3. Open DeadDrop from the Start menu.

### macOS
1. Download `DeadDrop-x.y.z-macos.dmg`.
2. Drag DeadDrop to the Applications folder.
3. The first time, open it with right-click → "Open" (Gatekeeper requires this for non-notarized apps).

### Linux
1. Download `DeadDrop-x.y.z-linux.AppImage` (or `.deb`).
2. Make it executable: `chmod +x DeadDrop-*.AppImage`.
3. Run it with a double click.

> **Verification:** each release publishes the SHA-256 checksums of the binaries and instructions to reproduce the build from source. See [docs/security.md](docs/security.md).

---

## First use in 2 minutes

1. **Open DeadDrop on both devices.** No account needed.
2. On the **sending** device: tap **"Send a file"** and pick the file.
3. On the **receiving** device: tap **"Receive a file"** and point the camera at the other screen.
4. You'll see a progress bar on both. When finished, the receiver taps **"Save"** and chooses where.

That's it. The [full user guide](docs/user-guide.md) walks through every step with screenshots, what to do if the camera struggles to read, and how to set up the decoy PIN.

---

## Quick questions

**Do I need internet?** No. Never. Not to install the app (if you copy it via USB), not to use it, not to activate it.

**What if someone forces me to unlock it?** You can set up a **decoy PIN**: if entered, the app opens normally but shows fake, credible content you chose in advance. Your real files are nowhere to be found. More details in the [FAQ](docs/faq.md).

**Is it legal?** Yes. DeadDrop is free software (MIT licence), auditable by anyone, and does not hide its own existence. It protects the same right as a sealed letter: the privacy of correspondence. Full analysis in the [FAQ](docs/faq.md#is-it-legal).

More answers in [docs/faq.md](docs/faq.md).

---

## Project status

DeadDrop is in active development for the **#cryptograFREE** challenge (RootedCON + Criptored). This repository has been public since day one and will remain so forever.

- ✅ Documentation and value proposition
- 🚧 MVP in development (delivery: February 2027)
- 📋 Roadmap: Android/iOS mobile apps after the MVP

## Documentation

| Document | Who it's for |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | Anyone who wants to use the app, step by step with screenshots |
| [docs/faq.md](docs/faq.md) | Answers to the questions everyone asks |
| [docs/security.md](docs/security.md) | What DeadDrop protects and what it doesn't — in plain language and in a technical version |
| [docs/value-proposition.md](docs/value-proposition.md) | Why the project exists and what makes it different |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute (code, translations, documentation) |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community rules |

## Licence

[MIT](LICENSE) — free software, forever.

---

*DeadDrop doesn't make you invisible. It gives you back something you should never have lost: the ability to hand information over in person without half the world knowing about it.*
