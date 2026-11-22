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


VERSION = r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?"
# Accept the previous unprefixed format when migrating generated markers.
GENERATED_VERSION = "v?" + VERSION[1:]


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
        raise ValueError("src/main.go must declare exactly one vX.Y.Z version, optionally with a -suffix.")
    version = versions[0]
    index = root / "src/web/index.html"
    html = index.read_text()
    versions = re.findall(r'src="assets/(' + VERSION + r')/game\.js"', html)
    if len(versions) != 1:
        raise ValueError("index.html must reference exactly one versioned game.js.")
    previous = root / "src/web/assets" / versions[0]
    destination = previous.parent / version
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

    html = re.sub(r"assets/" + VERSION + "/", "assets/" + version + "/", html)
    html = replace(html, r'(<meta\s+name="leqra-version"\s+content=")' + VERSION + r'(")',
                   lambda match: match[1] + version + match[2], 1, "src/web/index.html")
    if html != index.read_text():
        updates.append((index, html))
    for name, marker in (("game.js", "GAME_VERSION"), ("pwa.js", "VERSION"), ("sw.js", "VERSION")):
        pattern = r"(\bconst\s+" + marker + r"\s*=\s*['\"])" + GENERATED_VERSION + r"(['\"])"
        stage(source / name, pattern, lambda match: match[1] + version + match[2],
              target=destination / name)
    for name in ("polish49_test.go", "polish410_test.go"):
        stage(root / "src" / name, r'if version != "' + GENERATED_VERSION + '"', 'if version != "' + version + '"')
    protocol = root / "docs/PROTOCOL.md"
    original = protocol.read_text()
    current, separator, history = original.partition("\n# ")
    current = replace(current, r"^(# leqra )" + VERSION + r"(?= — current game protocol)",
                      lambda match: match[1] + version, 1, "docs/PROTOCOL.md title")
    for packet_type in ("server_hello", "client_hello", "join", "welcome"):
        pattern = r'^(\s*\{\s*"type"\s*:\s*"' + packet_type + r'",[^{}\n]*?"version"\s*:\s*")' + GENERATED_VERSION + r'(?=")'
        current = replace(current, pattern, lambda match: match[1] + version, 1,
                          f"docs/PROTOCOL.md current {packet_type} example")
    updated = current + separator + history
    if updated != original:
        updates.append((protocol, updated))

    # Validate every file before changing any of them or moving the bundle.
    moved = source != destination
    if moved:
        source.rename(destination)
    for path, text in updates:
        write_atomic(path, text)
    print(("Generated" if moved or updates else "Already generated") + " leqra " + version + ".")


if __name__ == "__main__":
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        synchronize(Path(__file__).resolve().parents[1])
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
