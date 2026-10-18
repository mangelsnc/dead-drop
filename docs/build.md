# Building DeadDrop

This document covers how to build DeadDrop from source on every supported platform.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.4.0 or later
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
flutter build linux
```

Output: `build/linux/x64/release/bundle/dead_drop`

### macOS

```bash
# Install Flutter
brew install --cask flutter

# Enable desktop support
flutter config --enable-macos-desktop

# Build
flutter build macos
```

Output: `build/macos/Build/Products/Release/dead_drop.app`

### Windows

```powershell
# Install Flutter (see https://docs.flutter.dev/get-started/install/windows)

# Enable desktop support
flutter config --enable-windows-desktop

# Build
flutter build windows
```

Output: `build\windows\x64\runner\Release\dead_drop.exe`

### Android

```bash
# Install Android Studio + SDK, then:
flutter build apk          # debug APK
flutter build apk --release  # release APK
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### iOS

```bash
# Requires macOS + Xcode
flutter build ios
flutter build ipa  # for distribution
```

## Running tests

```bash
cd dead-drop/app
flutter test
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `sodium_libs` fails to load | Run `flutter pub get` and ensure platform runners exist (`flutter create .`) |
| Camera not working on desktop | `mobile_scanner` requires a camera; on Linux ensure `v4l2` is available |
| QR codes not scanning | Ensure good lighting and hold the camera steady; try increasing frame rate |
| Build fails on Linux | Install `libgtk-3-dev` and `pkg-config` |
| Build fails on Windows | Install Visual Studio Build Tools with C++ workload |

## Reproducible builds

See [reproducible-builds.md](reproducible-builds.md) for instructions on verifying that a downloaded binary matches the source code.
