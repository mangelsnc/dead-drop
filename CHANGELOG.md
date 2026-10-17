# Changelog

All notable changes to DeadDrop are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository structure: `/app` (Flutter), `/docs`, `/design`, `/tools`
- GitHub Actions CI: builds for Linux, Windows, macOS on every push to main
- SHA-256 checksums published as artifacts for every build
- Reproducible build documentation (`docs/reproducible-builds.md`)
- Issue templates (bug report, feature request, security)
- PR template
- `tools/verify-build.sh` — verify local builds against CI hashes
- `tools/release.sh` — create tagged releases

## [0.1.0] — 2026-10-17

### Added
- Technical spike: animated-QR air-gap channel with E2E encryption
- Core crypto: libsodium X25519, XSalsa20-Poly1305 AEAD, Ed25519 signatures
- Fountain codes (LT code, robust soliton) for lossy channel tolerance
- QR frame wire format and rendering
- Lossy channel simulator and benchmark harness
- 12 passing tests
- Project documentation: README, FAQ, security model, usage guide
- MIT License, Code of Conduct, Contributing guide
