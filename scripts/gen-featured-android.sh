#!/bin/sh
set -eu
exec go run "$(dirname "$0")/featured-graphic/main.go" \
	-input "$(dirname "$0")/../docs/showcase.png" \
	-output "$(dirname "$0")/../docs/showcase-featured-android.png" "$@"
