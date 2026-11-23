#!/bin/sh
set -eu
exec perl "$(dirname "$0")/vergen.pl" "$@"
