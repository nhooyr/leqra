#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

status=0
./android/gradlew --build-cache -p android :app:connectedDebugAndroidTest --rerun \
	-Pandroid.testInstrumentationRunnerArguments.class=com.leqra.android.MainActivityTest#launchWakesSleepingDevice,com.leqra.android.MainActivityTest#allFiveModesRenderMoveFirePauseAndRotate,com.leqra.android.MainActivityTest#fireDragAimsInPlaceInBothLayouts,com.leqra.android.NativeChromeTest,com.leqra.android.accounts.EncryptedAccountStoreTest ||
	status=$?

if [ "$status" -ne 0 ]; then
	report=android/app/build/reports/emulator
	mkdir -p "$report"
	adb shell dumpsys window >"$report/windows.txt" 2>&1 || true
	adb logcat -d >"$report/logcat.txt" 2>&1 || true
	adb exec-out screencap -p >"$report/screen.png" 2>/dev/null || true
fi
exit "$status"
