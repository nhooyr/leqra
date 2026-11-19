#!/usr/bin/env python3
"""Run the native iPhone muzzle test without networking from the XCTest runner.

Start TestNativeMuzzleDeviceServer with LEQRA_MUZZLE_DEVICE_ADDR set, then pass
the signed build-for-testing .xctestrun, device ID, and device-reachable server
URL. All results and screenshots belong outside the repository.
"""

import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xctestrun", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--fixture", default="http://127.0.0.1:18123")
    parser.add_argument("--results-dir", required=True)
    args = parser.parse_args()
    results_dir = Path(args.results_dir)
    results_dir.mkdir(parents=True, exist_ok=True)
    bundle = results_dir / "tests.xcresult"
    if bundle.exists():
        parser.error("Use a fresh results directory; tests.xcresult already exists.")
    environment = dict(os.environ)
    environment.update(
        TEST_RUNNER_LEQRA_TEST_SERVER=args.server,
        TEST_RUNNER_LEQRA_MUZZLE_DEVICE_UI="1",
        TEST_RUNNER_LEQRA_MUZZLE_HOST_COORDINATED="1",
    )
    command = [
        "xcodebuild", "-xctestrun", args.xctestrun,
        "-destination", "id=" + args.device,
        "-resultBundlePath", str(bundle),
        "-only-testing:leqraUITests/GameUITests/testOnlineMuzzleGhostWallsAndTouchTurning",
        "test-without-building",
    ]
    process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines = queue.Queue()

    def collect_output():
        for line in process.stdout:
            lines.put(line)
        lines.put(None)

    threading.Thread(target=collect_output, daemon=True).start()

    def fixture(body):
        request = urllib.request.Request(
            args.fixture.rstrip("/") + "/_fixture/muzzle",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.load(response)

    configurations, checks, errors, failures = {}, [], [], []
    deadline = time.monotonic() + 20 * 60
    try:
        with (results_dir / "xcodebuild.log").open("w") as log:
            while time.monotonic() < deadline:
                try:
                    line = lines.get(timeout=1)
                except queue.Empty:
                    continue
                if line is None:
                    break
                log.write(line)
                log.flush()
                if "MUZZLE_HOST " not in line:
                    if "error:" in line or "failed" in line or "passed" in line:
                        print(line.rstrip(), flush=True)
                    continue
                body = json.loads(line.split("MUZZLE_HOST ", 1)[1])
                key = (body["name"], body["infinity"])
                if not body.get("read"):
                    state = fixture(body)
                    if "wallX" not in state:
                        raise AssertionError("Fixture did not find a wall")
                    configurations[key] = dict(body, wallX=state["wallX"])
                    continue
                state = fixture(body)
                setup = configurations[key]
                try:
                    if body["check"] == "fire":
                        limit = time.monotonic() + 2
                        while state["shots"] == 0 and time.monotonic() < limit:
                            time.sleep(0.05)
                            state = fixture(body)
                        assert state["shots"] > 0, "Native Fire never reached the server"
                        if body["weapon"] != "cannon":
                            for bullet in state.get("bullets") or []:
                                assert bullet["x"] <= setup["wallX"] + 0.1, "Shot crossed the wall"
                                assert bullet["bounces"] > 0, "Shot did not reflect from the wall"
                    elif body["check"] == "turn":
                        assert abs(state["angle"]) > 0.5, "Native touch turn never reached the server"
                        assert state["input"].get("touchAim", False), "Native touch assistance was not requested"
                    else:
                        raise AssertionError("Unknown host check")
                    checks.append(dict(setup, check=body["check"], state=state))
                    print(f"HOST PASS {len(checks)}/44 {body['check']} "
                          f"infinity={body['infinity']} weapon={setup['weapon'] or 'normal'} "
                          f"ghost={setup['ghost']} gap={setup['gap']}", flush=True)
                except AssertionError as error:
                    errors.append(str(error))
                    failures.append(dict(setup, check=body["check"], state=state, error=str(error)))
                    print("HOST FAIL " + str(error), flush=True)
            else:
                raise TimeoutError("iPhone test exceeded 20 minutes")
        exit_code = process.wait(timeout=30)
    except BaseException:
        process.terminate()
        process.wait(timeout=30)
        raise
    fires = sum(check["check"] == "fire" for check in checks)
    turns = sum(check["check"] == "turn" for check in checks)
    passed = exit_code == 0 and fires == 40 and turns == 4 and not errors
    report = dict(passed=passed, xcodebuild_exit_code=exit_code,
                  firing_cases_passed=fires, turn_cases_passed=turns,
                  errors=errors, failures=failures, checks=checks)
    (results_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key not in ("checks", "failures")}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
