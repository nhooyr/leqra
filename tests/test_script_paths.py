"""Check shell entry points without invoking renderers or controlling Chrome."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GENERATORS = {
    "gen-icons.sh": ("python3", "render-icons.py"),
    "gen-showcase.sh": ("node", "render-showcase.cjs"),
    "gen-version.sh": ("python3", "vergen.py"),
}


class ScriptPathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="leqra script paths ")
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name)
        self.project = self.parent / "project with spaces"
        self.scripts = self.project / "scripts"
        self.scripts.mkdir(parents=True)
        self.caller = self.parent / "unrelated working directory"
        self.caller.mkdir()
        (self.project / "src").mkdir()
        (self.project / "src/main.go").write_text('const (\n version = "1.2.3"\n)\n')
        for path in (ROOT / "scripts").iterdir():
            if path.is_file():
                shutil.copy2(path, self.scripts / path.name)
        self.commands = self.parent / "mock commands"
        self.commands.mkdir()
        for name in ("python3", "node", "osascript"):
            command = self.commands / name
            command.write_text(f"#!{sys.executable}\n" +
                               "import json, os, sys\n"
                               "print(json.dumps({'command':os.path.basename(sys.argv[0]), 'args':sys.argv[1:], 'cwd':os.getcwd(), 'stdin':sys.stdin.read()}))\n"
                               "print('mock stderr', file=sys.stderr)\n"
                               "sys.exit(int(os.environ.get('MOCK_EXIT', '0')))\n")
            command.chmod(0o755)

    def invocation(self, name, form):
        script = self.scripts / name
        env = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"]}
        if form == "absolute":
            command = str(script)
        elif form == "relative":
            command = os.path.relpath(script, self.caller)
        else:
            entry = str(self.scripts) if form == "path" else os.path.relpath(self.scripts, self.caller)
            env["PATH"] = entry + os.pathsep + env["PATH"]
            command = name
        return command, env

    def test_generators_find_their_implementation_and_preserve_caller_arguments_and_status(self):
        arguments = ["output folder/file.html", "", 'quoted "value"', "two\nlines"]
        for name, (interpreter, implementation) in GENERATORS.items():
            for form in ("absolute", "relative", "path", "relative_path"):
                for status in (0, 37):
                    with self.subTest(script=name, invocation=form, exit=status):
                        command, env = self.invocation(name, form)
                        env["MOCK_EXIT"] = str(status)
                        result = subprocess.run([command, *arguments], cwd=self.caller, env=env,
                                                input="", capture_output=True, text=True)
                        self.assertEqual(result.returncode, status, result.stderr)
                        recorded = json.loads(result.stdout)
                        self.assertEqual(recorded["command"], interpreter)
                        resolved = (self.caller / recorded["args"][0]).resolve()
                        self.assertEqual(resolved, (self.scripts / implementation).resolve())
                        self.assertEqual(recorded["args"][1:], arguments)
                        self.assertEqual(Path(recorded["cwd"]).resolve(), self.caller.resolve())
                        self.assertEqual(result.stderr, "mock stderr\n")

    def test_fit_helper_preserves_its_applescript_and_caller_directory(self):
        for form in ("absolute", "relative", "path", "relative_path"):
            with self.subTest(invocation=form):
                command, env = self.invocation("fit-showcase.sh", form)
                env["MOCK_EXIT"] = "37"
                result = subprocess.run([command], cwd=self.caller, env=env, input="",
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 37, result.stderr)
                recorded = json.loads(result.stdout)
                self.assertEqual(recorded["args"], [])
                self.assertEqual(Path(recorded["cwd"]).resolve(), self.caller.resolve())
                self.assertIn('tell application "Google Chrome"', recorded["stdin"])
                self.assertIn("set bounds of showcaseWindow to fittedBounds", recorded["stdin"])
                self.assertIn("screen.availLeft", recorded["stdin"])

    def test_version_query_works_from_an_unrelated_directory_and_path(self):
        for form in ("absolute", "relative", "path", "relative_path"):
            with self.subTest(invocation=form):
                command, env = self.invocation("version.sh", form)
                result = subprocess.run([command], cwd=self.caller, env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "1.2.3\n")
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
