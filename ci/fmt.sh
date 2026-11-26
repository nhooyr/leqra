#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

case "${1-}" in
-h | --help)
	printf 'Usage: %s [--help | --fish-completions]\n\nFormat source files concurrently.\n' "$0"
	exit 0
	;;
--fish-completions)
	printf "complete -c fmt.sh -s h -l help -d 'Show usage'\n"
	printf "complete -c fmt.sh -l fish-completions -d 'Print Fish completions'\n"
	exit 0
	;;
esac

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install parallel shfmt swift-format ktfmt cpanminus
	npm ci --ignore-scripts

	perl_lib="$PWD/.build/perltidy-20260826-$(perl -e 'print $^V')"
	export PERL_CPANM_HOME="$PWD/.build/cpanm"
	export PERL5LIB="$perl_lib/lib/perl5"
	export PATH="$perl_lib/bin:$PATH"
	perl "$(command -v cpanm)" --notest --local-lib-contained "$perl_lib" 'Perl::Tidy@20260826'
fi

printf '%s\0' \
	prettier 'npx prettier --log-level warn -w --print-width=110 --no-semi --bracket-same-line .' \
	shfmt 'shfmt -s -w .' \
	perltidy 'git ls-files --cached --others --exclude-standard -z -- "*.pl" "*.pm" "*.t" |
		perl -0ne "chomp; print qq{./\$_\0} if -f" |
		xargs -0 -r perltidy -npro -l=110 -conv -b -bext=/' \
	swift-format 'find ios ci \( -name .build -o -name .swiftpm -o -name DerivedData \) -prune -o -type f -name "*.swift" -exec swift-format format --in-place {} +' \
	ktfmt 'find android \( -name build -o -name .gradle -o -name .kotlin \) -prune -o -type f \( -name "*.kt" -o -name "*.kts" \) -exec ktfmt --quiet --kotlinlang-style {} +' \
	gofmt 'gofmt -s -w .' |
	PARALLEL_SHELL=/bin/sh parallel --plain --null -N 2 --jobs 6 --line-buffer --tagstring '[{1}]' --halt never 'sh -ec {2} 2>&1'

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
