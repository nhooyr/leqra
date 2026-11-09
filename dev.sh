#!/bin/sh
set -eu

go build  -o ./bin/leqra ./src && ./bin/leqra
