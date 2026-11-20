#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

npm ci --ignore-scripts
node --test src/tests/*.test.cjs
python3 -m unittest discover -s tests -v
