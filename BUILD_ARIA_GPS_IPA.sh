#!/bin/bash
# Build with the 3.2 build script in an isolated staging directory.
# Never overwrite the existing/latest IPA or publish latest-unsigned.
set -euo pipefail
cd "$(dirname "$0")"
output="$PWD/ipa/FinchMobile-3.2-ARIA-GPS.ipa"
if [ -e "$output" ]; then
  echo "Refusing to overwrite $output; move the previous candidate first." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "Xcode on macOS is required." >&2; exit 1; }
staging=$(mktemp -d "${TMPDIR:-/tmp}/finch-aria-gps.XXXXXX")
cp -R FinchMobile FinchMobile.xcodeproj BUILD_UNSIGNED_IPA.sh "$staging/"
(cd "$staging" && bash BUILD_UNSIGNED_IPA.sh)
mkdir -p ipa
cp -n "$staging/FinchMobile.ipa" "$output"
echo "New candidate: $output"
echo "Build evidence retained at: $staging"
