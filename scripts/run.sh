#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if ! command -v go >/dev/null 2>&1; then
  echo 'Go is required on the hosting computer. Install it from https://go.dev/doc/install' >&2
  exit 1
fi
exec go run ./src "$@"
