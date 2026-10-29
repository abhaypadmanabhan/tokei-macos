#!/usr/bin/env python3
"""WP-2 live evidence: observe Cursor temp copies or sample one owned Tokei PID."""
import argparse
import csv
import json
import os
from pathlib import Path
import statistics
import stat
import subprocess
import tempfile
import time


def write_result(directory, name, result):
    (directory / name).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)


def watch_copies(directory):
    temporary = Path(os.environ.get("TMPDIR", tempfile.gettempdir()))
    deadline = time.monotonic() + 360
    while not (directory / "refresh-ready.json").exists():
        if time.monotonic() > deadline:
            raise SystemExit("Timed out waiting for the app's warm-cache checkpoint")
        time.sleep(0.01)
    if (directory / "refresh-proof.json").exists():
        raise SystemExit("Refresh proof already finished; start the observer before invoking it")
    seen = set(temporary.glob("TokeiCursorStateDB-*"))
    created = set()
    started = time.monotonic()
    while not (directory / "refresh-proof.json").exists():
        current = set(temporary.glob("TokeiCursorStateDB-*"))
        created.update(current - seen)
        seen.update(current)
        if time.monotonic() > deadline:
            raise SystemExit("Timed out waiting for three app refreshes")
        time.sleep(0.005)
    proof = json.loads((directory / "refresh-proof.json").read_text())
    write_result(directory, "cursor-copy-watch.json", {
        "refreshes": proof.get("refreshes"), "newCopies": len(created),
        "observedSeconds": round(time.monotonic() - started, 3),
        "names": sorted(path.name for path in created)
    })


def sample_cpu(directory, pid, seconds):
    command = subprocess.check_output(["ps", "-p", str(pid), "-o", "comm="], text=True).strip()
    if not command.endswith("/Tokei.app/Contents/MacOS/Tokei"):
        raise SystemExit("The supplied PID is not the expected Tokei executable")
    (directory / "cpu-monitor.pid").write_text(str(os.getpid()) + "\n")
    before = source_stamps()
    values = []
    start = time.monotonic()
    print("CPU measurement started", flush=True)
    with (directory / "cpu.csv").open("w") as output:
        writer = csv.writer(output)
        writer.writerow(["seconds", "ps_cpu_percent"])
        while True:
            elapsed = time.monotonic() - start
            value = float(subprocess.check_output(["ps", "-p", str(pid), "-o", "%cpu="], text=True))
            values.append(value)
            writer.writerow([round(elapsed, 3), value])
            output.flush()
            if elapsed >= seconds:
                break
            time.sleep(min(5, seconds - elapsed))
    after = source_stamps()
    changed = sum(before.get(path) != after.get(path) for path in before.keys() | after.keys())
    write_result(directory, "cpu-summary.json", {
        "pid": pid, "seconds": round(time.monotonic() - start, 3), "samples": len(values),
        "meanPercent": statistics.mean(values), "medianPercent": statistics.median(values),
        "maxPercent": max(values), "sourceFileCount": len(before), "sourceFilesChanged": changed
    })


def source_stamps():
    home = Path.home()
    patterns = [".claude*/projects/**/*.jsonl", ".codex/sessions/**/*.jsonl",
                ".copilot/session-state/*/events.jsonl", ".cline/data/sessions/**/*.json",
                ".gemini/antigravity*/conversations/**/*.db",
                ".gemini/antigravity*/conversations/**/*.db-wal"]
    stamps = {}
    for pattern in patterns:
        for path in home.glob(pattern):
            if path.name in {"auth.json", ".credentials.json", "oauth_creds.json"}:
                continue
            try:
                info = path.lstat()
                if stat.S_ISREG(info.st_mode):
                    stamps[str(path)] = (info.st_size, info.st_mtime_ns)
            except FileNotFoundError:
                continue
    return stamps


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--cpu-seconds", type=int, default=0)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    if args.cpu_seconds:
        if not args.pid:
            parser.error("--pid is required for CPU sampling")
        sample_cpu(args.directory, args.pid, args.cpu_seconds)
    else:
        watch_copies(args.directory)
