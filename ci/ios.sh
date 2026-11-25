#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

ci_tmpdir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
simulator_file=$(mktemp "$ci_tmpdir/leqra-ios-simulator.XXXXXX")
simulator_pid=

cleanup() {
	status=$?
	trap - 0
	trap '' HUP INT TERM
	if [ -n "$simulator_pid" ]; then
		kill -TERM "$simulator_pid" 2>/dev/null || :
		wait "$simulator_pid" 2>/dev/null || :
	fi
	rm -f "$simulator_file"
	exit "$status"
}
trap cleanup 0
signal_status=0
trap 'signal_status=129' HUP
trap 'signal_status=130' INT
trap 'signal_status=143' TERM

perl ci/ios-simulator.pl >"$simulator_file" &
simulator_pid=$!

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
[ "$signal_status" -eq 0 ] || exit "$signal_status"

swift -module-cache-path .build/swift-module-cache ci/ios-cache.swift restore "$ci_tmpdir/leqra-ios-inputs.json"

swift test --package-path ios --configuration debug --disable-index-store \
	--build-system native --scratch-path "$ci_tmpdir/leqra-swift"

set -- -project ios/leqra.xcodeproj -scheme leqra -configuration Debug \
	-derivedDataPath "$ci_tmpdir/leqra-ios" \
	COMPILER_INDEX_STORE_ENABLE=NO COMPILATION_CACHE_ENABLE_CACHING=YES \
	COMPILATION_CACHE_CAS_PATH="$ci_tmpdir/leqra-ios/CompilationCache.noindex" \
	CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

xcodebuild "$@" -destination 'generic/platform=iOS Simulator' \
	"ARCHS=$(uname -m)" ONLY_ACTIVE_ARCH=YES build-for-testing

wait "$simulator_pid"
simulator_pid=
simulator=$(cat "$simulator_file")

xcodebuild "$@" -destination "id=$simulator" \
	-resultBundlePath "$ci_tmpdir/leqra-ios-tests.xcresult" \
	-parallel-testing-enabled NO \
	-only-testing:leqraUITests/GameUITests/testUnchangedOfflineCallsignResumeKeepsItsBattleWithoutAnAccountKey \
	-only-testing:leqraUITests/GameUITests/testDeathNoticeMatchesTankLabelsInPortraitAndLandscape \
	-only-testing:leqraUITests/GameUITests/testFireDragAimsInPlaceInBothLayouts \
	test-without-building

swift -module-cache-path .build/swift-module-cache ci/ios-cache.swift save "$ci_tmpdir/leqra-ios-inputs.json"
