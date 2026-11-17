#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

./android/gradlew -p android :app:bundleRelease
realpath android/app/build/outputs/bundle/release/app-release.aab | perl -pe 's/\Q$ENV{HOME}\E/~/g'
