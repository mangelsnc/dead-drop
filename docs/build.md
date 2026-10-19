# Building DeadDrop

This document covers how to build DeadDrop from source on every supported platform.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.24.5 (the version CI uses; any 3.4.0+ should work)
- Git
- Platform-specific toolchain (see below)

## Quick start

```bash
git clone https://github.com/mangelsnc/dead-drop.git
cd dead-drop/app
flutter pub get
flutter run
```

## Platform setup

### Linux

```bash
# Install Flutter
sudo snap install flutter --classic

# Install build dependencies
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev

# Enable desktop support
flutter config --enable-linux-desktop

# Build
cd app
flutter build linux --release
```

Output: `app/build/linux/x64/release/bundle/dead_drop`

**Camera:** receiving files needs a working webcam (V4L2). Most desktop
webcams work out of the box; check with `v4l2-ctl --list-devices`.

### macOS

```bash
# Install Flutter
brew install --cask flutter

# Enable desktop support
flutter config --enable-macos-desktop

# Build
cd app
flutter build macos --release
```

Output: `app/build/macos/Build/Products/Release/dead_drop.app`

**Camera permission:** the app declares `NSCameraUsageDescription` in
`macos/Runner/Info.plist`. macOS will ask for camera access the first time
you scan; grant it or receiving cannot work.

### Windows

```powershell
# Install Flutter (see https://docs.flutter.dev/get-started/install/windows)
# Install Visual Studio Build Tools with the "Desktop development with C++" workload

# Enable desktop support
flutter config --enable-windows-desktop

# Build
cd app
flutter build windows --release
```

Output: `app\build\windows\x64\runner\Release\dead_drop.exe`

### Android

```bash
# Install Android Studio + SDK, then:
cd app
flutter build apk --release
```

Output: `app/build/app/outputs/flutter-apk/app-release.apk`

### iOS

**Requires macOS with Xcode 15.4+ and CocoaPods.**

```bash
cd app
flutter build ios --release --no-codesign   # unsigned, for local testing
flutter build ipa --release                  # signed, for distribution
```

For detailed iOS build and distribution instructions, see [ios-build.md](ios-build.md).

## Running tests

```bash
cd dead-drop/app
flutter pub get
flutter test
```

The integration suite (`test/integration_test.dart`) covers the full
protocol end to end: crypto roundtrips, the LT fountain code, frame
packing, the QR transport envelope, the key handshake, and timed transfers
of 1 KB / 100 KB / 1 MB files (the timings are printed as `[benchmark]`
lines in the test output).

## Reproducible builds & CI

Every push to `main` builds Linux, Windows and macOS artifacts in GitHub
Actions (`.github/workflows/build.yml`) with a pinned Flutter version and
publishes SHA-256 checksums. See [reproducible-builds.md](reproducible-builds.md)
for instructions on verifying that a downloaded binary matches the source code.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `sodium_libs` fails to load | Run `flutter pub get` and ensure platform runners exist (`flutter create .`) |
| Camera not working on desktop | `mobile_scanner` requires a camera; on Linux ensure `v4l2` is available |
| QR codes not scanning | Ensure good lighting, hold the camera steady, and try lowering the frame rate (fps) on the sender |
| Transfer stalls mid-way | Keep both devices still; the fountain code recovers from lost frames automatically — just keep scanning |
| Build fails on Linux | Install `libgtk-3-dev` and `pkg-config` |
| Build fails on Windows | Install Visual Studio Build Tools with C++ workload |
