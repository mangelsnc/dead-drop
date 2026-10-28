# Changelog

All notable changes to DeadDrop are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.3] — 2026-10-28

### Miscellaneous

- Update the actions that were warning about Node 20

## [0.9.2] — 2026-10-28

### Miscellaneous

- Build macOS too, so a branch can be tested on both ends

## [0.9.1] — 2026-10-28

### Miscellaneous

- Build a signed APK from any branch, for testing on a device

## [0.9.0] — 2026-10-28

### Added

- *(vault)* Search and sort the file list, and keep the identity stable

### Other

- Vault list controls, a visible save confirmation, and a stable identity

## [0.8.0] — 2026-10-28

### Added

- *(vault)* Send a file from the vault, and say when one is saved

### Fixed

- *(protocol)* The file name survives, and a decoy needs its own passphrase

### Other

- Five more reports from device testing

## [0.7.0] — 2026-10-28

### Added

- *(vault)* View, export and delete a file you have stored

### Fixed

- *(receive)* Measure the camera on mobile, and stop the screen dimming
- *(receive)* Stop the sender block pushing the progress off the screen
- *(vault)* One address book and one identity outside the decoy

### Other

- The six reports from device testing

## [0.6.0] — 2026-10-28

### Added

- The real app icon, on all five platforms

## [0.5.5] — 2026-10-28

### Fixed

- *(macos)* The app could not reach the camera, files or the keychain

## [0.5.4] — 2026-10-27

### Miscellaneous

- Prove the Linux packaging is deterministic instead of asserting it

## [0.5.3] — 2026-10-27

### Documentation

- Describe the artifacts the project actually publishes

## [0.5.2] — 2026-10-27

### Fixed

- *(ci)* Package the Linux build reproducibly, as the docs already claim

## [0.5.1] — 2026-10-27

### Fixed

- *(ci)* Make the Android job survive its first two failures

## [0.5.0] — 2026-10-27

### Added

- *(ci)* Ship a signed Android APK with every release

## [0.4.0] — 2026-10-27

### Added

- *(ci)* Tag releases to a written policy, and actually publish them

## [0.3.0] — 2026-10-27

### Added

- Port spike core to Dart — crypto.dart (X25519, XSalsa20-Poly1305, Ed25519)
- Port spike core to Dart — fountain.dart (LT code, robust soliton)
- Port spike core to Dart — qrframe.dart (binary wire format)
- Port spike core to Dart — emitter.dart (file → QR frames)
- Port spike core to Dart — receiver.dart (QR frames → file)
- Flutter UI — main.dart with home navigation
- Flutter UI — home_screen.dart
- Flutter UI — send_screen.dart (file picker, bootstrap QR, params)
- Flutter UI — receive_screen.dart (camera scanner, progress)
- Add missing ui/home_page.dart
- Add missing ui/send/send_page.dart
- Add missing ui/receive/receive_page.dart
- Automatic release workflow on merge to main (#5)
- Apply WCAG 2.1 AA colors to Flutter theme
- Dockerized dev environment + Makefile (#12)
- IOS build setup, distribution config, and testing guide (#8)
- *(makefile)* Add build-macos target (host-only, with warning) (#13)
- *(makefile)* Unify build-ios and build-macos as host-only targets (#14)
- Add iOS preparation script for Mac setup (#15)
- Firebase App Distribution setup for iOS beta testing (#16)
- Android Firebase App Distribution setup (#20)
- Functional E2E prototype v0.1 — QR handshake, robust transport, timed transfer tests (#25)
- *(receive)* Add QR/text toggle for receiver public key (#31)
- *(send)* Richer file info tile with type icon and metadata (#34)
- *(send)* Enhance file info tile — info button, rich metadata, human sizes (#40)
- Transfer controls, screen wakelock, and a better icon (#62)
- *(vault)* Encrypted at-rest storage with a decoy environment (#61)
- *(scanner)* Decode QR frames on Linux and Windows
- *(scanner)* Drive a desktop camera and decode its frames
- *(a11y)* Let the user set the size of codes and keys
- *(protocol)* Let the receiver suggest emission settings in its QR
- *(senders)* A page for the senders this device knows
- *(scanner)* Measure the camera, and show how well it is reading
- *(vault)* Let the user read back the passphrase they are typing
- *(vault)* Let the user erase a vault, both environments at once
- *(protocol)* The receiver's camera measurement now reaches the sender

### Changed

- Consolidate to lib/core + lib/ui implementation
- Consolidate to lib/core + lib/ui implementation
- Extract duplicate _constantTimeEquals into src/utils.dart (#44)

### Documentation

- Technical specification v1 (architecture, protocol, crypto, duress mode)
- Add build instructions for all platforms
- Translate core docs to English for submission PDF (#22)
- Translate README, FAQ, CONTRIBUTING and CODE_OF_CONDUCT to English (#24)
- Add weekly status report W42 and usability test results (#26)
- Mark decoy PIN, at-rest encryption and self-destruct as not implemented (#37)
- Establish parallel-work discipline (worktree-based) (#38)
- Fix F0 — rewrite usability-test.md as protocol, add reconstructed submission.md (#47)
- Design for the vault and coercion-resistance features (#57)
- State what has actually been tested on devices (#65)
- The vault ships, so stop telling users it does not (#73)
- Deleting a vault, revealing a passphrase, and the camera suggestion
- Draw the transfer diagram instead of spelling it in ASCII

### Fixed

- Rewrite send_page.dart to use src/ API
- Rewrite receive_page.dart to use src/ API
- Rewrite integration_test.dart to use src/ API
- Add missing dart:io import to receive_page.dart
- Resolve flutter analyze errors blocking CI (#6)
- Change Android applicationId to dev.deaddrop.dead_drop (#19)
- Load libsodium manually in integration tests (#9)
- *(android)* Resolve build warnings — compileSdk 35, disable Gradle VFS watcher in Docker (#21)
- Redesign send page UX + camera robustness for desktop (#30)
- *(send)* Remove duplicate frame counter under QR code (#33)
- *(crypto)* Mandatory Ed25519 signature verification + persistent identity + TOFU (#35)
- *(receiver)* Bounds-check chunkIds before feeding the fountain decoder (#41)
- *(fountain)* Deterministic PRNG for chunk selection (audit #2) (#43)
- *(crypto)* Align hash docs and spike with BLAKE2b implementation (#45)
- *(send)* Reject chunkCount overflow instead of silently corrupting the header (#36)
- *(docker)* Add libsecret-1-dev for flutter_secure_storage_linux (#49)
- *(make)* Rebuild dev image automatically when Dockerfile changes (#50)
- *(android)* Sign release builds with an upload key when one is configured (#54)
- *(make)* Mount the signing keystore into the Android build container (#55)
- *(ci)* The Linux artifact never reached the release (#58)
- *(android)* Move MainActivity to the package the manifest resolves to (#59)
- *(receive)* Require user approval before trusting a new sender (#51)
- The four issues from device testing — key re-entry, save location, desktop layout, named senders (#70)
- *(ci)* Bump FLUTTER_VERSION, and fail fast when it drifts from .fvmrc
- Actually wire the desktop scanner into both pages
- *(receive)* Stack the save buttons, undistort the preview, show progress
- *(vault)* A vault configured in a previous run was invisible after a restart
- *(android)* Unblock the build after the Flutter upgrade
- *(ui)* Leaving a transfer screen clears what was staged there

### Miscellaneous

- Remove duplicate app/lib/screens/ directory
- Add GoogleService-Info.plist for Firebase App Distribution (#17)
- Add Android platform files and pubspec.lock (#18)
- Remove internal coordination docs from public repo (#27)
- Repo cleanup — remove internal docs, translate spike decisions to English (#32)
- Reproducible builds verification + deterministic packaging (#42)
- Pin the Flutter version in .fvmrc and enforce it on Apple builds (#52)
- *(ios)* Add the iOS platform files and an unsigned build check (#53)
- Ignore every build artefact, especially Xcode's (#56)
- Ignore Firebase credentials repo-wide (#64)
- Bump to 0.3.0 (#72)
- Flutter 3.24.5 -> 3.47.8, sodium_libs -> sodium 4.1.2
- Label this project's Docker resources so they can be cleaned up
- Report the build cache by age before pruning it
- Remove the Firebase integration and the fastlane lanes
- The repository carries code, not the contest paperwork
- Drop the spike workflow, which has never had tests to run

### Other

- Remove Firebase config files from git tracking (#23)

### Tests

- Integration tests — crypto, fountain, frames, E2E transfers (1KB/100KB/1MB)

## [0.1.0] — 2026-10-17

### Added

- *(spike)* Validate animated-QR air-gap channel with E2E encryption
- Add Flutter app skeleton (pubspec.yaml)
- Add Flutter analysis options
- Add Flutter main.dart skeleton
- Add Flutter .gitignore
- Add design directory placeholder
- Add tools directory placeholder
- Add verify-build.sh tool
- Add release.sh tool
- Add bug report issue template
- Add feature request issue template
- Add security issue template
- Add issue template config
- Add PR template

### Documentation

- Plan de proyecto y registro de riesgos (COO)
- Propuesta de valor y narrativa para el jurado
- README público v1 — qué es, instalación en 3 pasos, primer uso
- Guía de uso paso a paso para personas no técnicas
- FAQ con 20 preguntas reales de usuarios
- Modelo de amenaza en llano + versión técnica para auditores
- CONTRIBUTING.md — formas de contribuir, principios, flujo, stack
- CODE_OF_CONDUCT.md (adaptación Contributor Covenant 2.1)
- LICENSE MIT (requisito no negociable del reto)
- Add CHANGELOG.md (SemVer + Keep a Changelog)
- Add reproducible builds documentation


