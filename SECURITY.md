# Security Policy

## Reporting a vulnerability

**Do not open a public issue for a security problem.** A public report
describes the attack before the fix exists, and the people this app is built
for are the ones who pay for that gap.

Two private channels, either is fine:

- **GitHub Security Advisories** — [report it
  here](https://github.com/mangelsnc/dead-drop/security/advisories/new).
  Preferred: it keeps the report, the discussion and the fix in one place,
  and it gives you credit when the advisory is published.
- **Email** — mangel@secture.com, with `[DeadDrop security]` in the subject.

Include what you need to make the problem reproducible: the version, the
platform, and the steps. Proof-of-concept code is welcome and stays private
as long as the report does.

### What to expect

This is a project maintained by one person, so these are honest targets
rather than a commercial SLA:

| Stage | Target |
|---|---|
| Acknowledgement that the report arrived | 72 hours |
| First assessment: is it a vulnerability, and how severe | 7 days |
| Fix released, or a public explanation of why there is none yet | 90 days |

Disclosure is coordinated: the advisory goes public with the fix, or at 90
days if a fix is not possible, whichever comes first. If you want to publish
sooner, say so and we will agree a date rather than argue about it after the
fact.

## Supported versions

Only the **latest release** receives security fixes. The project is in active
development toward its MVP, and backporting to older tags would spread a
small amount of review across more surface than it can cover honestly.

## Scope

In scope: the application in this repository — the wire protocol, the
cryptographic orchestration, the vault, the decoy environment, self-destruct,
and the build and release pipeline.

Out of scope, because they are not defects this project can fix:

- **The absence of an external audit.** No independent party has reviewed
  this code. That is a stated limitation, documented in
  [docs/security.md](docs/security.md), not a vulnerability to report.
- **Limits that are documented and deliberate**, such as self-destruct
  discarding keys rather than erasing bytes, or an unprepared decoy being
  unconvincing. [docs/security.md](docs/security.md) lists them. A report
  showing one is *worse than documented* is in scope and welcome.
- **Attacks on the physical channel.** Anyone who can see the sending screen
  can photograph the QR codes. The payload is encrypted to the receiver, and
  an attacker in that position has already defeated more than this app.
- Vulnerabilities in the operating system, the camera driver, or a
  third-party dependency — report those upstream. Tell us anyway if DeadDrop
  makes one materially worse.

## What this project promises about its own security

It orchestrates audited primitives (libsodium) and never implements
cryptography of its own. Each primitive is pinned against published test
vectors, and both wire formats are pinned to canonical bytes.

What it does **not** promise is that the orchestration is correct. Nobody
independent has checked it. Everything in
[docs/security.md](docs/security.md) is written to be read with that in mind.
