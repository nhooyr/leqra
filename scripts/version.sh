#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

awk -F'"' '/version *=/ {print $2; exit}' src/main.go
