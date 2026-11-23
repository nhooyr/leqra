#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

npm ci --ignore-scripts

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install shfmt cpanminus
	export NODE_PATH="$PWD/node_modules"
	perl "$(command -v cpanm)" --notest --local-lib-contained "$RUNNER_TEMP/leqra-perl" --installdeps .
	export PERL5LIB="$RUNNER_TEMP/leqra-perl/lib/perl5"
	export PATH="$RUNNER_TEMP/leqra-perl/bin:$PATH"
fi

go vet ./...
git ls-files --cached --others --exclude-standard -z -- '*.js' '*.cjs' | xargs -0 -n1 sh -c 'test ! -f "$1" || node --check "./$1"' sh
shfmt -f=0 . | xargs -0 -n1 sh -n

git ls-files --cached --others --exclude-standard -z -- '*.pl' '*.pm' '*.t' |
	xargs -0 -n1 sh -c 'test ! -f "$1" || perl -Isrc/tests/lib -Itests/lib -c "./$1"' sh
