"""Keep unchanged source timestamps aligned with restored Swift build records."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def inputs(root):
    names = subprocess.check_output([
        "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--",
        "ios", "scripts/ios-version.sh", "scripts/version.sh", "src/main.go",
    ], cwd=root).decode().split("\0")
    for name in sorted(set(names) - {""}):
        path = root / name
        if path.is_file() and not path.is_symlink():
            yield name, path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(root, manifest):
    records = {
        name: {"sha256": digest(path), "mtime_ns": path.stat().st_mtime_ns}
        for name, path in inputs(root)
    }
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(records, sort_keys=True) + "\n")


def restore(root, manifest):
    if not manifest.exists():
        return
    records = json.loads(manifest.read_text())
    restored = 0
    for name, path in inputs(root):
        record = records.get(name)
        if record and record["sha256"] == digest(path):
            stat = path.stat()
            os.utime(path, ns=(stat.st_atime_ns, record["mtime_ns"]))
            restored += 1
    print(f"Restored timestamps for {restored} unchanged iOS build inputs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("restore", "save"))
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    {"restore": restore, "save": save}[args.action](root, args.manifest)
