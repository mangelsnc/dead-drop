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

# The Flutter version every environment must agree on. Single source of truth
# is .fvmrc; this reads it so the Makefile, the Docker image tag and CI cannot
# drift apart.
FLUTTER_VERSION := $(shell sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)

# Apple targets cannot run in Docker (Xcode needs macOS), so they use the
# host toolchain — the one place where a contributor's own Flutter version
# leaks into a build. Prefer FVM when it is installed so everyone compiles
# with $(FLUTTER_VERSION); fall back to PATH otherwise, with a warning.
HOST_FLUTTER := $(shell command -v fvm >/dev/null 2>&1 && echo "fvm flutter" || echo "flutter")

.PHONY: help image build-linux build-android build-ios build-macos test analyze clean shell doctor

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

image: ## Build the Docker development image
	docker build --platform $(PLATFORM) -f $(DOCKERFILE) -t $(IMAGE) \
		--build-arg USER_UID=$(UID) --build-arg USER_GID=$(GID) .

build-linux: ## Compile the Linux desktop app (release)
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter build linux --release"
	@echo "✔ Output: $(APP_DIR)/build/linux/x64/release/bundle/"

build-android: ## Compile the Android APK (release)
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter build apk --release"
	@echo "✔ Output: $(APP_DIR)/build/app/outputs/flutter-apk/app-release.apk"

build-ios: ## iOS build — runs on HOST, not in Docker (requires macOS + Xcode + Flutter)
	@echo "⚠️  iOS builds cannot run in Docker (Apple requires macOS + Xcode)."
	@echo "   This will run on your Mac using your local Flutter installation."
	@echo "   Make sure you have Flutter SDK installed and in your PATH."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) --no-print-directory _check-host-flutter
	cd $(APP_DIR) && $(HOST_FLUTTER) pub get && $(HOST_FLUTTER) build ios --release
	@echo "✔ Output: $(APP_DIR)/build/ios/iphoneos/Runner.app"

build-macos: ## macOS build — runs on HOST, not in Docker (requires macOS + Flutter)
	@echo "⚠️  macOS builds cannot run in Docker (Apple requires macOS + Xcode)."
	@echo "   This will run on your Mac using your local Flutter installation."
	@echo "   Make sure you have Flutter SDK installed and in your PATH."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) --no-print-directory _check-host-flutter
	cd $(APP_DIR) && $(HOST_FLUTTER) pub get && $(HOST_FLUTTER) build macos --release
	@echo "✔ Output: $(APP_DIR)/build/macos/Build/Products/Release/dead_drop.app"

test: ## Run the test suite
	$(DOCKER_RUN) $(IMAGE) bash -c "\
		cd $(APP_DIR) && \
		flutter pub get && \
		flutter test"

analyze: ## Run static analysis (flutter analyze)
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
		echo "✖ No Flutter found on PATH. Install FVM (brew install leoafarias/fvm/fvm)"; \
		echo "  then run: fvm install $(FLUTTER_VERSION) && fvm use $(FLUTTER_VERSION)"; \
		exit 1; \
	elif [ "$$actual" != "$(FLUTTER_VERSION)" ]; then \
		echo "✖ Flutter $$actual found, but this project pins $(FLUTTER_VERSION) (.fvmrc)."; \
		echo "  Building with another version produces errors that look like code bugs."; \
		echo "  Fix: brew install leoafarias/fvm/fvm && fvm install $(FLUTTER_VERSION) && fvm use $(FLUTTER_VERSION)"; \
		exit 1; \
	else \
		echo "✔ Flutter $$actual matches .fvmrc"; \
	fi

clean: ## Remove build artifacts (host-side, no container needed)
	rm -rf $(APP_DIR)/build
	rm -rf $(APP_DIR)/.dart_tool
	@echo "✔ Cleaned $(APP_DIR)/build and $(APP_DIR)/.dart_tool"

shell: ## Open an interactive shell inside the dev container
	$(DOCKER_RUN) $(TTY) $(IMAGE) bash

doctor: ## Run flutter doctor inside the container (diagnostics)
	$(DOCKER_RUN) $(IMAGE) flutter doctor -v
