"""Exercise dev.sh with a fake build, readiness probe, and browser opener."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class DevTests(unittest.TestCase):
    def test_browser_uses_the_configured_listen_address(self):
        for system, settings, expected in (
            ("Darwin", {}, "http://test.local:8080"),
            ("Darwin", {"PORT": "8099"}, "http://test.local:8099"),
            ("Darwin", {"PORT": "8099", "ADDR": "[::1]:9020"}, "http://[::1]:9020"),
            ("Darwin", {"ADDR": ":0"}, None),
            ("Linux", {}, None),
        ):
            with self.subTest(system=system, settings=settings), tempfile.TemporaryDirectory() as scratch:
                root = Path(scratch)
                project = root / "project with spaces"
                project.mkdir()
                script = project / "dev.sh"
                shutil.copy2(Path(__file__).resolve().parents[1] / script.name, script)
                commands = root / "commands"
                commands.mkdir()
                log = root / "log"
                stubs = {
                    "go": """mkdir -p bin
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" >> "$TEST_LOG"' > bin/leqra
chmod +x bin/leqra""",
                    "uname": f"echo {system}",
                    "hostname": "echo test.local",
                    "curl": 'printf "probe %s\\n" "$4" >> "$TEST_LOG"',
                    "open": 'printf "open %s\\n" "$3" >> "$TEST_LOG"',
                }
                for name, contents in stubs.items():
                    command = commands / name
                    command.write_text("#!/bin/sh\n" + contents + "\n")
                    command.chmod(0o755)
                env = {key: value for key, value in os.environ.items() if key not in ("ADDR", "PORT")}
                env.update(PATH=str(commands) + os.pathsep + os.defpath, TEST_LOG=str(log), **settings)
                result = subprocess.run(["/bin/sh", str(script)], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                lines = log.read_text().splitlines()
                self.assertEqual(lines[0], "-check-assets")
                self.assertEqual(sorted(line for line in lines[1:] if line),
                                 sorted([f"probe {expected}", f"open {expected}"] if expected else []))


if __name__ == "__main__":
    unittest.main()
