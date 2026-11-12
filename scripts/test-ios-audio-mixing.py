#!/usr/bin/env python3
"""Verify music continuity using two temporary iOS Simulator apps.

Pass --products pointing at Xcode's Debug-iphonesimulator products, or let this
script build them. The simulator must be booted; no device identifiers are saved.
Use --audio-source to run the same regression against an earlier GameAudio.swift.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path)
    parser.add_argument("--audio-source", type=Path, default=root / "ios/leqra/GameAudio.swift")
    parser.add_argument("--simulator", default="booted")
    parser.add_argument("--require-interruption-control", action="store_true",
                        help="fail if this simulator does not model cross-app interruption")
    args = parser.parse_args()
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="leqra-audio-mixing-") as temporary:
        work = Path(temporary)
        products = args.products
        if products is None:
            with (work / "build.log").open("w") as log:
                subprocess.run(["xcodebuild", "-project", str(root / "ios/leqra.xcodeproj"),
                    "-scheme", "leqra", "-configuration", "Debug", "-sdk", "iphonesimulator",
                    "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(work / "build"),
                    "CODE_SIGNING_ALLOWED=NO", "build"], stdout=log, stderr=log, check=True)
            products = work / "build/Build/Products/Debug-iphonesimulator"
        sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
        os.environ["SDKROOT"] = sdk
        architecture = run("uname", "-m")
        executable = work / "AudioMixingFixture"
        subprocess.run(["xcrun", "swiftc", "-sdk", sdk, "-target", architecture + "-apple-ios16.0-simulator",
            "-I", str(products), str(products / "leqraCore.o"),
            str(root / "ios/Tests/AudioMixing/Fixture.swift"), str(args.audio_source), "-o", str(executable)], check=True)
        identifiers = ["com.leqra.test.audio-sentinel", "com.leqra.test.audio-client"]
        try:
            for identifier in identifiers:
                app = work / (identifier + ".app")
                app.mkdir()
                (app / "AudioMixingFixture").write_bytes(executable.read_bytes())
                (app / "AudioMixingFixture").chmod(0o755)
                info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "AudioMixingFixture",
                    "CFBundleName": "Audio mixing test", "CFBundlePackageType": "APPL",
                    "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                    "MinimumOSVersion": "16.0", "UIDeviceFamily": [1, 2], "UILaunchScreen": {},
                    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}}}
                if identifier == identifiers[0]:
                    info["UIBackgroundModes"] = ["audio"]
                (app / "Info.plist").write_bytes(plistlib.dumps(info))
                run("codesign", "--force", "--sign", "-", str(app))
                run("xcrun", "simctl", "install", args.simulator, str(app))
            run("xcrun", "simctl", "launch", args.simulator, identifiers[0], "--sentinel")
            container = Path(run("xcrun", "simctl", "get_app_container", args.simulator, identifiers[0], "data"))
            status_file = container / "Documents/status.json"
            client_container = Path(run("xcrun", "simctl", "get_app_container", args.simulator, identifiers[1], "data"))

            def status():
                return json.loads(status_file.read_text())

            deadline = time.monotonic() + 10
            while not status_file.exists() and time.monotonic() < deadline:
                time.sleep(0.2)
            initial = status()
            assert initial["playing"] and "error" not in initial, initial
            for name, flags in [("muted menu", ["--muted"]), ("unmuted menu", []),
                                ("muted game", ["--muted", "--game"]),
                                ("zero-volume game", ["--zero-volume", "--game"]),
                                ("unmuted game", ["--game"])]:
                before = status()
                run("xcrun", "simctl", "launch", "--terminate-running-process", args.simulator, identifiers[1], *flags)
                time.sleep(2)
                after = status()
                client = json.loads((client_container / "Documents/status.json").read_text())
                assert "error" not in client, (name, client)
                if name == "unmuted game":
                    assert client["category"] == "AVAudioSessionCategoryAmbient" and client["mixes"], client
                assert after["playing"], (name, after)
                assert after["interruptions"] == 0, (name, after)
                assert after["time"] > before["time"] + 1, (name, before, after)
                print(name + ": background playback continued without interruption", flush=True)
            # Ensure the fixture can detect the exclusive-session behavior this
            # test protects against, rather than passing on an inert player.
            run("xcrun", "simctl", "launch", "--terminate-running-process", args.simulator, identifiers[1], "--exclusive")
            time.sleep(2)
            exclusive = status()
            detected = exclusive["interruptions"] > 0 or not exclusive["playing"]
            if args.require_interruption_control:
                assert detected, ("this simulator does not model exclusive-session interruption", exclusive)
            print("exclusive-session control: " + ("interruption detected" if detected else
                  "SKIPPED; this simulator does not model interruption. Verify background music on an iPhone."), flush=True)
        finally:
            for identifier in identifiers:
                subprocess.run(["xcrun", "simctl", "terminate", args.simulator, identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.run(["xcrun", "simctl", "uninstall", args.simulator, identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
