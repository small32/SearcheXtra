#!/usr/bin/env python3
"""Bound one SwiftPM test class and retain evidence before stopping a hang."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys


def report(message):
    print(message, file=sys.stderr, flush=True)


def sample_processes(process, directory):
    snapshot = subprocess.run(
        ["ps", "-axo", "pid=,pgid=,comm="],
        capture_output=True, text=True, timeout=5, check=False,
    )
    targets = []
    for line in snapshot.stdout.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) != 3:
            continue
        pid, group, command = fields
        if int(group) == process.pid and (
            "xctest" in command.lower() or "PackageTests" in command
        ):
            targets.append(int(pid))
    if not targets:
        report("No xctest process in the test group; sampling the SwiftPM process.")
        targets = [process.pid]
    for pid in targets:
        destination = directory / f"sample-{pid}.log"
        report(f"=== All-thread sample for PID {pid}: {destination} ===")
        try:
            sampled = subprocess.run(
                ["sample", str(pid), "1", "-file", str(destination)],
                capture_output=True, text=True, timeout=10, check=False,
            )
            if sampled.stdout or sampled.stderr:
                report(sampled.stdout + sampled.stderr)
            if destination.exists():
                report(destination.read_text(errors="replace"))
            elif sampled.returncode:
                report(f"sample exited with status {sampled.returncode}")
        except (OSError, subprocess.TimeoutExpired) as error:
            report(f"Could not sample PID {pid}: {error}")


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    # The SwiftPM parent can exit before its children; stop the entire group.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("test_class")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command or args.timeout <= 0:
        parser.error("a command and a positive timeout are required")

    directory = (
        Path("build/macos-launch-smoke/native-tests/regressions") / args.test_class
    ).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    trace = directory / "progress.log"
    trace.write_text("")
    environment = dict(os.environ, SEARCH_NATIVE_TEST_TRACE=str(trace))
    process = subprocess.Popen(args.command, env=environment, start_new_session=True)
    try:
        code = process.wait(timeout=args.timeout)
        return code if code >= 0 else 128 - code
    except subprocess.TimeoutExpired:
        report(f"=== TIMEOUT: {args.test_class} exceeded {args.timeout:g} seconds ===")
        try:
            report(f"=== Test progress: {trace} ===")
            report(trace.read_text(errors="replace") or "(no test progress recorded)")
            sample_processes(process, directory)
        except (OSError, subprocess.TimeoutExpired) as error:
            report(f"Could not collect timeout diagnostics: {error}")
        finally:
            stop_group(process)
        return 124
    except KeyboardInterrupt:
        stop_group(process)
        return 130


if __name__ == "__main__":
    sys.exit(main())
