#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install shfmt swift-format ktfmt
	npm ci --ignore-scripts
fi

npx prettier -w --print-width=110 --no-semi --bracket-same-line .
shfmt -s -w .
find ios \( -name .build -o -name .swiftpm -o -name DerivedData \) -prune -o -type f -name '*.swift' -exec swift-format format --in-place {} +
find android \( -name build -o -name .gradle -o -name .kotlin \) -prune -o -type f \( -name '*.kt' -o -name '*.kts' \) -exec ktfmt --kotlinlang-style {} +
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
