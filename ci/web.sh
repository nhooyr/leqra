#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

npm ci --ignore-scripts

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install parallel cpanminus
fi

perl_lib="$PWD/.build/perl-$(perl -e 'print $^V')"
export NODE_PATH="$PWD/node_modules"
export PERL_CPANM_HOME="$PWD/.build/cpanm"
export PERL5LIB="$perl_lib/lib/perl5"
export PATH="$perl_lib/bin:$PATH"
perl "$(command -v cpanm)" --notest --local-lib-contained "$perl_lib" --installdeps .

node --test src/tests/*.test.cjs
prove -Itests/lib tests/*.t
