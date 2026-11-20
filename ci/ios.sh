#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

ci_tmpdir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

swift test --package-path ios --configuration release \
	--build-system native --scratch-path "$ci_tmpdir/leqra-swift"

simulator=$(
	python3 - <<'PY'
import json
import subprocess

devices = json.loads(subprocess.check_output([
    "xcrun", "simctl", "list", "devices", "available", "--json",
]))["devices"]
print(next(
    device["udid"]
    for runtime, entries in devices.items()
    if ".iOS-" in runtime
    for device in entries
    if device["name"].startswith("iPhone") and device["isAvailable"]
))
PY
)

xcodebuild -project ios/leqra.xcodeproj -scheme leqra \
	-configuration Debug -destination "id=$simulator" \
	-derivedDataPath "$ci_tmpdir/leqra-ios" \
	-resultBundlePath "$ci_tmpdir/leqra-ios-tests.xcresult" \
	-parallel-testing-enabled NO \
	-only-testing:leqraUITests/GameUITests/testUnchangedOfflineCallsignResumeKeepsItsBattleWithoutAnAccountKey \
	-only-testing:leqraUITests/GameUITests/testDeathNoticeMatchesTankLabelsInPortraitAndLandscape \
	CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
