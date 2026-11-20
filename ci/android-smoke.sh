#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

gradle --build-cache -p android :app:connectedDebugAndroidTest --rerun \
	-Pandroid.testInstrumentationRunnerArguments.class=com.leqra.android.MainActivityTest#allFiveModesRenderMoveFirePauseAndRotate,com.leqra.android.NativeChromeTest,com.leqra.android.accounts.EncryptedAccountStoreTest
