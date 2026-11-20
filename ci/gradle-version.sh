#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# The wrapper JAR is not tracked; install its declared Gradle release.
version=$(sed -nE 's@^distributionUrl=.*gradle-(.+)-(bin|all)\.zip$@\1@p' android/gradle/wrapper/gradle-wrapper.properties)
test -n "$version"
if [ "${GITHUB_OUTPUT-}" ]; then
	printf 'version=%s\n' "$version" >>"$GITHUB_OUTPUT"
else
	printf 'version=%s\n' "$version"
fi
