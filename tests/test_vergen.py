"""Exercise release synchronization through its shell entry point."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VersionGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="leqra version ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "project with spaces"
        self.caller = Path(self.temporary.name) / "another directory"
        self.caller.mkdir()
        files = {
            "src/main.go": 'const (\n version = "1.2.4"\n)\n',
            "src/web/index.html": '<meta name="leqra-version" content="v1.2.3">\n'
                                  '<script src="assets/v1.2.3/game.js"></script>\n'
                                  '<link href="assets/v1.2.3/style.css">\n',
            "src/web/assets/v1.2.3/game.js": "const GAME_VERSION='1.2.3';\n// Keep this game code.\n",
            "src/web/assets/v1.2.3/pwa.js": "const VERSION = 'v1.2.3';\n",
            "src/web/assets/v1.2.3/sw.js": "const VERSION = 'v1.2.3';\n",
            "src/web/assets/v1.2.3/style.css": "body{color:white}\n",
            "src/polish49_test.go": 'if version != "1.2.3" {\n}\n',
            "src/polish410_test.go": 'if version != "1.2.3" {\n}\n',
            "docs/PROTOCOL.md": '# leqra v1.2.3 — current game protocol (protocol 1)\n\n'
                                'The application-version handshake requires **1.2.3**.\n\n'
                                '```json\n{"type":"server_hello","version":"1.2.3"}\n'
                                '{"type":"client_hello","version":"1.2.3"}\n```\n\n\n'
                                'Historical v1.2.3 content stays unchanged.\n',
            "README.md": "Do not edit this v1.2.3 README.\n",
            "docs/releases/old.md": "Historical v1.2.3 release.\n",
        }
        for name, text in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        (self.root / "scripts").mkdir()
        for name in ("gen-version.sh", "vergen.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        self.icon = b"\x89PNG\r\n\x1a\n\x00unchanged icon bytes\xff"
        (self.root / "src/web/assets/v1.2.3/icon.png").write_bytes(self.icon)
        os.chmod(self.root / "src/web/assets/v1.2.3/game.js", 0o640)

    def run_script(self):
        return subprocess.run([str(self.root / "scripts/gen-version.sh")], cwd=self.caller,
                              capture_output=True, text=True)

    def snapshot(self):
        return {str(path.relative_to(self.root)): (path.read_bytes(), path.stat().st_mode)
                for path in self.root.rglob("*") if path.is_file()}

    def test_syncs_from_another_directory_and_preserves_icons_modes_and_history(self):
        untouched = {name: (self.root / name).read_bytes()
                     for name in ("README.md", "docs/releases/old.md", "src/main.go")}
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Synced leqra v1.2.4", result.stdout)
        destination = self.root / "src/web/assets/v1.2.4"
        self.assertFalse((self.root / "src/web/assets/v1.2.3").exists())
        self.assertEqual((destination / "icon.png").read_bytes(), self.icon)
        self.assertEqual((destination / "game.js").stat().st_mode & 0o777, 0o640)
        self.assertEqual((destination / "game.js").read_text(),
                         "const GAME_VERSION='1.2.4';\n// Keep this game code.\n")
        for name, data in untouched.items():
            self.assertEqual((self.root / name).read_bytes(), data)
        self.assertNotIn("1.2.3", (self.root / "src/web/index.html").read_text())
        protocol = (self.root / "docs/PROTOCOL.md").read_text()
        self.assertEqual(protocol.count("1.2.4"), 4)
        self.assertTrue(protocol.endswith("Historical v1.2.3 content stays unchanged.\n"))
        for name in ("polish49_test.go", "polish410_test.go"):
            self.assertIn('version != "1.2.4"', (self.root / "src" / name).read_text())

    def test_repeating_sync_does_not_rewrite_files(self):
        self.assertEqual(self.run_script().returncode, 0)
        before = {str(path): path.stat().st_mtime_ns for path in self.root.rglob("*")}
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Already synced", result.stdout)
        self.assertEqual(before, {str(path): path.stat().st_mtime_ns for path in self.root.rglob("*")})

    def test_existing_destination_fails_before_changing_any_file(self):
        destination = self.root / "src/web/assets/v1.2.4"
        destination.mkdir()
        (destination / "keep.txt").write_text("Do not overwrite.")
        before = self.snapshot()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to overwrite", result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_missing_final_marker_fails_before_moving_or_writing(self):
        protocol = self.root / "docs/PROTOCOL.md"
        protocol.write_text(protocol.read_text().replace('"client_hello","version":"1.2.3"',
                                                         '"client_hello","version":"missing"'))
        before = self.snapshot()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PROTOCOL.md header", result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_duplicate_asset_marker_fails_before_any_change(self):
        game = self.root / "src/web/assets/v1.2.3/game.js"
        game.write_text(game.read_text() + "const GAME_VERSION='1.2.3';\n")
        before = self.snapshot()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 2", result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_invalid_version_fails_without_changes(self):
        main = self.root / "src/main.go"
        main.write_text('const version = "../../outside"\n')
        before = self.snapshot()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("numeric X.Y.Z", result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_rerun_finishes_an_already_moved_directory(self):
        (self.root / "src/web/assets/v1.2.3").rename(self.root / "src/web/assets/v1.2.4")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("assets/v1.2.4/game.js", (self.root / "src/web/index.html").read_text())
        self.assertEqual((self.root / "src/web/assets/v1.2.4/icon.png").read_bytes(), self.icon)

    def test_repairs_stale_constants_when_html_already_uses_the_new_version(self):
        self.assertEqual(self.run_script().returncode, 0)
        pwa = self.root / "src/web/assets/v1.2.4/pwa.js"
        pwa.write_text("const VERSION = 'v1.2.3';\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(pwa.read_text(), "const VERSION = 'v1.2.4';\n")


if __name__ == "__main__":
    unittest.main()
