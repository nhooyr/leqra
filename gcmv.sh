#!/bin/sh
set -eu

version=$(awk -F'"' '/version *=/ {print $2; exit}' src/main.go)

git add -A
git commit -em "v$version"
git push
