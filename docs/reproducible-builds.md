# Reproducible Builds

DeadDrop publishes **SHA-256 checksums** for every release artifact. Anyone can verify that the binary they downloaded matches the one built by CI, and — more importantly — that the binary corresponds exactly to the public source code.

This document explains how to verify a release and how to reproduce the build locally.

---

## 1. Verify a downloaded release

Every release includes a `SHA256SUMS.txt` file with the hash of each artifact.

### Linux / macOS

```bash
# Download the artifact and SHA256SUMS.txt from the release page
sha256sum -c SHA256SUMS.txt --ignore-missing
```

### Windows (PowerShell)

```powershell
# Get the hash of your downloaded file
Get-FileHash .\deaddrop-windows-x64.zip -Algorithm SHA256

# Compare with the value in SHA256SUMS.txt
```

If the hash matches, the file is intact and authentic.

---

## 2. Reproduce the build locally

### Prerequisites

| Tool | Version | How to install |
|------|---------|----------------|
| Flutter SDK | See `.github/workflows/build.yml` → `FLUTTER_VERSION` | https://docs.flutter.dev/get-started/install |
| Git | Any recent | — |

The exact Flutter version is pinned in the CI workflow. Using the same version is **required** for bit-for-bit reproducibility.

### Steps

```bash
# 1. Clone the exact release tag
git clone --depth 1 --branch v0.1.0 https://github.com/mangelsnc/dead-drop.git
cd dead-drop/app

# 2. Install dependencies (uses pubspec.lock for exact versions)
flutter pub get --enforce-lockfile

# 3. Build for your platform
flutter build linux --release
# or: flutter build windows --release
# or: flutter build macos --release

# 4. Compute the hash
sha256sum build/linux/x64/release/bundle/dead_drop
# Compare with the CI artifact hash
```

### What affects reproducibility

- **Flutter SDK version**: Must match exactly. Check `FLUTTER_VERSION` in the CI workflow.
- **pubspec.lock**: Ensures identical dependency versions. Never delete it.
- **Build flags**: CI uses `--release` with default flags. Custom flags may change the binary.
- **Absolute build path**: Flutter embeds the filesystem path into `lib/libapp.so` via `dart_plugin_registrant.dart`. To reproduce the CI hash, build in `/home/runner/work/dead-drop/dead-drop` (or use a container/symlink). See `docs/reproducibility-verification.md` section 2 for the full analysis.
- **Packaging**: `tar` and `gzip` embed timestamps by default. The CI uses deterministic flags (`--sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner --format=gnu` + `gzip -n9`) so the `.tar.gz` hash is also reproducible.

---

## 3. CI verification

Every push to `main` and every tag triggers the build workflow. The workflow:

1. Builds for Linux, Windows, and macOS in parallel.
2. Computes SHA-256 of each artifact.
3. Uploads artifacts + `SHA256SUMS.txt` as GitHub Actions artifacts.
4. On tags, creates a GitHub Release with the artifacts attached.

You can inspect any build at: https://github.com/mangelsnc/dead-drop/actions

---

## 4. Why this matters

Reproducible builds are a core security property: they prove that the binary you run was built from the source code you can read. Without them, you are trusting that the release binary was not tampered with. With them, you can verify it yourself.

This is an explicit evaluation criterion of the #cryptograFREE challenge.
