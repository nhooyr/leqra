#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

npm ci --ignore-scripts

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install shfmt cpanminus
fi

perl_lib="$PWD/.build/perl-$(perl -e 'print $^V')"
export NODE_PATH="$PWD/node_modules"
export PERL_CPANM_HOME="$PWD/.build/cpanm"
export PERL5LIB="$perl_lib/lib/perl5"
export PATH="$perl_lib/bin:$PATH"
perl "$(command -v cpanm)" --notest --local-lib-contained "$perl_lib" --installdeps .

go vet ./...
git ls-files --cached --others --exclude-standard -z -- '*.js' '*.cjs' | xargs -0 -n1 sh -c 'test ! -f "$1" || node --check "./$1"' sh
shfmt -f=0 . | xargs -0 -n1 sh -n
swiftc -module-cache-path .build/swift-module-cache -typecheck ci/ios-cache.swift

git ls-files --cached --others --exclude-standard -z -- '*.pl' '*.pm' '*.t' |
	xargs -0 -n1 sh -c 'test ! -f "$1" || perl -Isrc/tests/lib -Itests/lib -c "./$1"' sh
