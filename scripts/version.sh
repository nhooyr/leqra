#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

exec awk -F'"' '/version *=/ {print $2; exit}' src/main.go
