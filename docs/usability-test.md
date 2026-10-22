# Usability Test Protocol — DeadDrop

**Date:** October 19, 2026
**Author:** Lía Ferrán (UX/UI Designer)
**Status:** v2.0 — Protocol defined, sessions not yet conducted
**Method:** Moderated task-based testing with high-fidelity mockups (mobile P0 set)

> **⚠️ IMPORTANT:** This document describes a **planned usability testing protocol**.
> No human testing sessions have been conducted yet. The scenarios, participant
> profiles, and expected outcomes below are **design targets**, not measured results.
> Do not cite any numbers from this document as user-test evidence.

---

## 1. Test script

### 1.1 Setup

- **Prototype:** High-fidelity HTML mockups (`design/mockups/`), mobile set (390×844), presented on a laptop screen. Participants will be told: *"This is a prototype of an app. It looks real but some things won't respond. Tell me what you would tap and what you expect to happen."*
- **Moderator:** TBD (human moderator required)
- **Duration:** 25–35 minutes per session (estimated)
- **Format:** Think-aloud protocol. The moderator does not help unless the participant is stuck for >60 seconds. Every intervention is logged.
- **Scenario:** *"You and a friend are in the same room. Your friend has a PDF on their phone that you need. There's no Wi-Fi and you don't want to use mobile data. You both have this app installed."*

### 1.2 The 5 tasks

| # | Task | What it validates | Success criterion |
|---|------|-------------------|-------------------|
| T1 | **First launch & comprehension.** "Open the app for the first time. What do you think this app does? What would you do first?" | Onboarding clarity, value proposition | Participant can explain the app's purpose in their own words without reading the tagline back |
| T2 | **Send a file.** "You have a file called `contract.pdf` on your phone. Send it to your friend." | Send flow: select → configure → PIN → QR | Participant reaches the QR screen without help |
| T3 | **Receive a file.** "Now you're the friend. Receive the file." | Receive flow: camera → scanning → PIN → save | Participant reaches the "Saved" screen without help |
| T4 | **Understand the PIN.** "Whose PIN is this? Who needs to know it? What happens if you get it wrong?" | PIN mental model (sender sets it, receiver enters it) | Participant correctly explains the PIN is set by the sender and shared verbally |
| T5 | **Duress mode comprehension.** "Imagine someone forces you to unlock this app. What could you do?" (Then show duress mode screens.) | Duress mode discoverability and comprehension | Participant understands the decoy PIN concept and can explain when they'd use it |

### 1.3 Post-test questions

1. "If you had to describe this app to a friend in one sentence, what would you say?"
2. "Was there any moment where you felt lost or unsure?"
3. "Is there anything you'd remove? Anything that's missing?"
4. "Would you trust this app with a sensitive document? Why or why not?"

---

## 2. Target participant profiles

We aim to recruit 5 participants matching the profiles from `docs/user-research.md`. None should have technical backgrounds.

| ID | Age range | Occupation type | Profile match | Expected tech level |
|----|-----------|-----------------|---------------|-------------------|
| P1 | 50–55 | Administrative / office work | Profile 3 (lawyer/whistleblower) | Low — WhatsApp, email, Word. No Signal. |
| P2 | 30–40 | Freelance creative | Profile 1 (journalist) | Medium-low — uses Signal, knows what a VPN is |
| P3 | 25–35 | NGO / advocacy | Profile 2 (activist) | Low-medium — uses Signal "because friends do", doesn't verify keys |
| P4 | 55–65 | Retired / non-digital-native | Profile 4 (privacy-conscious citizen) | Very low — smartphone basics only |
| P5 | 35–45 | Small business owner | Profile 3/4 hybrid | Low — email and WhatsApp for business |

---

## 3. Hypotheses and expected outcomes

These are our **pre-test hypotheses** — what we expect to find. They are not results.

### 3.1 What we expect to confuse users

| # | Hypothesis | Rationale | Severity if confirmed |
|---|-----------|-----------|----------------------|
| H1 | **PIN mental model: "Whose PIN?"** | The receive-side PIN screen may confuse users about whose PIN to enter. The subtitle *"The person who sent you the file gave it to you"* should resolve it, but hesitation is expected. | Medium |
| H2 | **Weak PIN choices** | Users will likely choose simple PINs (`1234`, `0000`, patterns). The app doesn't currently encourage stronger PINs. | Low |
| H3 | **Onboarding skip rate** | Some users will skip onboarding screens. The "How it works" screen is essential for users who don't know what a QR transfer is. | Low |
| H4 | **Duress mode discoverability** | We expect **zero participants** to find duress mode on their own. It's buried in Settings. Users who need it most would never find it alone. | High |
| H5 | **"Self-destruct" label** | The label is jargon. The subtitle explains it, but the label itself may confuse. | Low |

### 3.2 What we expect to reassure users

| # | Hypothesis | Rationale |
|---|-----------|-----------|
| H6 | **The QR analogy is universal.** | Most people have scanned a QR code (restaurant menus, pharmacy, etc.). The "one phone shows, the other scans" model should be immediately understood. |
| H7 | **Camera permission explanation works.** | The pre-permission screen (*"We only use it to read the code on the other screen. We don't record or save anything."*) should build trust. |
| H8 | **Progress feedback reduces anxiety.** | The progress bar, frame counter, and haptic feedback should reassure users the transfer is working. |
| H9 | **"Saved to Downloads" is the right level of detail.** | Most users know where Downloads is. |
| H10 | **The fake environment is convincing.** | The decoy environment should look identical to the real one. If fake files are openable, it validates the anti-leak requirement. |

### 3.3 What we expect to be unnecessary

| # | Hypothesis | Rationale |
|---|-----------|-----------|
| H11 | **Speed chips will be ignored.** | Most users won't notice or use the Slow/Normal/Fast chips. Consider hiding behind an "advanced" toggle. |
| H12 | **"Recent files" list will be underused.** | Most users will tap "Choose file" directly. The recent list saves a tap for repeat users but isn't a discovery mechanism. |

---

## 4. Proposed changes (pre-test, based on hypotheses)

These changes are **already justified by design review** and do not depend on test results. Testing will validate or refine them.

### 4.1 Design changes

| # | Change | Addresses | Priority | Effort |
|---|--------|-----------|----------|--------|
| C1 | **Add a one-line hint on the receive PIN screen:** *"The sender chose this PIN. Ask them for it."* | H1 (PIN confusion) | High | Trivial (copy change) |
| C2 | **Add a subtle "per-send" note on the send PIN screen:** *"This PIN is only for this file. You'll choose a new one next time."* | H1 (per-send confusion) | Medium | Trivial (copy change) |
| C3 | **Encourage stronger PINs without being annoying:** If the user enters `1234`, `0000`, `1111`, or a keypad pattern, show a gentle inline suggestion: *"That PIN is easy to guess. Try mixing it up?"* | H2 (weak PINs) | Medium | Low |
| C4 | **Surface duress mode after first successful transfer.** After "Sent!" or "Saved!", show a one-time card: *"Did you know? You can set up a decoy PIN that shows fake files if someone forces you to open the app. [Learn more] [Not now]"* | H4 (discoverability) | **Critical** | Low |
| C5 | **Rename "Self-destruct" to "Delete after opening"** | H5 (jargon) | Low | Trivial (copy change) |
| C6 | **Make the "How it works" onboarding screen non-skippable on first launch.** Or add a "How it works" link on the home screen. | H3 (skip rate) | Medium | Low |
| C7 | **Move speed chips into a collapsible "Advanced" section on the QR screen.** | H11 (ignored chips) | Low | Low |

### 4.2 Narrative changes

| # | Change | Addresses | Priority |
|---|--------|-----------|----------|
| C8 | **Lead with the QR analogy in all marketing copy:** *"Like scanning a menu at a restaurant, but for files."* | H6 | High |
| C9 | **Mention duress mode in the app store description and onboarding screen 3.** Not as a headline feature, but as a bullet: *"Optional decoy mode for high-risk situations."* | H4 | High |
| C10 | **Use "no internet, no cables, no logs" as the primary tagline.** | H6 | Already done |

---

## 5. Metrics to collect

When sessions are conducted, we will record:

| Metric | How measured |
|--------|-------------|
| Task completion rate (T2: Send) | Binary: completed without help / needed help / failed |
| Task completion rate (T3: Receive) | Binary |
| Completed transfer without any help | Binary |
| Understood PIN mental model (T4) | Binary |
| Understood duress mode after explanation (T5) | Binary |
| Discovered duress mode without being shown | Binary |
| Time to complete send flow | Seconds |
| Time to complete receive flow | Seconds |
| Would use the app | Yes/no + why |
| Would recommend to a friend | Yes/no + why |

---

## 6. Next steps

1. **Implement C1, C2, C5** (copy changes) — trivial, can be done immediately without waiting for tests.
2. **Implement C4** (duress mode discovery card) — highest-impact change. Needs a new mockup.
3. **Implement C3** (PIN strength nudge) — low effort, good security practice.
4. **Implement C6** (non-skippable "How it works") — needs a decision: force the screen or add a home link?
5. **Recruit 5 participants** matching the profiles in §2 and **conduct the sessions** with a human moderator.
6. **Record results** in this document, replacing hypotheses with measured data.

---

*Usability test protocol v2.0 — Lía Ferrán, 2026-10-19. Corrected to clarify that no sessions have been conducted.*
