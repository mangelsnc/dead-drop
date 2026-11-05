#!/usr/bin/env bash
# Print the --dart-define arguments every `flutter build` needs, derived
# from pubspec.yaml so the version in the binary cannot drift from the
# version in the repository.
#
# Usage:  flutter build apk --release $(tool/build_args.sh)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pubspec="${here}/../pubspec.yaml"

# `version: 0.9.1+162` -> version 0.9.1, build number 162.
line="$(grep -m1 '^version:' "$pubspec" | awk '{print $2}')"
version="${line%%+*}"
build="${line##*+}"
[ "$build" = "$line" ] && build=''

commit="$(git -C "$here" rev-parse --short HEAD 2>/dev/null || true)"

# Fail rather than emit nothing. A silently empty result would produce a
# release binary whose About screen reads "Development build", and that
# is not something anyone notices until the binary is in a user's hands.
if [ -z "$version" ]; then
  echo "build_args.sh: no version found in ${pubspec}" >&2
  exit 1
fi

args="--dart-define=DEADDROP_VERSION=${version}"
[ -n "$build" ] && args="${args} --dart-define=DEADDROP_BUILD_NUMBER=${build}"
[ -n "$commit" ] && args="${args} --dart-define=DEADDROP_COMMIT=${commit}"
echo "$args"
