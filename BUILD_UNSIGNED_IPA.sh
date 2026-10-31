#!/bin/bash
# Generates the Xcode project from project.yml (XcodeGen) and builds an unsigned IPA.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build Payload ARIA.ipa build.log
xcodegen generate
set +e
xcodebuild -project ARIA.xcodeproj -target ARIA -configuration Release -sdk iphoneos \
  SYMROOT="$(pwd)/build" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" ONLY_ACTIVE_ARCH=NO \
  SWIFT_STRICT_CONCURRENCY=minimal build 2>&1 | tee build.log
STATUS=${PIPESTATUS[0]}
set -e
if [ "$STATUS" -ne 0 ]; then
  echo "===== BUILD ERRORS ====="
  grep -E "error:|fatal error:" build.log | head -60 || true
  exit "$STATUS"
fi
APP=$(find build -name 'ARIA.app' -type d | head -1)
test -n "$APP"
mkdir Payload && cp -R "$APP" Payload/ && zip -qr ARIA.ipa Payload && rm -rf Payload
ls -lh ARIA.ipa
