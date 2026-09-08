#!/bin/sh
set -eu

rsync --exclude .git --exclude-from=.gitignore --exclude pull-chatgpt.sh --exclude deploy --exclude deploy.sh \
	-avzP --delete "$1/" "$(dirname "$0")/"
