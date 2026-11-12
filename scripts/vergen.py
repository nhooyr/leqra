"""Synchronize release files after editing version in src/main.go.

Run ./scripts/gen-version.sh from the repository root, then rebuild normally.
Existing icons are moved unchanged; the root README and historical docs stay put.
"""

import argparse
import os
from pathlib import Path
import re
import stat
import tempfile


VERSION = r"[0-9]+\.[0-9]+\.[0-9]+"


def replace(text, pattern, replacement, expected, path):
    updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count != expected:
        raise ValueError(f"Expected {expected} version marker(s) in {path}; found {count}.")
    return updated


def write_atomic(path, text):
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(text)
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def synchronize(root):
    main = (root / "src/main.go").read_text()
    versions = re.findall(r'^\s*version\s*=\s*"(' + VERSION + r')"', main, re.MULTILINE)
    if len(versions) != 1:
        raise ValueError("src/main.go must declare exactly one numeric X.Y.Z version.")
    version = versions[0]
    index = root / "src/web/index.html"
    html = index.read_text()
    versions = re.findall(r'src="assets/v(' + VERSION + r')/game\.js"', html)
    if len(versions) != 1:
        raise ValueError("index.html must reference exactly one versioned game.js.")
    previous = root / "src/web/assets" / ("v" + versions[0])
    destination = previous.parent / ("v" + version)
    if previous != destination and previous.exists() and destination.exists():
        raise ValueError(f"Both {previous.name} and {destination.name} exist; refusing to overwrite assets.")
    # A rerun can finish an interrupted sync whose directory already moved.
    source = previous if previous.is_dir() else destination
    if not source.is_dir():
        raise ValueError(f"The browser asset directory is missing: {previous}.")

    updates = []

    def stage(path, pattern, replacement, expected=1, target=None):
        original = path.read_text()
        updated = replace(original, pattern, replacement, expected, path.relative_to(root))
        if original != updated:
            updates.append((target or path, updated))

    html = re.sub(r"assets/v" + VERSION + "/", "assets/v" + version + "/", html)
    html = replace(html, r'(<meta name="leqra-version" content="v)' + VERSION + r'(">)',
                   lambda match: match[1] + version + match[2], 1, "src/web/index.html")
    if html != index.read_text():
        updates.append((index, html))
    for name, prefix in (("game.js", "const GAME_VERSION='"),
                         ("pwa.js", "const VERSION = 'v"), ("sw.js", "const VERSION = 'v")):
        stage(source / name, re.escape(prefix) + VERSION + "';", prefix + version + "';",
              target=destination / name)
    for name in ("polish49_test.go", "polish410_test.go"):
        stage(root / "src" / name, r'if version != "' + VERSION + '"', 'if version != "' + version + '"')
    protocol = root / "docs/PROTOCOL.md"
    lines = protocol.read_text().splitlines(keepends=True)
    header = replace("".join(lines[:10]), VERSION, version, 4, "docs/PROTOCOL.md header")
    updated = header + "".join(lines[10:])
    if updated != "".join(lines):
        updates.append((protocol, updated))

    # Validate every file before changing any of them or moving the bundle.
    moved = source != destination
    if moved:
        source.rename(destination)
    for path, text in updates:
        write_atomic(path, text)
    print(("Synced" if moved or updates else "Already synced") + " leqra v" + version + ".")


if __name__ == "__main__":
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        synchronize(Path(__file__).resolve().parents[1])
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
