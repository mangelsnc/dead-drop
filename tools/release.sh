#!/usr/bin/env bash
# release.sh — Create a tagged release for DeadDrop
#
# Usage:
#   ./tools/release.sh <version>
#
# Example:
#   ./tools/release.sh 0.2.0
#
# This script:
#   1. Validates semver format
#   2. Updates pubspec.yaml version
#   3. Creates a git tag
#   4. Pushes the tag (triggers CI release build)
#
# Requires: git, sed

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.2.0"
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"

# Validate semver
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
  echo "Error: '${VERSION}' is not a valid semver version"
  exit 1
fi

# Check we're on main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "Error: must be on main branch (currently on ${BRANCH})"
  exit 1
fi

# Check working tree is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean"
  exit 1
fi

# Check tag doesn't exist
if git rev-parse "$TAG" &>/dev/null; then
  echo "Error: tag ${TAG} already exists"
  exit 1
fi

echo "Releasing DeadDrop ${TAG}..."

# Update pubspec.yaml
PUBSPEC="app/pubspec.yaml"
CURRENT=$(grep '^version:' "$PUBSPEC" | awk '{print $2}')
echo "Updating pubspec.yaml: ${CURRENT} → ${VERSION}+1"
sed -i "s/^version: .*/version: ${VERSION}+1/" "$PUBSPEC"

# Commit version bump
git add "$PUBSPEC"
git commit -m "chore: bump version to ${VERSION}"

# Create annotated tag
git tag -a "$TAG" -m "DeadDrop ${TAG}"

echo ""
echo "Ready to push. Run:"
echo "  git push origin main ${TAG}"
echo ""
echo "This will trigger the CI release workflow, which will:"
echo "  1. Build for Linux, Windows, macOS"
echo "  2. Compute SHA-256 checksums"
echo "  3. Create a GitHub Release with artifacts attached"
