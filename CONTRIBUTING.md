# How to contribute to DeadDrop

Thanks for wanting to help. DeadDrop is a free software project (MIT) built for the **#cryptograFREE** challenge (RootedCON + Criptored), and every contribution is welcome: code, documentation, translation, design, testing or spreading the word.

---

## Ways to contribute (not everything is programming)

- **Report bugs or propose improvements:** open an [issue](https://github.com/mangelsnc/dead-drop/issues) describing what happened, what you expected, and on what system.
- **Documentation:** if anything in the [user guide](docs/user-guide.md) or the [FAQ](docs/faq.md) confused you, improving it is a first-class contribution. This project is judged precisely on being usable by non-technical people.
- **Translation:** the base documentation is in English and Spanish. More languages are welcome.
- **Design and UX:** mockups, icons, clearer flows.
- **Code:** Dart/Flutter in the app, GitHub Actions in the CI.
- **Security review:** auditing the code is one of the best ways to help. For vulnerabilities, **do not use public issues** — see `SECURITY.md` when available.

## Project principles (read them before proposing)

1. **The non-technical person rules the UX.** If a feature can't be explained without cryptographic jargon, it's not ready. The check question is: "would someone who doesn't know what a public key is understand it?"
2. **Zero home-grown cryptography.** Everything cryptographic is solved with libsodium and its default parameters.
3. **Zero network.** No feature may require connectivity. No telemetry, no accounts, no servers.
4. **Everything in public.** Decisions, code and documentation live in this repo from day one.

## Workflow

1. **Open or comment on an issue** before starting work, to avoid duplicating effort.
2. **Fork and create a descriptive branch:** `fix/qr-reading-low-light`, `docs/faq-legality`, etc.
3. **Clear commits:** format `type: brief description` (e.g. `feat: resume transfer after pause`, `docs: user guide screenshots`). Types: `feat`, `fix`, `docs`, `test`, `refactor`, `ci`. The type decides the next version number — `feat:` is a minor, a `!` or a `BREAKING CHANGE` body is a major, anything else is a patch — so get it right and the release takes care of itself. See [docs/versioning.md](docs/versioning.md).
4. **Open a Pull Request** against `main` describing what it changes and why. If it touches UX, include screenshots. If it touches cryptography, expect an extra-rigorous review — and be ready to justify why default libsodium is not enough (hint: it almost always is).
5. CI must pass (tests + build on Windows, macOS and Linux).

## Development environment

The stack is **Flutter** (Dart) + **libsodium**.

**Option A — Docker (recommended, no Flutter install on your machine):**

```bash
# Requirement: Docker only
git clone https://github.com/mangelsnc/dead-drop.git
cd dead-drop
make build-linux   # builds the Linux desktop app
make test          # tests
make analyze       # static analysis
make shell         # interactive shell inside the container
```

Full guide in [docs/development.md](docs/development.md).

**Option B — Native Flutter:**

```bash
# Requirements: stable Flutter SDK (see pinned version in the repo)
git clone https://github.com/mangelsnc/dead-drop.git
cd dead-drop/app
flutter pub get
flutter run            # runs on your platform
flutter test           # tests
```

Reproducible builds and binary signing are documented in each release and in [docs/security.md](docs/security.md).

## Code style

- Dart: `flutter analyze` with no warnings, formatted with `dart format`.
- Comment the *why*, not the *what*.
- No new dependencies without prior discussion in an issue: every dependency is audit surface.

## Code of conduct

Everyone participating in DeadDrop accepts the [Code of Conduct](CODE_OF_CONDUCT.md). Summary: respect, no exceptions.

## Licence

By contributing you accept that your contribution is distributed under the project's [MIT licence](LICENSE), forever.
