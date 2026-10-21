# Reproducibility Verification

This document records the experimental verification that DeadDrop's Linux build is **bit-for-bit reproducible**, the root cause of non-reproducibility across different machines, and the pipeline changes that enforce reproducibility going forward.

This is the evidence cited in the #cryptograFREE submission under "build verifiability".

---

## 1. What we verified

Two builds of the same commit, compiled in the **same absolute path** with the **same toolchain**, produce an identical SHA-256 hash of the `dead_drop` binary.

| Property | Value |
|----------|-------|
| Commit | `e3d64dc` (tip of `main` at time of verification) |
| Flutter SDK | `3.24.5` (pinned in `.github/workflows/build.yml`) |
| Dart SDK | `3.5.4` (bundled with Flutter 3.24.5) |
| Host OS | Debian 12 (sandbox), Ubuntu 22.04 (CI) |
| Build command | `flutter build linux --release` |

### Hashes

The full hashes are recorded in the CI job output (`reproducibility-check`) on every push. The experiment below was run locally:

| Build | Path | `sha256(dead_drop)` |
|-------|------|---------------------|
| #1 | `/tmp/dd-repro` | `4fd6ffb1157d19db352bbbb82f2b41d6a03f76b4f7612c60580c633e5309eda8` |
| #2 (after `flutter clean`) | `/tmp/dd-repro` | `4fd6ffb1157d19db352bbbb82f2b41d6a03f76b4f7612c60580c633e5309eda8` |

| Artifact | `sha256` |
|----------|----------|
| `dead_drop` (binary) | `4fd6ffb1157d19db352bbbb82f2b41d6a03f76b4f7612c60580c633e5309eda8` |
| `lib/libapp.so` | `83db55176cf4ddd2860af1c1e11614a9604903c468272bdb405be80ff5c16b23` |
| `deaddrop-linux-x64.tar.gz` (deterministic) | `e4178f9219586f9a0dbbdb6913436d9ac4706c18a674e6eddf1dc035b3cd179f` |

> **Note**: The exact hash changes with every commit. What is invariant is the **property**: same commit + same toolchain + same path → same hash. The CI `reproducibility-check` job re-verifies this property on every push, so the evidence is always current.

---

## 2. Root cause of cross-machine non-reproducibility

The Flutter Linux build embeds the **absolute build path** into `lib/libapp.so` via the generated file:

```
.dart_tool/flutter_build/dart_plugin_registrant.dart
```

This file is referenced by a `file:///` URI that includes the full filesystem path. Because CI builds in `/home/runner/work/dead-drop/dead-drop` and a local clone builds wherever the user put it, the resulting `libapp.so` differs between machines even when the source code and toolchain are identical.

**Implication**: to reproduce the CI hash locally, you must build in the same absolute path. The simplest way is a container or a symlink:

```bash
# Option A: build in the CI path via a container
docker run --rm -v $(pwd):/home/runner/work/dead-drop/dead-drop \
  -w /home/runner/work/dead-drop/dead-drop \
  ghcr.io/mangelsnc/dead-drop-builder:latest \
  bash -c "cd app && flutter pub get && flutter build linux --release"

# Option B: symlink your clone into the CI path
sudo mkdir -p /home/runner/work/dead-drop
sudo ln -s $(pwd) /home/runner/work/dead-drop/dead-drop
cd /home/runner/work/dead-drop/dead-drop/app
flutter pub get && flutter build linux --release
```

---

## 3. The packaging layer was also non-deterministic

The original CI pipeline packaged the bundle with:

```bash
tar czf deaddrop-linux-x64.tar.gz .
```

Both `tar` and `gzip` embed non-deterministic metadata:

- `tar`: file ordering (filesystem-dependent), UID/GID of the build user, modification timestamps.
- `gzip`: the original filename and a timestamp in the header.

This means two builds of the *same* binary produced *different* `.tar.gz` hashes, making the published SHA-256 useless for verification.

### Fix

The pipeline now uses deterministic packaging:

```bash
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner --format=gnu -cf - . | gzip -n9 > deaddrop-linux-x64.tar.gz
```

| Flag | Effect |
|------|--------|
| `--sort=name` | Deterministic file ordering |
| `--mtime='@0'` | All timestamps set to epoch |
| `--owner=0 --group=0 --numeric-owner` | No UID/GID leakage |
| `--format=gnu` | Consistent tar format |
| `gzip -n` | No filename or timestamp in gzip header |

This was verified experimentally: two independent builds packaged with these flags produced the identical hash `e4178f9219586f9a0dbbdb6913436d9ac4706c18a674e6eddf1dc035b3cd179f`.

---

## 4. CI enforcement

The `reproducibility-check` job in `.github/workflows/build.yml` runs on every push and pull request:

1. Builds the Linux release binary (pass 1).
2. Records the SHA-256.
3. Runs `flutter clean`, re-fetches dependencies, rebuilds (pass 2).
4. Records the SHA-256 again.
5. **Fails the build** if the two hashes differ.

This catches any future change that introduces non-determinism (embedded timestamps, hash-map iteration order, new absolute paths) before it reaches a release.

The `release` job depends on `reproducibility-check`, so a non-reproducible build cannot be published.

---

## 5. How to verify a release yourself

```bash
# 1. Download the release artifact and its hash
#    (from https://github.com/mangelsnc/dead-drop/releases)

# 2. Verify the tarball hash
sha256sum -c deaddrop-linux-x64.tar.gz.sha256

# 3. Extract and verify the binary hash
tar xzf deaddrop-linux-x64.tar.gz
sha256sum -c deaddrop-linux-x64.binary.sha256

# 4. (Optional) Reproduce the build from source
git clone --depth 1 --branch v0.1.0 https://github.com/mangelsnc/dead-drop.git
cd dead-drop/app
flutter pub get --enforce-lockfile
flutter build linux --release
sha256sum build/linux/x64/release/bundle/dead_drop
# Compare with deaddrop-linux-x64.binary.sha256
```

---

## 6. What this does NOT cover

- **Cross-machine reproducibility without path matching**: building in a different absolute path produces a different binary. This is a known Flutter limitation, not a DeadDrop bug. The workaround is documented in section 2.
- **Windows and macOS**: the same deterministic packaging approach should work, but has not been verified experimentally. The `reproducibility-check` job currently covers Linux only.
- **Android APK**: not yet verified. Gradle builds embed timestamps and signing keys by default; reproducible APK builds require additional configuration (`--no-daemon`, deterministic ZIP ordering, etc.).

---

## 7. Environment notes

The verification was performed in a Debian 12 sandbox with:

- Flutter 3.24.5 (exact pin from CI)
- clang 14.0, cmake 3.25.1, ninja 1.11.1
- libgtk-3-dev 3.24.38, libsecret-1-dev 0.20.5
- 32-core x86_64, local disk (NFS volumes cause the Dart frontend_server to hang in D-state — use local disk for builds)
