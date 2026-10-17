#!/usr/bin/env bash
# verify-build.sh — Verify a local DeadDrop build against CI SHA-256 hashes
#
# Usage:
#   ./tools/verify-build.sh <platform> <path-to-local-binary>
#
# Example:
#   ./tools/verify-build.sh linux build/linux/x64/release/bundle/dead_drop
#
# Requires: curl, sha256sum (or shasum on macOS)

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <platform> <path-to-binary>"
  echo "Platforms: linux, windows, macos"
  exit 1
fi

PLATFORM="$1"
BINARY="$2"
REPO="mangelsnc/dead-drop"

# Detect sha256 tool
if command -v sha256sum &>/dev/null; then
  SHA_CMD="sha256sum"
elif command -v shasum &>/dev/null; then
  SHA_CMD="shasum -a 256"
else
  echo "Error: sha256sum or shasum required"
  exit 1
fi

# Get the latest release tag
echo "Fetching latest release..."
TAG=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$TAG" ]; then
  echo "Error: could not determine latest release tag"
  exit 1
fi

echo "Latest release: ${TAG}"

# Download SHA256SUMS.txt
SUMS_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS.txt"
echo "Downloading checksums from ${SUMS_URL}..."
SUMS=$(curl -sL "$SUMS_URL")

if [ -z "$SUMS" ]; then
  echo "Error: could not download SHA256SUMS.txt"
  exit 1
fi

# Compute local hash
LOCAL_HASH=$($SHA_CMD "$BINARY" | awk '{print $1}')
echo "Local binary SHA-256: ${LOCAL_HASH}"

# Find expected hash for this platform
EXPECTED=$(echo "$SUMS" | grep "${PLATFORM}" | awk '{print $1}')

if [ -z "$EXPECTED" ]; then
  echo "Error: no hash found for platform '${PLATFORM}' in SHA256SUMS.txt"
  echo "Available entries:"
  echo "$SUMS"
  exit 1
fi

echo "Expected SHA-256:     ${EXPECTED}"

if [ "$LOCAL_HASH" = "$EXPECTED" ]; then
  echo ""
  echo "✅ MATCH — Your local build is identical to the CI build."
  echo "   This proves the binary corresponds to the public source code."
else
  echo ""
  echo "❌ MISMATCH — Your local build differs from the CI build."
  echo "   Possible causes:"
  echo "   - Different Flutter SDK version (check .github/workflows/build.yml)"
  echo "   - Modified source code"
  echo "   - Different build flags"
  echo "   See docs/reproducible-builds.md for troubleshooting."
  exit 1
fi
