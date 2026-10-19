# DeadDrop — Value Proposition and Narrative

**Project:** DeadDrop · #cryptograFREE Challenge (RootedCON + Criptored)
**Version:** 1.0 · **Date:** 2026-10-17
**Status:** Governing document for the idea submission (deadline: 28-Dec-2026) and project decision-making guide.

---

## 1. Elevator pitch

> **DeadDrop is the first app that lets you pass encrypted files from one device to another without touching any network, cable or Bluetooth: just the camera and the screen.**
> **And if you are forced to unlock it, a decoy PIN opens a convincing fake environment while your real data stays invisible.**

Two sentences. Two promises. The first solves the technical problem (truly air-gapped transfer, usable by anyone). The second solves the human problem (physical coercion — the scenario no conventional encryption tool even considers).

---

## 2. The concrete problem we solve

Modern encryption protects data **in transit over the network** and **at rest on disk**. But it leaves one critical — and increasingly common — moment uncovered: **the physical handover of sensitive information between two people who cannot afford to leave a trace on any network**.

Today, if two people face to face want to exchange a file without exposing it, their real options are bad:

- **Send it over the internet** (email, messaging, cloud): leaves metadata on third-party servers, even if the content is encrypted. Metadata reveals *who talks to whom, when, and how much*.
- **Use Bluetooth, AirDrop or a local network**: they emit detectable signals, are recorded in system logs, and can be intercepted at close range.
- **Use a USB drive**: requires trusting the hardware, is a classic malware vector (BadUSB, Stuxnet), and is the first thing seized at a checkpoint.

### Scenario 1 — The journalist in a hostile zone

María covers corruption in a country where searching journalists is routine. She has 4 GB of leaked documents on her laptop proving the diversion of public funds. Her source is in the same city and wants a backup copy before María crosses the border. Sending them over the internet — even via Signal or Tor — generates a detectable traffic pattern between two people already under surveillance. A USB drive would be seized at the first roadblock. With DeadDrop, the two laptops face each other in a room, one screen emits animated QR codes, the other's camera reads them, and the documents pass end-to-end encrypted **without a single byte touching any network**. If María is detained and forced to unlock the app, she enters her decoy PIN: a folder opens with travel photos and bland documents. The real documents are nowhere to be found.

### Scenario 2 — The activist under surveillance

Karim runs a support network for persecuted people. His phone was seized once; since then he assumes everything he transmits is read. He needs to hand a lawyer a list of contacts and evidence of arbitrary detentions. He cannot use the internet, he cannot use Bluetooth (detectable at close range), he cannot risk a logged USB drive. With DeadDrop on two phones, the transfer happens in electromagnetic silence: no radio emission, no connection log, no metadata. Duress mode also gives him a layer of plausible deniability if the device is searched in his presence.

### Scenario 3 — The ordinary citizen

Lucía has just signed her divorce and needs to hand her lawyer personal financial documents. She is neither an activist nor a journalist: she simply does not want her payslips and accounts passing through Google's, Meta's or Dropbox's servers, or ending up in her phone's "shared" history. DeadDrop gives her the same guarantee it gives María and Karim, with an interface that does not require knowing what a public key is: open the app, pick the file, hold the other device up, done.

**The common pattern:** all three people need to move sensitive information between two physically close devices without leaving a trace on any infrastructure — and without possession of the app itself being incriminating evidence. Today no product tool solves this.

---

## 3. Why now

The #cryptograFREE challenge states it precisely: privacy is not a technical luxury, it is a fundamental right in accelerated erosion.

- **UDHR Art. 12:** *"No one shall be subjected to arbitrary interference with his privacy, family, home or correspondence."* Mass metadata surveillance makes all digital "correspondence" observable by design. DeadDrop restores Art. 12 in the concrete act of transferring a file: there is no observable correspondence because there is no channel.
- **UDHR Art. 19:** *"Everyone has the right to freedom of opinion and expression; this right includes freedom to hold opinions without interference and to seek, receive and impart information and ideas through any media and regardless of frontiers."* The phrase "seek, receive and impart information" is exactly what the journalist in scenario 1 does. Network surveillance turns that right into a physical risk. DeadDrop protects it.
- **UDHR Art. 20:** *"Everyone has the right to freedom of peaceful assembly and association."* Network metadata is the standard instrument for mapping association networks. An air-gapped transfer generates no edges in any observable social graph.

The context that makes this urgent:

- **Mass-scanning regulation in the EU** (the debate around "Chat Control") normalises the idea that all digital content must be inspectable. Even if end-to-end encryption survives, the pressure shifts to metadata and to devices.
- **Commercial state malware** (Pegasus and successors) has proven that the connected device is the weak link. Reducing network exposure surface to zero during transfer is a structural defence, not a setting.
- **Physical coercion is the forgotten vector.** Disk encryption is defeated by a court order or a threat. Well-implemented plausible deniability is the only technical answer to that vector, and today it is reserved for experts (VeraCrypt hidden volumes) with hostile UX.

DeadDrop arrives at the moment these three pressures converge, and it does so with a tool a non-technical person can use.

---

## 4. Differentiation from what exists

### State of the art (honest summary)

| Tool | What it does | Why it doesn't solve the problem |
|---|---|---|
| **AirGap Vault/Wallet** | Air-gapped animated QRs | Only for crypto keys and transaction signing. Not a general file-transfer tool. |
| **libcimbar / txqr** | One-way transfer via animated codes | Research libraries/prototypes, not a product. No integrated E2E encryption, no UX, no packaged cross-platform build, no duress mode. |
| **magic-wormhole** | Encrypted P2P transfer | Requires internet and a rendezvous server. Leaves metadata. |
| **OnionShare** | File sharing over Tor | Requires network, Tor, and configuration that intimidates non-technical users. Leaves traffic patterns. |
| **Snapdrop / LocalSend / AirDrop** | Local-network transfer | Not air-gapped: they emit radio, end up in logs, interceptable at close range. |
| **VeraCrypt (hidden volumes)** | Plausible deniability on disk | Transfers nothing. Extremely hostile UX. Desktop only. |
| **USB / SD cards** | Physical transfer | Malware vector, seizable, leaves forensic artefacts on both systems. |

### DeadDrop's unique position

As of today, DeadDrop is **the only tool that combines the following four properties in a single open-source, cross-platform product**:

1. **Real air-gap:** the data channel is optical (screen → camera). No radio, no cable, no network. The absence of emission is verifiable with a spectrum analyser.
2. **End-to-end encryption** with libsodium (X25519 + XSalsa20-Poly1305), with key exchange also optical: not even the keys touch a network.
3. **Built-in plausible deniability:** decoy PIN that opens a credible decoy environment (not an empty folder, which would give the trick away), with optional self-destruct after N failed attempts.
4. **Designed for non-technical users:** three-step flow, no configuration, no exposed cryptographic concepts, documentation in plain language.

Existing tools solve **one** of these four. None solves all four at once. That combination is DeadDrop's original contribution.

### Challenge category coverage

- **Anonymity:** there is no network metadata to anonymise because there is no network. It is structural anonymity, not probabilistic.
- **Encryption:** E2E with libsodium, ephemeral per-session keys, forward secrecy.
- **Local machine:** everything happens locally; the app works 100% offline; plausible deniability and self-destruct protect the device itself.
- **Evasion:** evasion of the surveillance channel by design (there is no channel), and evasion of physical coercion via the decoy environment.

Four categories with a single end-to-end solution. Exactly the profile the challenge rewards.

---

## 5. Narrative for the jury

### The story in three acts

**Act 1 — The uncomfortable moment (30 seconds).**
"Imagine you have on this laptop the documents that prove a corruption case. The person who needs a copy is one metre away from you. And yet, in 2026, your only safe option is… to send them over the internet, leaving a permanent trail on servers you don't control. That's absurd. DeadDrop fixes it."

**Act 2 — The live demo (2 minutes).**
Two devices on the jury's table. Airplane mode visibly on in both. A file is chosen, the screen starts emitting animated QRs, the other device receives it. The file opens. *Total, verifiable electromagnetic silence.* Then the punch: "Now search my phone." The decoy PIN is entered. A convincing fake environment appears. "The real documents don't exist for you."

**Act 3 — The right (30 seconds).**
"This is not a tool for hiding crimes. It is the tool that makes Article 19 of the Universal Declaration possible — to seek and receive information without interference — in a world where all electronic communication is observable by design. The journalist, the activist and the ordinary citizen have the same right. DeadDrop gives it back to all three."

### Rhetorical keys

- **Never say "military-grade encryption" or "unbreakable".** Say "end-to-end encryption with libsodium, the same audited library used by Signal and WireGuard". Technical credibility without marketing.
- **The air-gap is demonstrated, not claimed.** Visible airplane mode + working transfer = empirical proof before the jury.
- **Duress mode is the emotional differentiator.** The QR impresses; the decoy PIN is what gets remembered. It is the answer to "what if they force you?".
- **Anticipate the "dual-use" objection:** every privacy tool (Tor, Signal, VeraCrypt) is dual-use. The challenge demands legality and ethics: DeadDrop meets them by design — it is auditable open source, it exfiltrates nothing, it does not hide its own existence, and its documentation frames use within fundamental rights. The answer to "what if a criminal uses it?" is the same one the UDHR gives: the right to privacy is not conditioned on prior innocence.
- **Quantify the coverage:** "4 of the 5 challenge categories, with a single end-to-end solution". It is the metric the jury explicitly scores.

### Tone

Sober, technical but translated, with a concrete emotional anchor (the journalist, not "the users"). Zero unnecessary jargon; when a technical term is unavoidable (air-gap, plausible deniability), it is defined in one sentence the first time.

---

## 6. MVP scope (delivery: 10-Feb-2027)

### ✅ In the MVP

| Feature | Rationale |
|---|---|
| **One-way transfer via animated QRs** (sender → receiver) | The core. Protocol with error correction (Reed-Solomon or fountain codes), resume on frame loss, progress indicator. |
| **E2E encryption with libsodium** | X25519 for key exchange (the receiver's public key is shown as a static QR at the start), XSalsa20-Poly1305 for the payload. Ephemeral per-session keys. |
| **Desktop: Windows, macOS, Linux** | Non-negotiable challenge requirement. Flutter covers it with a single codebase. |
| **Duress mode (decoy PIN)** | Key differentiator. A real PIN and a decoy PIN; the decoy opens an environment with user-configurable decoy files. |
| **Optional self-destruct** | After N incorrect PIN attempts (configurable, off by default). Secure erasure of the encrypted database. |
| **3-step UX** | Pick file → show QR → confirm receipt. No configuration, no accounts, no visible cryptographic concepts. |
| **Documentation for non-technical users** | Install and usage guide with screenshots, FAQ, and a "journalist's guide" (step-by-step narrated use case). In Spanish and English. |
| **Reproducible builds + CI on GitHub Actions** | Explicit jury criterion ("build verifiability"). Signed binaries with published checksums. |
| **Open source (MIT or Apache 2.0) from day 1** | Non-negotiable challenge requirement. Public repo from the MVP's first commit. |

### ❌ NOT in the MVP (and why)

| Feature | Reason for exclusion |
|---|---|
| **Android/iOS mobile apps** | The challenge scores them as *extra*, not as a requirement. Flutter eases the port, but certifying camera + performance on phones doubles the QA effort. Announced as post-MVP roadmap to score vision points without risking the date. |
| **Simultaneous two-way transfer** | Protocol complexity (two full-duplex optical channels) with no proportional demonstrative value. The MVP allows swapping roles with a button. |
| **Steganography (hiding the QRs in images/video)** | The challenge's "stego" category. Tempting, but it is an entire second thesis. Documented as future work to show ambition without compromising the core. |
| **Folder / multi-file transfer** | The MVP supports one file or a `.zip` created by the app itself. Native directory-tree management is post-MVP. |
| **Integration with password managers / hardware keys** | Out of scope. The MVP uses PIN + local encryption with derived key (Argon2). |
| **"Room" mode (more than 2 devices)** | Protocol and UX complexity. Post-MVP. |
| **Translations beyond ES/EN** | Post-MVP, via community. |

### Cut-off criterion

Anything not in the "In" column that is not indispensable for the Act 2 demo to work in front of the jury **is not built before 10-Feb-2027**. The absolute priority is a small, solid, auditable core that can be demonstrated live.

---

## Annex — Decisions this document governs

1. Any proposal for a new feature is evaluated against section 6: is it in "In"? If not, is it indispensable for the demo? If the answer is no twice, it is parked.
2. Every technical encryption decision is resolved in favour of **libsodium with default parameters**. Zero home-grown cryptography.
3. Every UX decision is resolved in favour of **the non-technical person in scenario 3**. If Lucía doesn't understand it, it gets redesigned.
4. All public project communication uses the narrative in section 5: fundamental rights first, technology second.

---

*Living document. Relevant changes are recorded as new versions in this same file.*
