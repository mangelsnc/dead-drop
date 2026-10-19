# DeadDrop User Guide

This guide takes you by the hand from the moment you open the app for the first time until you complete your first transfer. **You don't need to know anything about technology.** If you can take a photo with your phone or copy a file on your computer, you can use DeadDrop.

> **Note:** screenshots will be added when the app is available. Each step describes exactly what you will see.

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

The first time, the app will ask you to create an **access PIN**. This is the code that protects your files stored inside the app. Choose something you will remember that is not your date of birth. Later you can also set up a **decoy PIN** (we explain it in the "The decoy PIN" section below).

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
- **Speed:** if your device's camera is old, the app automatically slows down the codes so there is time to read them. You can also adjust it manually on the sender with the "Sending speed" control.

If the transfer stalls at a percentage, no problem: the codes repeat in a loop, so as soon as the camera reads well again, the bar keeps moving from where it was. **You don't need to start over.**

---

## The decoy PIN: what it is and how to set it up

DeadDrop lets you have **two PINs**:

- Your **real PIN**: opens the app with your real files.
- Your **decoy PIN**: opens the app with fake content you prepared in advance.

What is it for? For the situation where someone **forces** you to unlock the app: a checkpoint, a search, a threat. You enter the decoy PIN and the app opens completely normally, showing the files you left there for that case. There is no "hidden mode" screen, no suspicious message, nothing that reveals that other content exists. The app behaves exactly the same as with the real PIN.

### How to set it up

1. Open DeadDrop with your real PIN.
2. Go to **Settings → Decoy PIN**.
3. Choose a PIN different from the real one (not obvious, not similar).
4. **Prepare the decoy content:** the app lets you add files to the decoy space. Choose credible, bland files: holiday photos, unimportant documents, notes. A completely empty space would raise suspicions, so spend five minutes on this.
5. From that moment on, each PIN opens its own space. No one who doesn't know both PINs can know that two exist.

### Golden rules for the decoy PIN

- **Never write it down** next to the real PIN or in the same place.
- **Keep the decoy content alive:** if your "holiday photos" are three years old and there is nothing recent, it looks strange. Add a file now and then.
- **Rehearse:** enter the decoy PIN once in a while to see exactly what another person would see. It must look like your real app.

---

## Self-destruct (optional, for high-risk situations)

DeadDrop can securely erase all protected content if someone enters the wrong PIN too many times in a row.

1. Go to **Settings → Self-destruct**.
2. Turn it on and choose the number of failed attempts (for example, 5).
3. From then on, if someone exceeds that number of attempts, the protected content is irreversibly erased.

**Important warning:** this feature is irreversible. If you turn it on and forget your PIN, you will lose your files forever. It is off by default and we only recommend enabling it if your situation justifies it.

---

## Frequently asked questions

Wondering whether you need internet, whether it is legal, what happens if your device is stolen…? All of that is answered in the [FAQ](faq.md).

Want to understand exactly what DeadDrop protects and what it doesn't? Read [security.md](security.md), which explains it first in plain language and then in a technical version.
