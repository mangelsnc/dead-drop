# Development Environment

DeadDrop ships a **Dockerized development environment** so you can build, test, and
run static analysis without installing Flutter or the Android SDK on your machine.
The only host requirement is **Docker**.

> If you prefer a native setup, see [build.md](build.md) instead.

---

## 1. Prerequisites

| Requirement | Notes |
|---|---|
| Docker | Any recent version ([install](https://docs.docker.com/get-docker/)) |
| `make` | Preinstalled on Linux/macOS; on Windows use WSL2 |
| `docker compose` | Optional — only if you prefer compose over the Makefile |

No Flutter SDK, no Android SDK, no Java on the host.

---

## 2. Quick start

```bash
git clone https://github.com/mangelsnc/dead-drop.git
cd dead-drop

# Build the dev image (first time only, ~10-15 min; cached afterwards)
make image

# Compile the Linux desktop app
make build-linux
```

The binary lands in `app/build/linux/x64/release/bundle/dead_drop`.

---

## 3. Makefile targets

| Target | What it does |
|---|---|
| `make image` | Build the Docker dev image (Flutter 3.24.5 + Android SDK + Linux toolchain) |
| `make build-linux` | Compile the Linux desktop app (release) |
| `make build-android` | Compile the Android APK (release) |
| `make build-ios` | **Not available in Docker** — see [§5](#5-ios--macos-limitation) |
| `make test` | Run the Flutter test suite |
| `make analyze` | Run `flutter analyze` (static analysis) |
| `make clean` | Delete `app/build/` and `app/.dart_tool/` |
| `make shell` | Interactive bash shell inside the container |
| `make doctor` | Run `flutter doctor -v` inside the container (diagnostics) |
| `make help` | List all targets |

All targets that need the image depend on `make image`, so they build it
automatically on first run (and rebuild it whenever `docker/Dockerfile` changes).

---

## Flutter version

The project pins **Flutter 3.24.5** in `.fvmrc`. Every environment must use
it: the Docker image builds it in, CI installs it, and the Makefile reads the
version from that file so the three cannot drift.

Linux, Windows and Android builds run in Docker, so they get the right
version automatically. **iOS and macOS cannot** — Xcode requires macOS, so
those targets use whatever Flutter is on your machine. That is the one place
a mismatch can creep in, and it does not fail cleanly: building with a newer
Flutter produces errors that look like bugs in our code (for example
`CardTheme` vs `CardThemeData`, whose signature changed after 3.24).

Use [FVM](https://fvm.app/) so your toolchain matches the project:

```bash
brew install leoafarias/fvm/fvm
cd dead-drop
fvm install     # reads .fvmrc
fvm use         # activates 3.24.5 for this project
```

`make build-ios` and `make build-macos` then pick up `fvm` automatically and
refuse to start if the active version does not match `.fvmrc`.

Without FVM they fall back to the `flutter` on your `PATH`, and the same
check still runs — so a mismatch is reported in seconds instead of after a
five-minute Xcode build.

### Upgrading

Not a one-line change. `sodium_libs` is pinned to `2.2.1+6` because newer
releases need a Dart SDK that Flutter 3.24.5 does not ship, so moving Flutter
forward means migrating the cryptography layer (now two majors behind and
discontinued upstream) along with several other majors. Treat it as its own
piece of work with its own branch and review — see the tracking issue.

---

## 4. How it works

### The image (`docker/Dockerfile`)

A single Ubuntu 22.04 image with everything pinned:

- **Flutter SDK 3.24.5** (the version in `.fvmrc` — see
  [Flutter version](#flutter-version) below)
- **Linux desktop toolchain**: `clang`, `cmake`, `ninja-build`, `pkg-config`,
  `libgtk-3-dev` (+ `liblzma-dev`, `libstdc++-12-dev`)
- **Android SDK**: command-line tools, platform 34, build-tools 34.0.0, JDK 17

The container runs as a **non-root user** whose UID/GID are matched to your host
user at image-build time (`--build-arg USER_UID/GID`), so files written to the
mounted source tree (`build/`, `.dart_tool/`, `pubspec.lock`) are owned by you,
not root.

### Volumes

- The **repository root** is bind-mounted at `/workspace` (the container's
  working directory), so edits on the host are instantly visible inside the
  container.
- A named volume (`deaddrop-pub-cache`) caches pub packages between runs so
  `flutter pub get` is fast after the first time.

### docker-compose (optional)

`docker-compose.yml` wraps the same image for users who prefer compose:

```bash
docker compose build dev
docker compose run --rm dev bash
```

It also exposes port **5000** for an optional Flutter web/hot-reload dev server
(`flutter run -d web-server --web-port 5000`).

---

## 5. iOS / macOS limitation

**iOS and macOS builds cannot run inside this Linux Docker container.** This is
a hard Apple restriction, not a tooling gap:

- Xcode and the iOS/macOS SDKs are licensed for Apple hardware only.
- Compilation requires the macOS kernel and frameworks.

`make build-ios` therefore prints an explanation and exits with an error.
To build for iOS/macOS:

1. **On a Mac** — install Flutter and run `cd app && flutter build ios --release`
   (see [build.md](build.md)).
2. **In CI** — the `build-macos` job in `.github/workflows/build.yml` already
   builds the macOS app on every push to `main`.

---

## 6. Common workflows

```bash
# Day-to-day: edit code on the host, then re-run tests/analysis
make test
make analyze

# Interactive work inside the container (e.g. flutter pub add, adb, etc.)
make shell
# inside the container:
cd app
flutter pub get
flutter test

# Produce release artifacts
make build-linux
make build-android

# Clean slate
make clean
```

---

## 7. Troubleshooting

| Problem | Solution |
|---|---|
| `docker: command not found` | Install Docker (see §1). |
| Permission denied on `app/build/` files | Rebuild the image so UID/GID match: `make image` (the Makefile passes your `id -u`/`id -g`). |
| `make image` fails downloading Flutter/Android | Check network/proxy; re-run — the build is resumable via Docker layer cache. |
| Linux build fails with GTK errors | The image already includes `libgtk-3-dev`; run `make doctor` and open an issue with the output. |
| Want a different Flutter version | Edit `FLUTTER_VERSION` in `docker/Dockerfile` **and** `.github/workflows/build.yml`, then `make image`. |
| Windows host | Use WSL2; run `make` inside the WSL2 distro with Docker Desktop integration enabled. |

---

## 8. Relationship to CI

The Docker image mirrors the CI environment (same Flutter version, same Linux
packages). If `make build-linux` / `make test` / `make analyze` pass locally,
the `build-linux` job in GitHub Actions should pass too. For reproducible
release builds and checksum verification, see
[reproducible-builds.md](reproducible-builds.md).
