# DeadDrop development environment
#
# Reproducible local dev environment: Flutter SDK + Linux desktop toolchain +
# Android SDK. No Flutter/Android installation required on the host — only Docker.
#
# Build:  docker build -f docker/Dockerfile -t deaddrop-dev .
# Or use the Makefile / docker-compose wrappers (see docs/development.md).
#
# NOTE: iOS and macOS builds are NOT possible here. They require macOS + Xcode
# (Apple license + kernel). Use CI or a Mac for those targets.

FROM ubuntu:22.04

# Pinned toolchain versions — keep in sync with .github/workflows/build.yml
ARG FLUTTER_VERSION=3.24.5
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708_latest
ARG ANDROID_PLATFORM_VERSION=34
ARG ANDROID_BUILD_TOOLS_VERSION=34.0.0

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_HOME=/opt/flutter \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    PUB_CACHE=/opt/pub-cache \
    GRADLE_USER_HOME=/opt/gradle-cache \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/build-tools/${ANDROID_BUILD_TOOLS_VERSION}:$PATH

# --- System dependencies -----------------------------------------------------
# - Linux desktop toolchain: clang, cmake, ninja, pkg-config, GTK3 headers
#   (+ lzma, cpp, stdc++ required by Flutter Linux desktop builds)
#   (+ libsecret-1-dev required by flutter_secure_storage_linux)
# - Android toolchain: JDK 17, unzip (for SDK packages)
# - Utilities: git, curl, xz, CA certs
# Single layer + full cleanup to keep image size down.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        xz-utils \
        unzip \
        openjdk-17-jdk-headless \
        clang \
        cmake \
        ninja-build \
        pkg-config \
        libgtk-3-dev \
        liblzma-dev \
        libstdc++-12-dev \
        libsecret-1-dev \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && apt-get clean

# --- Flutter SDK -------------------------------------------------------------
# Clone with --depth 1 (no .git history) and remove VCS metadata after
# precache to save ~300MB. Precache both Linux and Android artifacts here
# so the runtime user doesn't need to download them later.
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git /opt/flutter \
    && git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics \
    && flutter config --enable-linux-desktop \
    && flutter precache --linux --android \
    && flutter doctor --version \
    && rm -rf /opt/flutter/.git/objects/pack/*

# --- Android SDK -------------------------------------------------------------
# Minimal install: cmdline-tools + platform + build-tools only.
# Clean .temp and extras directories after sdkmanager to save space.
RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}.zip" -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager \
        "platform-tools" \
        "platforms;android-${ANDROID_PLATFORM_VERSION}" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
    && rm -rf "${ANDROID_SDK_ROOT}/.temp" "${ANDROID_SDK_ROOT}/extras"

# --- Non-root user -----------------------------------------------------------
# The container runs as a non-root user whose UID/GID can be matched to the
# host at runtime (see docker-compose.yml / Makefile) so that files written to
# the mounted source tree keep the host user's ownership.
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --force --gid "${USER_GID}" dev \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash dev \
    && mkdir -p "${PUB_CACHE}" "${GRADLE_USER_HOME}" \
    && chown -R dev:dev /opt/flutter "${PUB_CACHE}" "${GRADLE_USER_HOME}" "${ANDROID_SDK_ROOT}"

USER dev
WORKDIR /workspace

# Sanity check + warm the Dart tooling cache as the runtime user.
RUN flutter doctor --version

CMD ["bash"]
