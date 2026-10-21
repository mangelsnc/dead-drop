# Frequently asked questions (FAQ)

The questions anyone would ask before using DeadDrop, answered without jargon.

---

## The basics

### Do I need internet to use DeadDrop?

**No.** Not to send, not to receive, not to activate the app. DeadDrop never connects to the internet: it has no servers, no accounts, it sends no statistics. You can turn on airplane mode and verify it works exactly the same.

### How can a file cross without internet, Bluetooth or cables?

By sight, literally. The sending device's screen shows codes (similar to the QR codes in restaurants) that change several times per second. The receiving device's camera reads them until it reconstructs the complete file. It's like passing a note by showing it to someone who copies it, but at machine speed.

### What do I need to use it?

Two devices with DeadDrop installed, and the receiving one must have a camera. Nothing else: no accounts, no passwords for external services, no configuration.

### Is it free?

Yes, and it always will be. DeadDrop is free software under the MIT licence: anyone can use it, copy it, study it and improve it, for free, forever.

### What systems does it support?

Windows, macOS and Linux. Android and iOS versions are on the roadmap after the initial release.

### Can I send any type of file?

Yes: documents, photos, videos, compressed archives… anything. In the initial version you send one file at a time (if you want to send several, the app itself can pack them into a single `.zip`).

### Is there a size limit?

There is no fixed limit, but keep in mind the file travels through the camera: a document of a few MB transfers in seconds or a few minutes; a video of several GB would take a long time. DeadDrop is designed for documents and sensitive information of reasonable size, not for passing along your film collection.

---

## Privacy and security

### Can someone intercept my file while I send it?

To read the codes, someone would have to **physically see the screen** during the entire transfer (a hidden camera in the room, for example). But even if they managed that, the content travels end-to-end protected: **only the receiving device that took part in that transfer can open it**. A recording of the screen would be a pile of useless codes.

### Is any trace of the transfer left?

On the internet: nothing, because there is no internet. On the devices: the app keeps no history of what you sent or to whom. The received file stays wherever you decide to save it, like any other file.

### What happens if I'm forced to unlock the app?

**Today: nothing protects you here yet.** The **decoy PIN** — a second PIN that would open the app showing fake, credible content you prepared in advance — is a **planned feature and is not implemented**. The current version has no PIN at all: whoever opens the app sees everything in it. If physical coercion is a realistic scenario for you, do not store sensitive files in DeadDrop yet; use it only for the transfer and protect the device with your operating system's tools (disk encryption, strong unlock code). Follow the roadmap in the [user guide](user-guide.md#what-works-today-vs-whats-planned).

### What happens if I lose my device or it gets stolen?

**Today:** files you received with DeadDrop are stored as ordinary files wherever you saved them. They are protected only by your device's own security (user account, disk encryption such as FileVault/BitLocker/LUKS if enabled). DeadDrop's own **PIN protection, at-rest encryption and self-destruct are planned features and do not exist yet** — there is currently no PIN to enter and nothing that erases content after failed attempts.

### What if I forget my PIN?

The current version has no PIN, so there is nothing to forget. When PIN protection ships, there will be no way to recover a forgotten PIN — no "security question" or recovery email, because that would require servers and accounts, exactly what DeadDrop avoids.

### Can I trust the encryption? Who has reviewed it?

DeadDrop doesn't invent its own cryptography: it uses **libsodium**, a cryptography library that is audited and used by tools as battle-tested as Signal and WireGuard. On top of that, all of DeadDrop's code is public: any expert in the world can review and audit it, and the binaries you download can be regenerated from the source code to verify they are exactly what they claim to be. Technical details are in [security.md](security.md).

### Does DeadDrop make me anonymous on the internet?

No, and it's important to understand this: DeadDrop **is not an internet tool**. It doesn't browse, it doesn't send email, it doesn't hide your IP. It does one thing and does it well: moving files between two devices that are physically together without touching any network. For anonymity on the internet there are other tools (like Tor) that solve a different problem.

---

## Legality and ethics

### Is it legal?

**Yes.** DeadDrop is free and public software. It doesn't hide its own existence, it doesn't exploit any vulnerability, it doesn't access other people's systems. It protects the same right protected by a sealed letter or a private conversation: Article 12 of the Universal Declaration of Human Rights ("No one shall be subjected to arbitrary interference with his privacy… nor upon his correspondence"). Using encryption is legal in the vast majority of countries, just like locking your own diary.

### What if someone uses it for something illegal?

Every privacy tool is "dual-use": the same encryption that protects a journalist protects a criminal, just as a kitchen knife serves for dinner and for other things. The answer of democratic societies has always been the same: the right to privacy is not conditioned on proving your innocence first. DeadDrop explicitly frames itself within fundamental rights (Articles 12, 19 and 20 of the UDHR) and its development is open and auditable precisely for that reason.

### Can I use it at work / in my country?

DeadDrop does nothing you couldn't already do with paper and a face-to-face conversation. That said: some countries restrict the use of encryption, and some companies have policies about what software can be installed. Check the regulations that apply to you. DeadDrop gives you the tool; the responsibility to use it according to your law is yours.

---

## Problems and practical cases

### The camera doesn't read the codes, what do I do?

The most common fixes, in order:

1. **Turn up the brightness** on the sending screen (the app does this automatically).
2. **Move the devices slightly apart**: between 15 and 30 cm is usually ideal.
3. **Avoid reflections**: if a strong light reflects on the screen, change the angle.
4. **Lower the sending speed** with the sender's "Speed" control: older cameras need more time per code.
5. Keep both devices **still**, resting them on something if you can.

The transfer is not lost: the codes repeat in a loop and the app resumes from where it was.

### Can I pause a transfer and continue later?

Yes. If the transfer is interrupted (you move, the camera locks up, you answer a call), when you resume, the receiver continues from where it left off. You don't start from scratch.

### Can I send to more than one device at a time?

In the initial version, no: the transfer is between two devices. If you need to deliver the same file to three people, you do three sends (each one independently protected for that recipient).

### Why is there no web version?

Because a website needs internet, and DeadDrop exists precisely to avoid touching the internet. It's an app you install that works completely locally.

### How do I know the app I downloaded is the genuine one and not a modified copy?

Each release publishes its **checksums** (a digital fingerprint of the file) and instructions to verify them. On top of that, builds are **reproducible**: anyone can generate the binary from the public source code and verify it matches the published one byte for byte. The concrete steps are in [security.md](security.md).

### Who is behind the project?

A team taking part in the **#cryptograFREE** challenge (RootedCON + Criptored), a competition for free privacy and encryption tools. The code, the decisions and the documentation have been public since day one at [github.com/mangelsnc/dead-drop](https://github.com/mangelsnc/dead-drop).

### How can I help?

By using it, spreading the word, translating, reporting bugs or contributing code. Everything is explained in [CONTRIBUTING.md](../CONTRIBUTING.md).

---

*Is your question not here? Open an [issue on GitHub](https://github.com/mangelsnc/dead-drop/issues) and we'll answer it.*
