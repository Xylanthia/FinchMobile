#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build Payload FinchMobile.ipa
xcodebuild \
  -project FinchMobile.xcodeproj \
  -scheme FinchMobile \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  build
APP=$(find build/Build/Products -name 'FinchMobile.app' -type d | head -1)
test -n "$APP"
mkdir Payload
cp -R "$APP" Payload/
zip -qr FinchMobile.ipa Payload
rm -rf Payload
echo ""
echo "DONE: $(pwd)/FinchMobile.ipa"
ls -lh FinchMobile.ipa
