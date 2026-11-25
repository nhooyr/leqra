#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

ci_tmpdir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}

swift -module-cache-path .build/swift-module-cache ci/ios-cache.swift restore "$ci_tmpdir/leqra-macos-inputs.json"

swift test --package-path ios --configuration release --disable-index-store \
	--build-system native --scratch-path "$ci_tmpdir/leqra-macos-swift"

# Compile UI regression tests without launching the app. The ad-hoc test runner
# needs library validation disabled to load its bundle when run manually.
xcodebuild -project ios/leqra.xcodeproj -scheme leqra \
	-configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' \
	-derivedDataPath "$ci_tmpdir/leqra-macos" \
	-resultBundlePath "$ci_tmpdir/leqra-macos-tests.xcresult" \
	-parallel-testing-enabled NO \
	COMPILER_INDEX_STORE_ENABLE=NO COMPILATION_CACHE_ENABLE_CACHING=YES \
	COMPILATION_CACHE_CAS_PATH="$ci_tmpdir/leqra-macos/CompilationCache.noindex" \
	CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO build-for-testing

swift -module-cache-path .build/swift-module-cache ci/ios-cache.swift save "$ci_tmpdir/leqra-macos-inputs.json"
