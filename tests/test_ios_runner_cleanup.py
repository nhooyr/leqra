"""Check Xcode runner cleanup without contacting a simulator or device."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/cleanup-ios-test-runner.sh"
RUNNER = "com.leqra.ios.uitests.xctrunner"


class RunnerCleanupTests(unittest.TestCase):
    def run_cleanup(self, platform, device="selected destination", status=0):
        with tempfile.TemporaryDirectory(prefix="leqra runner cleanup ") as directory:
            path = Path(directory)
            command = path / "xcrun"
            command.write_text(f"#!{sys.executable}\n" +
                               "import json, os, sys\n"
                               "print(json.dumps(sys.argv[1:]), file=sys.stderr)\n"
                               "sys.exit(int(os.environ['MOCK_EXIT']))\n")
            command.chmod(0o755)
            env = {**os.environ, "PATH": str(path) + os.pathsep + os.environ["PATH"],
                   "TARGET_DEVICE_IDENTIFIER": device, "TARGET_DEVICE_PLATFORM_NAME": platform,
                   "MOCK_EXIT": str(status)}
            result = subprocess.run([str(SCRIPT)], cwd=path, env=env, capture_output=True, text=True)
            commands = [json.loads(line) for line in result.stderr.splitlines() if line.startswith("[")]
            return result, commands

    def test_simulator_cleanup_targets_only_the_selected_device_and_runner(self):
        for platform in ("iphonesimulator", "com.apple.platform.iphonesimulator", "iOS Simulator"):
            result, commands = self.run_cleanup(platform)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(commands, [["simctl", "uninstall", "selected destination", RUNNER]])

    def test_physical_cleanup_is_bounded_and_never_uninstalls_the_game(self):
        for platform in ("iphoneos", "com.apple.platform.iphoneos", "iOS"):
            result, commands = self.run_cleanup(platform)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(commands, [["devicectl", "device", "uninstall", "app", "--device",
                                         "selected destination", RUNNER, "--timeout", "15", "--quiet"]])
            self.assertNotIn("com.leqra.ios", commands[0])

    def test_missing_generic_and_unsupported_destinations_are_untouched(self):
        for platform, device in (("iphoneos", ""), ("iphoneos", "dvtdevice-placeholder"),
                                 ("iphonesimulator", "AnySimulatorPlaceholder"), ("macosx", "host"),
                                 ("", "unknown")):
            result, commands = self.run_cleanup(platform, device)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(commands, [])

    def test_unavailable_device_does_not_mask_test_results_and_reports_retry(self):
        for platform in ("iphoneos", "iphonesimulator"):
            result, commands = self.run_cleanup(platform, status=17)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(len(commands), 1)
            self.assertIn("warning:", result.stderr)
            self.assertIn("retry before Run", result.stderr)

    def test_shared_scheme_cleans_after_testing_and_before_normal_run(self):
        scheme = ET.parse(ROOT / "ios/leqra.xcodeproj/xcshareddata/xcschemes/leqra.xcscheme")
        for action in ("TestAction/PostActions", "LaunchAction/PreActions"):
            content = scheme.find(action + "/ExecutionAction/ActionContent")
            self.assertIsNotNone(content, action)
            self.assertEqual(content.attrib["scriptText"].strip(),
                             '"${SRCROOT}/../scripts/cleanup-ios-test-runner.sh"')
            target = content.find("EnvironmentBuildable/BuildableReference")
            self.assertEqual(target.attrib["BlueprintName"], "leqraUITests")
        testable = scheme.find("TestAction/Testables/TestableReference")
        self.assertEqual(testable.attrib["skipped"], "NO", "Xcode must still install the test runner as needed")


if __name__ == "__main__":
    unittest.main()
