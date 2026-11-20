#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

xcode=$(xcodebuild -version)
swift=$(xcrun swift --version)
toolchain=$(printf '%s\n%s\n' "$xcode" "$swift" | shasum -a 256 | cut -d ' ' -f 1)
if [ "${GITHUB_OUTPUT-}" ]; then
	printf 'toolchain=%s\n' "$toolchain" >>"$GITHUB_OUTPUT"
else
	printf 'toolchain=%s\n' "$toolchain"
fi
