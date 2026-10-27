# iOS Build & Distribution

This document covers everything needed to build DeadDrop for iOS and distribute it to testers.

---

## 1. Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 14.0 (Sonoma) or later |
| **Xcode** | 15.4 or later (16.x recommended) |
| **Flutter SDK** | See `FLUTTER_VERSION` in `.github/workflows/build.yml` |
| **CocoaPods** | `sudo gem install cocoapods` or `brew install cocoapods` |
| **Apple ID** | Required for device builds (free account works for development) |
| **Apple Developer Program** | $99/year — required for TestFlight and Ad-Hoc distribution |

### Quick setup on a fresh Mac

```bash
# Install Xcode from the App Store, then:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

# Install CocoaPods
brew install cocoapods

# Install Flutter (if not already installed)
brew install --cask flutter

# Verify
flutter doctor
```

---

## 2. First-time iOS runner setup

The iOS runner directory is **not committed** to the repository (it's generated). To create it:

```bash
cd app
flutter create --platforms=ios .
```

This generates the `ios/` directory with the Xcode project, Podfile, and configuration files.

### Configure the bundle identifier

Edit `ios/Runner.xcodeproj/project.pbxproj` or open in Xcode:

```bash
open ios/Runner.xcworkspace
```

In Xcode → Runner → Signing & Capabilities:
- **Bundle Identifier**: `com.deaddrop.app` (or your team's identifier)
- **Team**: Select your Apple ID team
- **Signing**: Automatic (for development)

### Required iOS permissions

The app needs camera access for QR scanning. This is configured in `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>DeadDrop needs camera access to scan QR codes for file transfer.</string>
```

The `flutter create` template includes a placeholder; update it with the string above.

---

## 3. Building

### Debug build (simulator)

```bash
cd app
flutter build ios --debug --no-codesign
```

Output: `build/ios/iphonesimulator/Runner.app`

### Release build (simulator, unsigned)

```bash
flutter build ios --release --no-codesign
```

### Release build (device, unsigned)

```bash
flutter build ios --release --no-codesign
# The .app is at build/ios/iphoneos/Runner.app
# It cannot be installed on a device without signing.
```

### Release IPA (signed, for distribution)

```bash
flutter build ipa --release
```

This requires:
- A valid signing certificate in the keychain
- A provisioning profile matching the bundle ID
- Xcode configured with your team

Output: `build/ios/ipa/dead_drop.ipa`

### Build with specific export method

```bash
# For Ad-Hoc distribution
flutter build ipa --release --export-method ad-hoc

# For TestFlight / App Store
flutter build ipa --release --export-method app-store

# For development
flutter build ipa --release --export-method development
```

---

## 4. CI/CD (GitHub Actions)

The CI workflow includes an iOS build job that runs on macOS runners.

### What CI does

| Trigger | What happens |
|---------|-------------|
| Push to `main` | Builds unsigned IPA (simulator) to verify compilation |
| Tag `v*` | Builds unsigned IPA + includes it in the GitHub Release |

### Why unsigned?

GitHub Actions macOS runners don't have access to Apple signing certificates. The CI builds with `--no-codesign` to verify that the code compiles for iOS. Signed builds for distribution must be done locally or with a CI that has certificate access (e.g., Codemagic, Bitrise, or a self-hosted runner).

### Adding signed builds to CI (future)

To enable signed CI builds, you need to:

1. Export the signing certificate (.p12) and provisioning profile
2. Store them as GitHub Secrets:
   - `IOS_CERTIFICATE_BASE64` — base64-encoded .p12 file
   - `IOS_CERTIFICATE_PASSWORD` — password for the .p12
   - `IOS_PROVISIONING_PROFILE_BASE64` — base64-encoded .mobileprovision
   - `IOS_KEYCHAIN_PASSWORD` — random password for the temporary keychain
3. Update the CI workflow to import the certificate into a temporary keychain

See the `build-ios-signed` job in `.github/workflows/build.yml` for the implementation (currently commented out until secrets are configured).

---

## 5. Distribution

Releases are built and uploaded by hand. There is no distribution service
wired into this repository and no automation that uploads a build anywhere:
the challenge requires the app to make no network calls, and a distribution
SDK linked into the binary would contradict that claim in the one place a
reviewer is most likely to check.

### Option A: TestFlight

**Pros:** Official Apple channel, 10,000 testers, no device limit
**Cons:** $99/year Apple Developer account, 1-2 day review for the first build

```bash
flutter build ipa --release --export-method app-store
# Upload via Xcode -> Window -> Organizer -> Distribute App
```

### Option B: Ad-Hoc

**Pros:** No review, direct install
**Cons:** 100 devices/year, UDIDs collected by hand, profiles expire yearly

```bash
flutter build ipa --release --export-method ad-hoc
# Hand the .ipa to the tester directly.
```

### Comparison

| Feature | TestFlight | Ad-Hoc |
|---------|------------|--------|
| Cost | $99/year | $99/year |
| Apple review | Yes (first build) | No |
| Max testers | 10,000 testers | 100 devices |
| Install method | TestFlight app | Direct IPA |
| Device registration | Not needed | Manual UDID |
| Expiration | 90 days per build | 1 year (profile) |

---

## 6. Release checksums

Publish a SHA-256 for every artefact you hand out, so a tester can verify
the build they install is the one you built:

```bash
shasum -a 256 build/ios/ipa/*.ipa
```

See `docs/reproducible-builds.md` for how this fits the wider verification
story.

---

## 7. Troubleshooting

| Problem | Solution |
|---------|----------|
| `sodium_libs` fails on iOS | Ensure `use_frameworks!` is in `ios/Podfile` (Flutter default) |
| Camera permission denied | Check `NSCameraUsageDescription` in `Info.plist` |
| Signing error | Open `ios/Runner.xcworkspace` in Xcode, select team in Signing & Capabilities |
| Pod install fails | `cd ios && pod install --repo-update` |
| Build fails on CI | Check that `FLUTTER_VERSION` matches a version with iOS support |
| IPA too large | Check `flutter build ipa --analyze-size` for size breakdown |

---

## 8. Checklist for first iOS release

- [ ] Mac with Xcode 15.4+ available
- [ ] `flutter create --platforms=ios .` run in `app/`
- [ ] Bundle ID configured (`com.deaddrop.app`)
- [ ] Camera permission description in `Info.plist`
- [ ] Apple Developer account created (if using TestFlight)
- [ ] Test build on simulator: `flutter build ios --debug --no-codesign`
- [ ] Test build for device: `flutter build ipa --release`
- [ ] SHA-256 published for the artefact handed to testers
- [ ] Tester guide shared with testers
