#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

ci_tmpdir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

python3 ci/ios-cache.py restore "$ci_tmpdir/leqra-ios-inputs.json"

simulator=$(
	python3 - <<'PY'
import json
import subprocess

inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "--json"]))
devices = inventory["devices"]
runtimes = [runtime for runtime in inventory["runtimes"]
            if ".iOS-" in runtime["identifier"] and runtime["isAvailable"]]
standard = [runtime for runtime in runtimes
            if runtime["identifier"].endswith(".iOS-" + runtime["version"].replace(".", "-"))]
runtimes = sorted(
    standard or runtimes,
    key=lambda runtime: tuple(map(int, runtime["version"].split("."))),
    reverse=True,
)
device = next(
    device
    for runtime in runtimes
    for device in devices.get(runtime["identifier"], [])
    if device["name"].startswith("iPhone") and device["isAvailable"]
)
if device["state"] == "Shutdown":
    subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True)
print(device["udid"])
PY
)

swift test --package-path ios --configuration release --disable-index-store \
	--build-system native --scratch-path "$ci_tmpdir/leqra-swift"

xcrun simctl bootstatus "$simulator" -b

xcodebuild -project ios/leqra.xcodeproj -scheme leqra \
	-configuration Debug -destination "id=$simulator" \
	-derivedDataPath "$ci_tmpdir/leqra-ios" \
	-resultBundlePath "$ci_tmpdir/leqra-ios-tests.xcresult" \
	-parallel-testing-enabled NO \
	-only-testing:leqraUITests/GameUITests/testUnchangedOfflineCallsignResumeKeepsItsBattleWithoutAnAccountKey \
	-only-testing:leqraUITests/GameUITests/testDeathNoticeMatchesTankLabelsInPortraitAndLandscape \
	-only-testing:leqraUITests/GameUITests/testFireDragAimsInPlaceInBothLayouts \
	COMPILER_INDEX_STORE_ENABLE=NO COMPILATION_CACHE_ENABLE_CACHING=YES \
	COMPILATION_CACHE_CAS_PATH="$ci_tmpdir/leqra-ios/CompilationCache.noindex" \
	CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test

python3 ci/ios-cache.py save "$ci_tmpdir/leqra-ios-inputs.json"
