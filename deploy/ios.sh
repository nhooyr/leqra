#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
	printf 'Usage: %s <iphone-name>\n' >&2 "${0##*/}"
	exit 1
fi

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodebuild \
  -project ios/leqra.xcodeproj \
  -scheme leqra \
  -configuration Release \
  -destination "platform=iOS,name=$1" \
  -derivedDataPath /tmp/leqra-ios-device \
  -allowProvisioningUpdates \
  build &&
xcrun devicectl device install app \
  --device "$1" \
  /tmp/leqra-ios-device/Build/Products/Release-iphoneos/leqra.app &&
xcrun devicectl device process launch \
  --device "$1" \
  --terminate-existing \
  com.leqra
