# DeadDrop — development environment Makefile
#
# Every target runs inside the Docker dev image (docker/Dockerfile), so the
# only host requirement is Docker. No Flutter or Android SDK on the host.
#
# Quick start:
#   make image         # build the dev image (first time only, ~10-15 min)
#   make build-linux   # compile the Linux desktop app
#   make shell         # interactive shell inside the container
#
# See docs/development.md for the full guide.

SHELL := /bin/bash

IMAGE        := deaddrop-dev:3.24.5
DOCKERFILE   := docker/Dockerfile
APP_DIR      := app
PLATFORM     := linux/amd64

# Match the container user to the host user so files written to the bind
# mount (build/, .dart_tool/, pubspec.lock) keep host ownership.
UID := $(shell id -u)
GID := $(shell id -g)

# Named volumes for caches: persist between runs, never baked into the image.
PUB_CACHE_VOL    := deaddrop-pub-cache
GRADLE_CACHE_VOL := deaddrop-gradle-cache

# Base docker run command: bind-mount the repo and reuse named volumes for
# the pub and Gradle caches so builds stay fast between runs.
# --platform is forced on every invocation (Apple Silicon Macs need it).
DOCKER_RUN := docker run --rm --platform $(PLATFORM) \
	--user $(UID):$(GID) \
	-v "$(CURDIR):/workspace" \
	-v $(PUB_CACHE_VOL):/opt/pub-cache \
	-v $(GRADLE_CACHE_VOL):/opt/gradle-cache \
	-w /workspace

# Add -it only when attached to a terminal (so `make shell` is interactive
# but CI / scripted targets are not).
TTY := $(shell test -t 0 && echo "-it")

# Release signing keystore, when one is configured.
#
# app/android/key.properties holds an absolute host path, because the keystore
# is deliberately kept OUTSIDE this public repository — a leaked signing key
# cannot be revoked. The Android build runs in the container, which only
# mounts the repo, so that path has to be bind-mounted in at the same location
# or Gradle fails with "Keystore file ... not found for signing config".
KEY_PROPERTIES := $(APP_DIR)/android/key.properties
KEYSTORE_PATH  := $(shell sed -n 's/^storeFile=//p' $(KEY_PROPERTIES) 2>/dev/null)
KEYSTORE_MOUNT := $(if $(wildcard $(KEYSTORE_PATH)),-v "$(KEYSTORE_PATH):$(KEYSTORE_PATH):ro",)

# Stamp file tracking the built image. Every containerised target depends on
# it, so a Dockerfile change (a new apt package, a toolchain bump) rebuilds the
# image automatically instead of failing deep inside the build with a message
# that doesn't mention Docker at all — a stale image missing libsecret-1-dev
# surfaces only as a CMake pkg_check_modules error.
#
# The stamp is also refreshed when the image is missing from the daemon (someone
# ran `docker rmi`, or cloned fresh), and is deliberately kept out of the repo
# (.gitignore) since it describes local Docker state, not the source tree.
STAMP := .make/image-$(subst :,-,$(IMAGE))

# The Flutter version every environment must agree on. Single source of truth
# is .fvmrc; this reads it so the Makefile, the Docker image tag and CI cannot
# drift apart.
FLUTTER_VERSION := $(shell sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)

# Apple targets cannot run in Docker (Xcode needs macOS), so they use the
# host toolchain — the one place where a contributor's own Flutter version
# leaks into a build. Prefer FVM when it is installed so everyone compiles
# with $(FLUTTER_VERSION); fall back to PATH otherwise, with a warning.
HOST_FLUTTER := $(shell command -v fvm >/dev/null 2>&1 && echo "fvm flutter" || echo "flutter")

.PHONY: help image image-force _check-host-flutter build-linux build-android build-ios build-macos test test-timing analyze clean shell doctor

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

image: ## Build the Docker development image (only if out of date)
	@$(MAKE) --no-print-directory $(STAMP)

image-force: ## Rebuild the Docker development image unconditionally
	@rm -f $(STAMP)
	@$(MAKE) --no-print-directory $(STAMP)

# Rebuild when the Dockerfile is newer than the stamp, or the image is gone.
$(STAMP): $(DOCKERFILE)
	@mkdir -p $(dir $@)
	@echo "⟳ Dev image out of date — rebuilding (first run takes ~10-15 min)…"
	docker build --platform $(PLATFORM) -f $(DOCKERFILE) -t $(IMAGE) \
		--build-arg USER_UID=$(UID) --build-arg USER_GID=$(GID) .
	@touch $@
	@echo "✔ Image $(IMAGE) up to date"

# Drop the stamp if the tag no longer exists in the daemon, so the rule above
# fires. Runs on every make invocation; a bare `docker image inspect` is ~0.1s.
$(shell docker image inspect $(IMAGE) >/dev/null 2>&1 || rm -f $(STAMP) 2>/dev/null)

build-linux: $(STAMP) ## Compile the Linux desktop app (release)
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter build linux --release"
	@echo "✔ Output: $(APP_DIR)/build/linux/x64/release/bundle/"

build-android: $(STAMP) ## Compile the Android APK (release)
	@if [ -f $(KEY_PROPERTIES) ] && [ -z "$(KEYSTORE_MOUNT)" ]; then \
		echo "✖ $(KEY_PROPERTIES) points at a keystore that does not exist:"; \
		echo "    $(KEYSTORE_PATH)"; \
		echo "  Fix the storeFile path, or remove key.properties to build with debug keys."; \
		exit 1; \
	fi
	$(DOCKER_RUN) $(KEYSTORE_MOUNT) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter build apk --release"
	@echo "✔ Output: $(APP_DIR)/build/app/outputs/flutter-apk/app-release.apk"

build-ios: ## iOS build — runs on HOST, not in Docker (requires macOS + Xcode + Flutter)
	@echo "⚠️  iOS builds cannot run in Docker (Apple requires macOS + Xcode)."
	@echo "   It runs on your Mac with the Flutter version pinned in .fvmrc,"
	@echo "   via FVM when installed (brew install fvm). See docs/development.md."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) --no-print-directory _check-host-flutter
	cd $(APP_DIR) && $(HOST_FLUTTER) pub get && $(HOST_FLUTTER) build ios --release
	@echo "✔ Output: $(APP_DIR)/build/ios/iphoneos/Runner.app"

build-macos: ## macOS build — runs on HOST, not in Docker (requires macOS + Flutter)
	@echo "⚠️  macOS builds cannot run in Docker (Apple requires macOS + Xcode)."
	@echo "   It runs on your Mac with the Flutter version pinned in .fvmrc,"
	@echo "   via FVM when installed (brew install fvm). See docs/development.md."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) --no-print-directory _check-host-flutter
	cd $(APP_DIR) && $(HOST_FLUTTER) pub get && $(HOST_FLUTTER) build macos --release
	@echo "✔ Output: $(APP_DIR)/build/macos/Build/Products/Release/dead_drop.app"

test: $(STAMP) ## Run the test suite (excludes wall-clock timing tests)
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter test --exclude-tags timing"

test-timing: $(STAMP) ## Run the wall-clock timing tests (serial; needs a quiet, non-emulated machine)
	@echo "Note: on an Apple Silicon host this runs under x86_64 emulation,"
	@echo "where the measurement is dominated by emulator jitter. CI's Linux"
	@echo "job runs it natively — see app/dart_test.yaml."
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter test --tags timing --concurrency 1"

analyze: $(STAMP) ## Run static analysis (flutter analyze)
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter analyze"

# Guard for the Apple targets: catches a host Flutter that does not match
# .fvmrc before spending five minutes in Xcode only to fail on an API that
# moved between releases (e.g. CardTheme -> CardThemeData after 3.24).
_check-host-flutter:
	@actual=$$($(HOST_FLUTTER) --version 2>/dev/null | sed -n '1s/Flutter \([0-9.]*\).*/\1/p'); \
	if [ -z "$$actual" ]; then \
		echo "✖ No Flutter found on PATH. Install FVM (brew install fvm)"; \
		echo "  then run: fvm install $(FLUTTER_VERSION) && fvm use $(FLUTTER_VERSION)"; \
		exit 1; \
	elif [ "$$actual" != "$(FLUTTER_VERSION)" ]; then \
		echo "✖ Flutter $$actual found, but this project pins $(FLUTTER_VERSION) (.fvmrc)."; \
		echo "  Building with another version produces errors that look like code bugs."; \
		echo "  Fix: brew install fvm && fvm install $(FLUTTER_VERSION) && fvm use $(FLUTTER_VERSION)"; \
		exit 1; \
	else \
		echo "✔ Flutter $$actual matches .fvmrc"; \
	fi

clean: ## Remove build artifacts (host-side, no container needed)
	rm -rf $(APP_DIR)/build
	rm -rf $(APP_DIR)/.dart_tool
	@echo "✔ Cleaned $(APP_DIR)/build and $(APP_DIR)/.dart_tool"

shell: $(STAMP) ## Open an interactive shell inside the dev container
	$(DOCKER_RUN) $(TTY) $(IMAGE) bash

doctor: $(STAMP) ## Run flutter doctor inside the container (diagnostics)
	$(DOCKER_RUN) $(IMAGE) flutter doctor -v
