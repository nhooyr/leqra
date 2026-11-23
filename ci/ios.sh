#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

ci_tmpdir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

swift -module-cache-path .build/swift-module-cache ci/ios-cache.swift restore "$ci_tmpdir/leqra-ios-inputs.json"

simulator=$(perl ci/ios-simulator.pl)

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

swift -module-cache-path .build/swift-module-cache ci/ios-cache.swift save "$ci_tmpdir/leqra-ios-inputs.json"
