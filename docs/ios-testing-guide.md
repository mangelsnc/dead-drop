# DeadDrop iOS Testing Guide

Welcome! This guide walks you through installing and testing DeadDrop on your iPhone or iPad.

---

## Before you start

You need:
- An iPhone or iPad running **iOS 15.0 or later**
- A camera (used for scanning QR codes)
- About 50 MB of free space

---

## Installation

### Via a direct build (.ipa)

1. **Get the `.ipa`** handed to you directly, along with its SHA-256.
2. **Check the SHA-256 matches** before you install it:
   `shasum -a 256 DeadDrop.ipa`
3. **Install it** with Apple Configurator, or by dragging it onto your
   device in Finder.
4. If prompted, go to **Settings → General → VPN & Device Management** and
   trust the developer profile.
5. **Open DeadDrop** from your home screen.

> **Note:** The first time you open the app, iOS may show a warning about an untrusted developer. Go to **Settings → General → VPN & Device Management → [Developer Name] → Trust** to allow the app to run.

### Via TestFlight

1. **Install TestFlight** from the App Store (if you don't have it)
2. **Check your email** — you'll receive an invitation from TestFlight
3. **Tap "View in TestFlight"** in the email
4. **Tap "Install"** next to DeadDrop
5. **Open DeadDrop** from your home screen or TestFlight

---

## What to test

### Basic flow: Send and receive a file

You need **two devices** — one to send, one to receive. Both must have DeadDrop installed.

There is no shared PIN or password: the receiver shows a QR holding its
public key, the sender scans it, and the transfer is encrypted to that
receiver alone.

**On the receiving device:**
1. Open DeadDrop
2. Tap **"Receive a file"** — it shows a QR with its public key
3. Point the camera at the sending device once the codes start

**On the sending device:**
1. Open DeadDrop
2. Tap **"Send a file"**
3. Choose a file (any type — photo, document, etc.)
4. Scan the receiver's QR (step 2 on the send screen)
5. Tap **"Start sending"**; animated QR codes appear

**Back on the receiver:** a progress bar fills as the codes are read.
When it reaches 100% the file is verified and you choose where to save
it — the device, or the vault if you have set one up.

### Things to try

- [ ] Send a small file (< 1 MB) — should be fast
- [ ] Send a larger file (5-10 MB) — notice the QR animation speed
- [ ] Try in different lighting conditions (bright, dim, outdoor)
- [ ] Try with devices at different distances (15-30 cm works best)
- [ ] Cancel a transfer mid-way — should not crash
- [ ] Cover the camera for a few seconds, then point it back — the
      transfer should carry on from where it was, not restart
- [ ] Start the sender, wait a minute, *then* open the receiver — it
      should still join (the session header repeats)
- [ ] Set up a vault and a decoy, and check each passphrase opens its
      own space
- [ ] Save a received file into the vault, then lock and reopen it

### What to report

Please report anything that seems wrong, confusing, or could be better:

- **Crashes** — the app closes unexpectedly
- **Transfer failures** — QR codes not scanning, files not decrypting
- **UI issues** — buttons too small, text unreadable, layout broken
- **Performance** — app is slow, QR animation stutters
- **Confusing UX** — anything that made you think "what do I do now?"

### How to report

- **GitHub Issues**: https://github.com/mangelsnc/dead-drop/issues/new?template=bug_report.yml
- Include: what you did, what happened, what you expected, device model, iOS version

---

## Privacy note

DeadDrop is designed for privacy:
- **No network connection** is used during file transfer
- **Files are encrypted** end-to-end with libsodium
- **No data is sent** to any server
- The camera is used **only** for QR scanning — no photos or videos are stored

---

## FAQ

**Q: The QR codes are moving too fast to scan**
A: The sender can adjust the frame rate in settings. Slower = easier to scan but takes longer.

**Q: Can I send files between iOS and Android?**
A: Yes! DeadDrop is cross-platform. Any device with the app can send to any other.

**Q: Can I send files between iOS and desktop?**
A: Yes, but the desktop version uses the webcam for scanning. Point it at the iOS screen.

**Q: The app says "Camera permission denied"**
A: Go to **Settings → DeadDrop → Camera** and enable it.

**Q: How big a file can I send?**
A: There's no hard limit, but larger files take longer. A 10 MB file at 30 fps with 500 bytes/frame takes about 11 minutes.

---

## Thank you!

Your testing helps make DeadDrop better for everyone. Every bug report and suggestion counts.
