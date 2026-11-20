#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

go build -trimpath -o bin/leqra ./src
go test -race -count=1 ./...
