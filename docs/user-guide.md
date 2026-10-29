# DeadDrop User Guide

This guide takes you by the hand from the moment you open the app for the first time until you complete your first transfer. **You don't need to know anything about technology.** If you can take a photo with your phone or copy a file on your computer, you can use DeadDrop.

> **Note:** this guide is written to be followed without pictures — each step says exactly what you will see on screen.

---

## What works today, and what does not

DeadDrop is in **active development** (MVP target: February 2027). To avoid any misunderstanding that could affect your safety, here is the exact status of every feature mentioned in this guide:

**✅ Works today:**

- Air-gapped file transfer via animated QR codes (screen → camera, no network).
- End-to-end encryption of the transfer: only the receiving device can read the file.
- File integrity check: the app verifies the file arrived identical to the original.
- Resume after interruption: the codes repeat in a loop and the transfer continues where it left off.
- **The vault** — an optional, passphrase-protected place to keep received files, encrypted at rest.
- **A decoy environment** — a second passphrase that opens a different, independent space.
- **Self-destruct** — off by default; when you turn it on, ten wrong passphrases in a row discard the keys to both environments.

**📋 Not yet:**

- **Scanning with the camera on Linux and Windows.** The desktop builds have no scanner, so there you type or paste the other device's key instead. Android, iOS and macOS scan normally.
- **An external audit.** Nobody independent has reviewed this code.

> ⚠️ **Three things to understand before you rely on the vault.** It is **opt-in**: a file you save outside it has no protection from DeadDrop. The decoy holds **whatever you put in it** — the app invents nothing, and an empty decoy is not convincing. And self-destruct **discards keys, it does not erase files**; on the flash storage phones use, nobody can promise the bytes are physically gone. The limits are spelled out in [docs/security.md](security.md).

---

## Before you start: what you need

- **Two devices** with DeadDrop installed (two computers, or a computer and a phone once the mobile apps are available).
- The **receiving** device must have a **camera** (a laptop webcam works fine).
- Both devices in the **same room**, facing each other.

You don't need internet. You don't need WiFi. You don't need Bluetooth. You don't need to create any account. In fact, if you want to check, turn on airplane mode on both devices: DeadDrop works just the same.

---

## Your first transfer, step by step

### Step 1 — Open DeadDrop on both devices

When you open the app you will see a screen with two large buttons:

- **"Send a file"**
- **"Receive a file"**

The app opens directly — **no account, no login, no setup**. The vault, if you set one up, asks for its passphrase only when you open it; the rest of the app does not.

### Step 2 — On the SENDING device

1. Tap **"Send a file"**.
2. Your system's file picker opens. Choose the file you want to pass.
3. The app shows you a screen with the file name and its size. Tap **"Start sending"**.
4. The screen starts showing **codes that change several times per second**, similar to QR codes. Your file is travelling inside those codes, protected so that **only the device in front can open it** — even if someone recorded the screen with another camera, they could not read the content.

### Step 3 — On the RECEIVING device

1. Tap **"Receive a file"**.
2. The app opens the camera. **Point it at the other device's screen**, as if you were going to take a photo of the code.
3. As soon as the camera starts reading the codes, you will see a **progress bar** moving forward. Keep the device still and focused.
4. When the bar reaches 100%, the app checks that the file has arrived complete and intact, and shows you its name and size.
5. Tap **"Save"** and choose the folder where you want to keep it. Done.

### Step 4 — Check the file

Open the file on the receiving device and check that it looks correct. DeadDrop guarantees that the file arrives identical to the original: if even a single byte is missing, the app warns you instead of handing you a corrupt file.

---

## Tips for fast reading

The codes on the screen travel through the camera, so reading quality depends on very physical things:

- **Distance:** between 15 and 30 centimetres between screen and camera is usually ideal. Neither touching nor far away.
- **Light:** avoid reflections on the sender's screen. If there is a light source right behind the receiver, the camera may struggle. Change the angle slightly.
- **Screen brightness:** turn it up to maximum on the sending device. The app raises it automatically during the transfer.
- **Stay still:** both devices should be as still as possible. Resting them on a table helps a lot.
- **Speed:** after the receiving device has read one transfer, it measures its own camera and puts a suggestion into the QR code it shows next time. The sender applies that suggestion automatically — the Options panel says "Set from the receiver's camera" when it has — and you can still change any of it by hand with the "Sending speed" control. On a first-ever transfer there is nothing measured yet, so the sender uses its defaults.

If the transfer stalls at a percentage, no problem: the codes repeat in a loop, so as soon as the camera reads well again, the bar keeps moving from where it was. **You don't need to start over.**

---

## The vault and the decoy

The vault is an optional, passphrase-protected place to keep files you have
received. Files you save into it are encrypted at rest. You can also set up a
**decoy**: a second passphrase that opens a different, independent space.

What is it for? The situation where someone **forces** you to unlock the app: a
checkpoint, a search, a threat. You enter the decoy passphrase and the vault
opens completely normally, showing the files you left there for that case. There
is no "hidden mode" screen, no warning, nothing that reveals other content
exists — and opening either one takes exactly the same time, so a stopwatch
tells them apart no better than the screen does.

### Setting it up

1. Go to **Settings → Set up vault** and choose a passphrase.
2. The app offers you six random words. **Use them.** Six words are about 62
   bits of entropy; the app will not accept anything under 60. A six-digit PIN
   falls in under a minute to someone holding a copy of your storage, which is
   why this asks for words rather than digits.
3. Go to **Settings → Set up decoy** and choose a *different* passphrase.
4. **Put real-looking files in the decoy.** The app invents nothing. An empty
   decoy is not a decoy — spend five minutes on this.
5. From then on, each passphrase opens its own space.

When you receive a file, the result screen offers **Device** and **Vault**. The
Vault button only appears once a vault exists: a greyed-out button would itself
tell someone the feature is set up.

### Rules worth following

- **Never write the two passphrases down together**, or near each other.
- **Keep the decoy alive.** If its newest file is three years old, it looks
  staged. Add something now and then.
- **Rehearse.** Open the decoy occasionally and look at exactly what a stranger
  would see. It has to look like your whole app.
- **The vault is opt-in.** A file saved to the device instead of the vault has
  no protection from DeadDrop — only whatever your operating system gives it.

### Seeing what you are typing

Passphrase boxes have an eye button. Six random words are long and nobody types
them from memory, so a typo in a row of dots is invisible — and if you have
self-destruct on, a wrong attempt is expensive. Tap the eye when you are
somewhere it is safe to read the screen. The app cannot see the room; you can.

### Deleting a vault

**Settings → Security → Delete vault**, or the same option on the unlock
screen. It asks you to type `DELETE` rather than your passphrase, so that a
stray tap cannot wipe your files — but it does not need the passphrase,
because deleting is also what you do when you have forgotten it.

**It deletes everything.** Both the real environment and the decoy. There is
no "delete just the decoy", on purpose: an option
like that could only exist on a device that has one, so its presence on the
screen would be the very thing the decoy is meant to hide. Assume that
deleting under someone else's pressure destroys all of it.

**If you have forgotten your passphrase, this is your way out.** There is no
recovery — no PIN, no hint, no reset link. That is what makes the vault worth
having: nobody can be made to hand over something that does not exist. What
you can always do is delete the vault and start again. The files are gone,
but they were encrypted and stay encrypted; better deleted than read.

---

## Self-destruct

Off by default. When you turn it on in **Settings → Self-destruct**, ten wrong
passphrases in a row discard the keys protecting **both** environments — the
real one and the decoy. A surviving decoy would prove there had been something
to erase, so it does not survive either.

**Read this before turning it on.**

- **It is irreversible.** Forget your passphrase and the files are gone.
- **An attacker can trigger it on purpose** by simply guessing wrong ten times.
  Whether that is good or bad depends on your situation: it destroys evidence,
  and it also destroys your files.
- **It discards keys; it does not erase files.** On the flash storage phones and
  SSDs use, the app cannot guarantee the old bytes are physically gone. What it
  guarantees is that the keys to read them are.

Wrong attempts are also slowed down — a few seconds, growing to a minute. That
helps against someone poking at your phone; it does nothing against someone who
copies the storage and attacks it offline. Your passphrase is what defends you
there, which is why the app insists on six words.

---

## Frequently asked questions

Wondering whether you need internet, whether it is legal, what happens if your device is stolen…? All of that is answered in the [FAQ](faq.md).

Want to understand exactly what DeadDrop protects and what it doesn't? Read [security.md](security.md), which explains it first in plain language and then in a technical version.
