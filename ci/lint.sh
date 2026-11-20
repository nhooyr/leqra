#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

go vet ./...
git ls-files --cached --others --exclude-standard -z -- '*.js' '*.cjs' | xargs -0 -n1 sh -c 'test ! -f "$1" || node --check "./$1"' sh
git ls-files --cached --others --exclude-standard -z -- '*.sh' android/gradlew | xargs -0 -n1 sh -c 'test ! -f "$1" || sh -n "./$1"' sh

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
