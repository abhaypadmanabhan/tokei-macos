"""Independent, read-only Copilot shutdown recount. Prints numbers, never conversation text."""
import datetime
import json
import math
import os
import stat
import sys

LIMIT = 16 * 1024 * 1024
FIELDS = ("inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "reasoningTokens")


def records(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            return
        while True:
            line = stream.readline(LIMIT + 2)
            if not line:
                return
            oversized = len(line.rstrip(b"\n")) > LIMIT
            if oversized:
                while line and not line.endswith(b"\n"):
                    line = stream.readline(LIMIT + 2)
                continue
            try:
                event = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                continue
            if isinstance(event, dict) and event.get("type") == "session.shutdown":
                yield event


def counters(usage):
    values = []
    for field in FIELDS:
        value = usage.get(field, 0)
        if value is None:
            value = 0
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("invalid counter")
        if not math.isfinite(value) or value < 0 or int(value) != value:
            raise ValueError("invalid counter")
        values.append(int(value))
    return values


def recount(root, cutoff):
    maxima = {}
    shutdowns = 0
    if os.path.isdir(root):
        for session in sorted(os.scandir(root), key=lambda entry: entry.name):
            if not session.is_dir(follow_symlinks=False):
                continue
            path = os.path.join(session.path, "events.jsonl")
            if not os.path.isfile(path) or os.path.islink(path):
                continue
            for event in records(path):
                try:
                    timestamp = datetime.datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00"))
                    if timestamp.timestamp() > cutoff:
                        continue
                    metrics = event["data"]["modelMetrics"]
                    if not isinstance(metrics, dict):
                        continue
                    parsed = {model: counters(metric["usage"]) for model, metric in metrics.items()
                              if isinstance(metric, dict) and isinstance(metric.get("usage"), dict)}
                except (KeyError, TypeError, ValueError):
                    continue
                shutdowns += 1
                for model, values in parsed.items():
                    key = (session.name, model)
                    previous = maxima.get(key, [0] * len(FIELDS))
                    maxima[key] = [max(old, new) for old, new in zip(previous, values)]
    counts = dict(shutdowns=shutdowns, input=0, cacheRead=0, cacheWrite=0, output=0, reasoning=0,
                  reportedInput=0, total=0)
    for input_total, output, cache_read, cache_write, reasoning in maxima.values():
        reported_input = max(input_total, cache_read + cache_write)
        counts["reportedInput"] += reported_input
        counts["input"] += reported_input - cache_read - cache_write
        counts["cacheRead"] += cache_read
        counts["cacheWrite"] += cache_write
        counts["output"] += output
        counts["reasoning"] += min(reasoning, output)
        counts["total"] += reported_input + output
    return counts


if __name__ == "__main__":
    print(json.dumps(recount(sys.argv[1], float(sys.argv[2])), sort_keys=True, separators=(",", ":")))
