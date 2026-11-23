#!/bin/sh
set -eu
exec perl "$(dirname "$0")/render-icons.pl" "$@"
