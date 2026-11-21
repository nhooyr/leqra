"""Keep the Android wrapper usable from a fresh checkout."""

from pathlib import Path
import subprocess
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = Path("android/gradle/wrapper/gradle-wrapper.jar")


class AndroidWrapperTests(unittest.TestCase):
    def test_wrapper_jar_contains_its_launcher(self):
        self.assertTrue((ROOT / WRAPPER).is_file(), "The Gradle wrapper JAR must ship with the launcher")
        with zipfile.ZipFile(ROOT / WRAPPER) as archive:
            self.assertIn("org/gradle/wrapper/GradleWrapperMain.class", archive.namelist())
            self.assertIn(
                "Main-Class: org.gradle.wrapper.GradleWrapperMain",
                archive.read("META-INF/MANIFEST.MF").decode(),
            )
            self.assertIsNone(archive.testzip())

    def test_wrapper_jar_is_not_ignored(self):
        result = subprocess.run(
            ["git", "check-ignore", "--no-index", "--quiet", str(WRAPPER)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 1, "The Gradle wrapper JAR must be included in Git")


if __name__ == "__main__":
    unittest.main()
