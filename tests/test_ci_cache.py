"""Check that build-cache reuse never hides changed source inputs."""

import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ios_cache", ROOT / "ci/ios-cache.py")
ios_cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ios_cache)


class IOSCacheTests(unittest.TestCase):
    def test_only_identical_existing_build_inputs_regain_their_cached_timestamp(self):
        with tempfile.TemporaryDirectory(prefix="leqra cache ") as directory:
            root = Path(directory)
            files = ["ios/same.swift", "ios/changed.swift", "ios/deleted.swift",
                     "scripts/version.sh", "src/main.go", "unrelated.swift"]
            original = 1_600_000_000_000_000_000
            newer = original + 5_000_000_000
            for name in files:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("original")
                os.utime(path, ns=(original, original))
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            manifest = root / "cache.json"
            ios_cache.save(root, manifest)

            for name in files:
                os.utime(root / name, ns=(newer, newer))
            (root / "ios/changed.swift").write_text("modified")
            os.utime(root / "ios/changed.swift", ns=(newer, newer))
            (root / "ios/deleted.swift").unlink()
            new = root / "ios/new.swift"
            new.write_text("new")
            os.utime(new, ns=(newer, newer))
            outside = root / "ios/link.swift"
            outside.symlink_to(root / "unrelated.swift")

            ios_cache.restore(root, manifest)
            for name in ["ios/same.swift", "scripts/version.sh", "src/main.go"]:
                self.assertEqual((root / name).stat().st_mtime_ns, original)
            for name in ["ios/changed.swift", "ios/new.swift", "unrelated.swift"]:
                self.assertEqual((root / name).stat().st_mtime_ns, newer)
            self.assertEqual((root / "ios/changed.swift").read_text(), "modified")
            self.assertFalse((root / "ios/deleted.swift").exists())

    def test_a_cold_cache_leaves_source_timestamps_alone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.swift"
            source.write_text("source")
            before = source.stat().st_mtime_ns
            ios_cache.restore(root, root / "missing.json")
            self.assertEqual(source.stat().st_mtime_ns, before)


class IOSSimulatorTests(unittest.TestCase):
    def test_newest_available_runtime_uses_its_version_instead_of_parsing_its_identifier(self):
        script = (ROOT / "ci/ios.sh").read_text().split("python3 - <<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        old = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        new = "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19"
        standard = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
        unavailable = "com.apple.CoreSimulator.SimRuntime.iOS-28-0"
        inventory = {
            "runtimes": [
                {"identifier": old, "version": "26.5", "isAvailable": True},
                {"identifier": new, "version": "27.2", "isAvailable": True},
                {"identifier": standard, "version": "27.2", "isAvailable": True},
                {"identifier": unavailable, "version": "28.0", "isAvailable": False},
            ],
            "devices": {
                old: [{"name": "iPhone old", "udid": "old", "state": "Booted", "isAvailable": True}],
                new: [{"name": "iPhone new", "udid": "new", "state": "Shutdown", "isAvailable": True}],
                standard: [{"name": "iPhone standard", "udid": "standard", "state": "Shutdown", "isAvailable": True}],
            },
        }
        for state in ["Shutdown", "Booted"]:
            inventory["devices"][standard][0]["state"] = state
            with mock.patch("subprocess.check_output", return_value=json.dumps(inventory).encode()), \
                    mock.patch("subprocess.run") as boot, redirect_stdout(io.StringIO()) as output:
                exec(compile(script, "ci/ios.sh simulator selection", "exec"), {})
            self.assertEqual(output.getvalue(), "standard\n")
            if state == "Shutdown":
                boot.assert_called_once_with(["xcrun", "simctl", "boot", "standard"], check=True)
            else:
                boot.assert_not_called()


class AndroidSDKTests(unittest.TestCase):
    def test_installed_sdk_is_reused_and_missing_packages_are_installed(self):
        for missing in [None, "platform", "build-tools"]:
            with self.subTest(missing=missing), tempfile.TemporaryDirectory(prefix="leqra sdk ") as directory:
                root = Path(directory)
                (root / "ci").mkdir()
                shutil.copy2(ROOT / "ci/android.sh", root / "ci/android.sh")
                sdk = root / "sdk"
                trace = root / "commands.jsonl"
                recorder = (f"#!{sys.executable}\nimport json, os, sys\n"
                            "with open(os.environ['TRACE'], 'a') as f: "
                            "f.write(json.dumps(sys.argv) + '\\n')\n")
                for name in ["android/gradlew", "sdk/cmdline-tools/latest/bin/sdkmanager"]:
                    path = root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(recorder)
                    path.chmod(0o755)
                if missing != "platform":
                    platform = sdk / "platforms/android-36/android.jar"
                    platform.parent.mkdir(parents=True)
                    platform.touch()
                if missing != "build-tools":
                    tool = sdk / "build-tools/36.0.0/aapt2"
                    tool.parent.mkdir(parents=True)
                    tool.touch()
                    tool.chmod(0o755)
                env = {**os.environ, "ANDROID_HOME": str(sdk), "TRACE": str(trace)}
                env.pop("GITHUB_ACTIONS", None)
                subprocess.run(["sh", str(root / "ci/android.sh")], env=env, check=True)
                commands = [json.loads(line) for line in trace.read_text().splitlines()]
                self.assertEqual(len(commands), 1 if missing is None else 2)
                self.assertEqual(Path(commands[-1][0]).name, "gradlew")
                for task in [":core:test", ":app:testDebugUnitTest", ":app:lintDebug",
                             ":app:assembleDebug", ":app:assembleDebugAndroidTest"]:
                    self.assertIn(task, commands[-1])
                if missing:
                    self.assertEqual(commands[0][1:], ["platforms;android-36", "build-tools;36.0.0"])


if __name__ == "__main__":
    unittest.main()
