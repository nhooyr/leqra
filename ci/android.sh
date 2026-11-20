#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

sdkmanager "platforms;android-36" "build-tools;36.0.0"
gradle --build-cache -p android :core:test --rerun :app:testDebugUnitTest --rerun :app:lintDebug \
	:app:assembleDebug :app:assembleDebugAndroidTest

if [ "${GITHUB_ACTIONS-}" ]; then
	sudo chmod a+rw /dev/kvm
fi
