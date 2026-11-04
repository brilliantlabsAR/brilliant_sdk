#!/usr/bin/env python3
"""Run the unattended device checks of the Python SDK against one Halo.

Uses this workspace's own brilliant_ble (`uv run --project <python dir>`), so it
tests the SDK as it stands against the firmware on the device. The Halo
firmware's release process runs it as part of its pre-release battery.

    python3 tools/run_device_tests.py --name "Halo AB"            # all unattended checks
    python3 tools/run_device_tests.py --name "Halo AB" --only test_time.py

What runs:
- the standalone scripts in packages/brilliant_ble/tests that end on their own;
- the polling scripts (battery, IMU), bounded to 30 s, where a clean timeout
  counts as a pass;
- the pytest device modules, with BRILLIANT_DEVICE=1.
Scripts that need a human (button, taps, AAD, camera, throughput's Enter
prompt) are not run.

The standalone scripts print, they don't assert. A script passes if it exits 0
(or times out cleanly, for the polling ones) and its output has none of the
failure markers the firmware's tests/run_tests.py uses: `Lua error`,
`FAILED:`, `Traceback`, `Not connected to device`. Treat a pass as "nothing
exploded" and read the logs (--out) when the values matter. Exit status is
non-zero if anything failed.
"""
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

AUTO = """test_version.py test_time.py test_compression.py test_display.py test_display_bitmap.py
test_text_api.py test_speaker_pcm.py test_speaker_lc3.py test_speaker_lc3_2.py test_microphone.py
test_microphone_lc3.py test_bluetooth_callback_api.py test_file_execution.py test_file_api.py""".split()
POLL = "test_battery.py test_imu_raw.py test_imu_direction.py".split()
INTERACTIVE = "test_aad.py test_button.py test_taps.py test_camera.py test_bluetooth_throughput.py".split()
ERR = re.compile(r"Lua error|FAILED:|Traceback|Not connected to device")  # same markers as run_tests.py


def run(cmd, cwd, timeout, log):
    with open(log, "w") as fh:
        p = subprocess.Popen(cmd, cwd=cwd, stdout=fh, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            return p.wait(timeout=timeout), False
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, 2)  # SIGINT so the script disconnects cleanly
            try:
                p.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, 9)
                p.wait()
            return p.returncode, True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help='exact BLE device name, e.g. "Halo AB"')
    ap.add_argument("--sdk", type=Path, default=Path(__file__).resolve().parent.parent,
                    help="the SDK python workspace (default: this checkout)")
    ap.add_argument("--out", type=Path, default=Path("device-test-logs"),
                    help="directory for per-test logs (default: ./device-test-logs)")
    ap.add_argument("--only", action="append", help="run just this script (repeatable)")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    tests = a.sdk / "packages/brilliant_ble/tests"
    results = []

    plan = [(f, 240, False) for f in AUTO] + [(f, 30, True) for f in POLL]
    if a.only:
        plan = [p for p in plan if p[0] in a.only]
    for f, to, endless in plan:
        log = a.out / (f[:-3] + ".log")
        t0 = time.monotonic()
        rc, timed_out = run(["uv", "run", "--project", str(a.sdk), "python", f, "--name", a.name],
                            tests, to, log)
        text = log.read_text(errors="replace")
        ok = (timed_out if endless else (rc == 0 and not timed_out)) and not ERR.search(text)
        why = "" if ok else (" timeout" if timed_out and not endless else f" rc={rc}") + \
            (" (error in output)" if ERR.search(text) else "")
        results.append((f, ok))
        print(f"{'PASS' if ok else 'FAIL'} {f} {time.monotonic() - t0:.0f}s{why}", flush=True)
        time.sleep(5)

    if not a.only:
        log = a.out / "pytest_device.log"
        rc, to = run(["uv", "run", "pytest", "-q", "packages/brilliant_ble/tests/test_ble.py",
                      "packages/brilliant_ble/tests/test_disconnect_device.py", "--name", a.name],
                     a.sdk, 600, log)
        ok = rc == 0 and not to
        results.append(("pytest device modules", ok))
        print(f"{'PASS' if ok else 'FAIL'} pytest device modules (BRILLIANT_DEVICE=1)", flush=True)

    bad = [f for f, ok in results if not ok]
    print(f"SUMMARY pass={len(results) - len(bad)} fail={len(bad)}" + (f" failed: {' '.join(bad)}" if bad else ""))
    print(f"not run (interactive): {' '.join(INTERACTIVE)}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    os.environ["BRILLIANT_DEVICE"] = "1"
    main()
