"""Exercise deployment with mock builds and remote commands; never contact a host."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

STUB = r'''import json
import os
from pathlib import Path
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["DEPLOY_TEST_LOG"], "a") as log:
    log.write(json.dumps({"command": name, "args": args, "cwd": os.getcwd(),
                          "goos": os.environ.get("GOOS"),
                          "goarch": os.environ.get("GOARCH")}) + "\n")
if name == "go":
    if os.environ.get("DEPLOY_TEST_GO_FAIL") == "1":
        sys.exit(7)
    assert args[0] == "build", args
    Path(args[args.index("-o") + 1]).write_bytes(b"mock compiled executable")
elif name == "ssh":
    if os.environ.get("DEPLOY_TEST_SSH_FAIL") == "1":
        sys.exit(8)
    assert args[0] == "leqra", args
    env = dict(os.environ, PATH=os.environ["DEPLOY_TEST_BIN"])
    if args[1:] == ["sh", "-s"]:
        result = subprocess.run(["/bin/sh", "-s"], input=sys.stdin.buffer.read(), env=env)
    else:
        result = subprocess.run(args[1:], env=env)
    sys.exit(result.returncode)
elif name == "rsync":
    assert Path(args[-2]).is_file(), args
    if os.environ.get("DEPLOY_TEST_RSYNC_FAIL") == "1":
        sys.exit(9)
elif name == "getent":
    sys.exit(1 if os.environ.get("DEPLOY_TEST_NEW_USER") == "1" else 0)
elif name not in {"useradd", "mkdir", "chown", "systemctl"}:
    raise AssertionError("Unexpected mock command: " + name)
'''


class DeployTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="leqra deploy test ")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.deploy = self.root / "project with spaces" / "deploy"
        self.deploy.mkdir(parents=True)
        original = Path(__file__).resolve().parents[1] / "deploy" / "run.sh"
        shutil.copy2(original, self.deploy / "run.sh")
        (self.deploy / "leqra.service").write_text("[Service]\n")
        (self.deploy / "leqra.env").write_text("TEST=yes\n")
        (self.deploy / "leqra").write_bytes(b"preserve existing binary")
        self.bin = self.root / "mock bin"
        self.bin.mkdir()
        # The remote PATH contains only stubs: unexpected commands fail safely.
        for name in ("go", "ssh", "rsync", "getent", "useradd",
                     "mkdir", "chown", "systemctl"):
            command = self.bin / name
            command.write_text("#!" + sys.executable + "\n" + STUB)
            command.chmod(0o755)
        self.log = self.root / "commands.jsonl"
        self.build_tmp = self.root / "build temp"
        self.build_tmp.mkdir()
        self.cwd = self.root / "unrelated cwd"
        self.cwd.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("DEPLOY_TEST_")}
        self.env.update(PATH=str(self.bin) + os.pathsep + os.defpath,
                        TMPDIR=str(self.build_tmp), DEPLOY_TEST_LOG=str(self.log),
                        DEPLOY_TEST_BIN=str(self.bin))

    def run_deploy(self, **flags):
        env = dict(self.env)
        env.update({"DEPLOY_TEST_" + key: value for key, value in flags.items()})
        result = subprocess.run(["/bin/sh", str(self.deploy / "run.sh")],
                                cwd=self.cwd, env=env, capture_output=True,
                                text=True, timeout=15)
        events = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual((self.deploy / "leqra").read_bytes(),
                         b"preserve existing binary")
        self.assertEqual(list(self.build_tmp.iterdir()), [], "Build temp leaked")
        return result, events

    def check_success(self, new_user):
        result, events = self.run_deploy(NEW_USER="1" if new_user else "0")
        self.assertEqual(result.returncode, 0, result.stderr)
        names = [event["command"] for event in events]
        self.assertEqual(names[0], "go")
        self.assertEqual(names.count("ssh"), 2)
        self.assertEqual(names.count("useradd"), int(new_user))
        self.assertEqual(events[0]["cwd"], str(self.deploy))
        self.assertEqual((events[0]["goos"], events[0]["goarch"]),
                         ("linux", "amd64"))
        mkdir = next(event for event in events if event["command"] == "mkdir")
        for directory in ("/opt/leqra", "/etc/leqra", "/var/lib/leqra"):
            self.assertIn(directory, mkdir["args"])
        transfers = [event["args"] for event in events if event["command"] == "rsync"]
        self.assertEqual([args[-1] for args in transfers], [
            "leqra:/opt/leqra/leqra-server",
            "leqra:/etc/systemd/system/leqra.service",
            "leqra:/etc/leqra/leqra.env",
        ])
        self.assertIn(self.build_tmp, Path(transfers[0][-2]).parents)
        controls = [event["args"] for event in events if event["command"] == "systemctl"]
        self.assertEqual([next(arg for arg in args if not arg.startswith("-"))
                          for args in controls],
                         ["daemon-reload", "enable", "restart", "status"])
        self.assertIn("--no-pager", controls[-1])

    def test_existing_user(self):
        self.check_success(new_user=False)

    def test_new_user(self):
        self.check_success(new_user=True)

    def test_build_failure_never_contacts_remote(self):
        result, events = self.run_deploy(GO_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["command"] for event in events], ["go"])

    def test_ssh_failure_prevents_transfer(self):
        result, events = self.run_deploy(SSH_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([event["command"] for event in events], ["go", "ssh"])

    def test_transfer_failure_prevents_service_changes(self):
        result, events = self.run_deploy(RSYNC_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        names = [event["command"] for event in events]
        self.assertEqual(names.count("rsync"), 1)
        self.assertEqual(names.count("ssh"), 1)
        self.assertNotIn("systemctl", names)


if __name__ == "__main__":
    unittest.main()
