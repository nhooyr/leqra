#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "${GITHUB_ACTIONS-}" ]; then
	brew install shfmt
fi

go vet ./...
git ls-files --cached --others --exclude-standard -z -- '*.js' '*.cjs' | xargs -0 -n1 sh -c 'test ! -f "$1" || node --check "./$1"' sh
shfmt -f=0 . | xargs -0 -n1 sh -n

python3 - <<'PY'
import ast
from pathlib import Path
import subprocess
import tokenize

files = subprocess.check_output([
    "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.py",
])
for name in files.decode().split("\0"):
    if name and Path(name).is_file():
        with tokenize.open(name) as source:
            ast.parse(source.read(), filename=name)
PY
