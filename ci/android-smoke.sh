#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

./android/gradlew --build-cache -p android :app:connectedDebugAndroidTest --rerun \
	-Pandroid.testInstrumentationRunnerArguments.class=com.leqra.android.MainActivityTest#allFiveModesRenderMoveFirePauseAndRotate,com.leqra.android.NativeChromeTest,com.leqra.android.accounts.EncryptedAccountStoreTest
