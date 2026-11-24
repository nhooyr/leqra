#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install shfmt swift-format ktfmt cpanminus
	npm ci --ignore-scripts

	perl_lib="$PWD/.build/perltidy-20260826-$(perl -e 'print $^V')"
	export PERL_CPANM_HOME="$PWD/.build/cpanm"
	export PERL5LIB="$perl_lib/lib/perl5"
	export PATH="$perl_lib/bin:$PATH"
	perl "$(command -v cpanm)" --notest --local-lib-contained "$perl_lib" 'Perl::Tidy@20260826'
fi

npx prettier --log-level warn -w --print-width=110 --no-semi --bracket-same-line .
shfmt -s -w .
git ls-files --cached --others --exclude-standard -z -- '*.pl' '*.pm' '*.t' |
	xargs -0 -n1 sh -c 'test ! -f "$1" || perltidy -npro -l=110 -conv -b -bext=/ "./$1"' sh
find ios ci \( -name .build -o -name .swiftpm -o -name DerivedData \) -prune -o -type f -name '*.swift' -exec swift-format format --in-place {} +
find android \( -name build -o -name .gradle -o -name .kotlin \) -prune -o -type f \( -name '*.kt' -o -name '*.kts' \) -exec ktfmt --quiet --kotlinlang-style {} +
gofmt -s -w .

if [ "${CI-}" ]; then
	git add --intent-to-add --ignore-removal .

	tput() { command tput -Txterm-256color "$@"; }

	if ! git --no-pager diff --color=always --stat --patch --exit-code; then
		tput bold
		printf '%s %s: unexpected diff\n' "$(printf '%40s' '' | tr ' ' '^')" "${0##*/}"
		tput sgr0
		exit 1
	fi
fi
