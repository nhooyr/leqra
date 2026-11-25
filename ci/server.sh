#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

go build -trimpath -o bin/leqra ./src
./bin/leqra -check-assets
go test -race -count=1 ./...
