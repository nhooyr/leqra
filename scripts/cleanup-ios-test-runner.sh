#!/bin/sh
# Xcode supplies the selected destination to scheme execution actions.
# Remove only the test host; leqra and its saved data are separate bundles.
set -eu

device=${TARGET_DEVICE_IDENTIFIER:-}
platform=${TARGET_DEVICE_PLATFORM_NAME:-${PLATFORM_NAME:-}}
runner=com.leqra.ios.uitests.xctrunner

case "$device" in
    ''|*placeholder*|*Placeholder*) exit 0 ;;
esac

case "$platform" in
    iphonesimulator|com.apple.platform.iphonesimulator|'iOS Simulator')
        if xcrun simctl uninstall "$device" "$runner" >/dev/null; then exit 0; fi
        ;;
    iphoneos|com.apple.platform.iphoneos|iOS)
        if xcrun devicectl device uninstall app --device "$device" "$runner" --timeout 15 --quiet; then exit 0; fi
        ;;
    *) exit 0 ;;
esac

# A disconnected device must not turn a successful build/test into a failure.
# The Run pre-action retries cleanup when the destination is available again.
echo 'warning: Could not remove the leqra UI test runner; cleanup will retry before Run.' >&2
exit 0
