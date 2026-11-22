#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

android_sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [ -n "$android_sdk" ]; then
	PATH="$android_sdk/cmdline-tools/latest/bin:$PATH"
	export PATH
fi
if [ ! -f "$android_sdk/platforms/android-36/android.jar" ] || [ ! -x "$android_sdk/build-tools/36.0.0/aapt2" ]; then
	sdkmanager "platforms;android-36" "build-tools;36.0.0"
fi
./android/gradlew --build-cache -p android :core:test --rerun :app:testDebugUnitTest --rerun :app:lintDebug \
	:app:assembleDebug :app:assembleDebugAndroidTest

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo chmod a+rw /dev/kvm
fi
