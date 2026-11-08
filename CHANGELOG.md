# Changelog

All notable changes to DeadDrop are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.3] — 2026-11-08

### Fixed

- *(vault)* Stop the form stretching across a desktop window

### Tests

- *(vault)* Pin what each erasure path leaves on disk

## [1.3.2] — 2026-11-08

### Miscellaneous

- *(android)* Fetch the Gradle distribution with curl, not the wrapper

## [1.3.1] — 2026-11-08

### Miscellaneous

- *(android)* Retry the Gradle distribution download

### Tests

- *(crypto)* Hold the forward-secrecy claim with a test

## [1.3.0] — 2026-11-08

### Added

- *(send)* Show what the window holds in a diagnostic build

### Fixed

- *(send)* Re-pin the screen while a transfer is still running

### Tests

- *(crypto)* Check the primitives against published vectors

## [1.2.0] — 2026-11-07

### Added

- *(receive)* Give a fingerprint words a person can say

### Fixed

- *(macos)* Stop a debug build asking for network access
- *(vault)* Hide the passphrase again after a failed attempt
- *(send)* An unmeasured screen is not a permissive one

### Tests

- *(elapsed)* Stop the readout test racing the clock

## [1.1.0] — 2026-11-07

### Added

- *(vault)* Ask for both passphrases when creating a vault

### Documentation

- *(adr)* Provision the decoy when the vault is created

### Fixed

- *(vault)* Stop Settings telling an attacker which environment is open
- *(vault)* Close the path that could overwrite a decoy unseen

## [1.0.3] — 2026-11-06

### Other

- *(vault)* Let the rehearsal show its wait too

## [1.0.2] — 2026-11-06

### Other

- *(vault)* Let a build rehearse self-destruct in three attempts

## [1.0.1] — 2026-11-05

### Fixed

- *(vault)* Say what the unlock pause is

## [1.0.0] — 2026-11-05

### Documentation

- *(faq)* The keychain prompts are per item, not per signature

### Fixed

- *(receive)* Say what to do about a rejected session
- *(send)* Recalibrate the density floor against hardware

### Other

- The zxing2 scanner, and the quiet zone that made it work

## [0.9.8] — 2026-10-31

### Added

- *(send)* Show the frame rate the screen manages, not the one asked for
- *(scanner)* Give a declined camera a way back
- *(receive)* Keep the time a transfer took after it finishes

### Documentation

- Correct what the documentation says the app does
- Describe the product, not the development
- *(macos)* Record what the keychain measurement actually showed
- *(faq)* Explain the macOS keychain prompts

### Fixed

- *(send)* A transfer set to 60% brightness emitted at full
- *(send)* Line the sending screen up with the code
- *(docker)* Stop compose drifting and docker-clean deleting other projects
- *(macos)* Name the app in the keychain prompt, not the plugin
- *(scanner)* Stop the camera asking for 30 repaints a second
- *(send)* Give the emitted code its quiet zone
- *(receive)* Report where the user is looking
- *(screen)* Count wakelock holders instead of flagging one

### Miscellaneous

- Build Linux from a branch too (#81)
- Let a test build carry the emission profiler
- Let a test build save camera frames for diagnosis
- Build Linux from a branch too (#81)

### Other

- *(send)* Time the two halves of a frame, behind a build flag
- *(send)* Measure the QR's share of a frame instead of assuming it
- *(send)* Measure the frame with the engine's own clock
- *(scanner)* Say which pixel format the camera delivers
- *(scanner)* Let a debug build save the frames it decodes

### Performance

- *(send)* Draw the QR as an image, not 7,921 rectangles
- *(send)* Stop building eleven throwaway QR codes per frame

## [0.9.7] — 2026-10-30

### Fixed

- *(ci)* Give the Android build enough heap (#79)

## [0.9.6] — 2026-10-30

### Miscellaneous

- Move the macOS and iOS jobs off a runner being retired (#80)

## [0.9.5] — 2026-10-30

### Fixed

- *(ci)* Pass the version to test builds (#78)

## [0.9.4] — 2026-10-28

### Miscellaneous

- Pin every action to a commit SHA

## [0.9.3] — 2026-10-28

### Miscellaneous

- Update the actions that were warning about Node 20

## [0.9.2] — 2026-10-28

### Added

- *(scanner)* Decode in Dart everywhere, so the APK stops asking for INTERNET
- *(settings)* Show the app version in About
- [**breaking**] Derive chunk ids from the seed instead of transmitting them
- *(send)* Explain the transfer settings, and fix the EC selector on a phone
- *(vault)* Recolour the icon, and let a forgotten passphrase delete
- *(send)* Let the sender choose how bright the screen emits

### Documentation

- Record why frames vary in size, and what it would cost to fix
- A device test plan for the Redmi Note 14 and macOS
- Drop the device test plan

### Fixed

- Fewer codes to scan, an undistorted preview, and a transfer that survives
- *(scanner)* The camera preview was rendering as a single pixel
- *(scanner)* The preview was stretched because the sensor is sideways
- *(scanner)* Let the preview keep its own shape instead of imposing one
- *(scanner)* Lay the preview out with the displayed ratio, not the sensor's
- *(scanner)* Drop a code read twice in a row
- *(scanner)* Decode on the main isolate, and refuse QR sizes that cannot render
- *(scanner)* Capture enough pixels to resolve the code
- *(send)* Draw the QR at the size the screen allows, and stop the flash
- *(send)* Stop the QR overflowing its box and hiding under the controls
- *(scanner)* The desktop was capturing at 320x240
- *(receive)* Keep the progress on screen on a phone
- *(receive)* Report progress that reflects the work done
- *(receive)* A progress bar that rises, inside the step it belongs to
- Say when a screen cannot show a code, and stop it dimming
- *(receive)* The sender appeared twice at once
- *(scanner)* Measure the camera's rate, not our own throughput
- *(hint)* Stop recommending stronger error correction
- *(scanner)* Measure what a decode costs, replacing a counter that could only read zero
- *(receive)* Centre the content when there is no second column to fill
- *(send)* Negotiate the handshake against a predicted size, not against zero
- *(send)* Give the code the height the furniture was taking
- *(send)* Make the transfer controls look like controls again
- *(send)* Let a late receiver join a transfer already running
- *(send)* Stop advising a phone to enlarge a window it has not got
- *(send)* Size and rank the transfer controls

### Miscellaneous

- Record qr as a direct dependency in the lock file
- Build macOS too, so a branch can be tested on both ends

### Other

- *(scanner)* Show where the frames are going
- *(scanner)* Show what fraction of frames the decoder drops
- *(send)* Show what the receiver asked for, beside what is in force
- Add a target for running one test file

### Tests

- *(scanner)* Measure which module colours this decoder will read

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


