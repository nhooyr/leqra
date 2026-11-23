#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

npm ci --ignore-scripts

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install cpanminus
	export NODE_PATH="$PWD/node_modules"
	perl "$(command -v cpanm)" --notest --local-lib-contained "$RUNNER_TEMP/leqra-perl" --installdeps .
	export PERL5LIB="$RUNNER_TEMP/leqra-perl/lib/perl5"
	export PATH="$RUNNER_TEMP/leqra-perl/bin:$PATH"
fi

node --test src/tests/*.test.cjs
prove -Itests/lib tests/*.t
