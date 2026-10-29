"""Independent read-only Codex recount. Run only through the opt-in test.

Uses zstd -dc for compressed bytes, never the Swift decoder. Prices are read from
Tokei's bundled seed as data; token selection, cumulative deduplication, tier state,
and multiplication are implemented independently here. Never reads account files.
"""
import argparse
import datetime as dt
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

CAP = 16 * 1024 * 1024
MAX_INT = 2**63 - 1
FIELDS = ("input_tokens", "output_tokens", "cached_input_tokens", "reasoning_output_tokens", "total_tokens")


def integer(value, default=None):
    if value is None:
        return default
    if isinstance(value, bool):
        raise ValueError("boolean token count")
    if isinstance(value, str):
        if not re.fullmatch(r"[+-]?[0-9]+", value):
            raise ValueError("noninteger string")
        value = int(value)
    if isinstance(value, int):
        if 0 <= value <= MAX_INT:
            return value
        raise ValueError("token count outside Int64")
    if not isinstance(value, float) or not math.isfinite(value) or int(value) != value:
        raise ValueError("invalid token count")
    if not 0 <= value <= MAX_INT:
        raise ValueError("token count outside Int64")
    return int(value)


def instant(value):
    try:
        if isinstance(value, (float, int)):
            return dt.datetime.fromtimestamp(value, dt.timezone.utc)
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.timezone.utc)
    except (ValueError, TypeError, AttributeError, OverflowError):
        return None


def seed_rates(path):
    source = path.read_text()
    rates = {}
    for model, arguments in re.findall(r'"([^"\n]+)":\s*rate\(([^)]+)\)', source):
        fields = {name: float(number.replace("_", "")) for name, number in
                  re.findall(r"(\w+):\s*([0-9_.]+)", arguments)}
        rates[model] = (fields["input"], fields.get("cachedInput", fields["input"]), fields["output"])
    priorities = re.search(r"let priorityModels = \[(.*?)\]", source, re.S).group(1)
    for model in re.findall(r'"([^"]+)"', priorities):
        rates[model + "@priority"] = tuple(x * (2.5 if model == "gpt-5.5" else 2) for x in rates[model])
    for model in ("gpt-6-astra", "gpt-6.1-sol"):
        rates[model + "@ultrafast"] = tuple(x * 6 for x in rates[model])
    return rates


def rate_for(model, rates):
    key = model.strip().lower().replace(" ", "-")
    tier = ""
    if "@" in key and key.rsplit("@", 1)[1] in ("priority", "ultrafast", "fast"):
        key, tier = key.rsplit("@", 1)
        tier = "@" + tier
    key = key.removesuffix("[1m]")
    candidates = [key]
    if "/" in key:
        candidates.append(key.rsplit("/", 1)[1])
    candidates += [re.sub(r"-\d{8}$", "", c) for c in candidates if re.search(r"-\d{8}$", c)]
    candidates += [re.sub(r"(claude-(?:[a-z]+-)?\d+)\.(\d+)", r"\1-\2", c) for c in candidates]
    standard = next((rates[c] for c in candidates if c in rates), None)
    if standard is None:
        return None
    return next((rates[c + tier] for c in candidates if c + tier in rates), standard) if tier else standard


def records(stream):
    while True:
        line = stream.readline(CAP + 2)
        if not line:
            return
        size = len(line) - int(line.endswith(b"\n"))
        if size > CAP:
            while line and not line.endswith(b"\n"):
                line = stream.readline(CAP + 2)
            continue
        try:
            row = json.loads(line, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            if isinstance(row, dict):
                yield row
        except (ValueError, UnicodeError, RecursionError):
            pass


def count_rows(rows, reference, rates):
    model, tier, previous = "unknown", "", None
    result = {name: 0 for name in ("tokens", "reported", "input", "cacheRead", "output", "reasoning", "lifetimeTokens")}
    result.update(mtdUsd=0.0, unpricedModels=0)
    unpriced = set()
    month = reference.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    tomorrow = reference.replace(hour=0, minute=0, second=0, microsecond=0) + dt.timedelta(days=1)
    for row in rows:
        payload = row.get("payload")
        payload = payload if isinstance(payload, dict) else {}
        if row.get("type") == "turn_context" and isinstance(payload.get("model"), str):
            model = payload["model"] or "unknown"
        if row.get("type") == "event_msg" and payload.get("type") == "thread_settings_applied":
            settings = payload.get("thread_settings")
            settings = settings if isinstance(settings, dict) else {}
            value = settings.get("service_tier")
            tier = "@priority" if value in ("priority", "fast") else "@ultrafast" if value == "ultrafast" else ""
        if row.get("type") != "event_msg" or payload.get("type") != "token_count":
            continue
        info = payload.get("info")
        if not isinstance(info, dict) or not isinstance(info.get("last_token_usage"), dict):
            continue
        usage = info["last_token_usage"]
        try:
            raw_input, raw_output, cached, reasoning = (integer(usage.get(k), 0) for k in FIELDS[:4])
            total_reported = integer(usage.get("total_tokens"))
            cumulative = info.get("total_token_usage")
            signature = tuple(integer(cumulative.get(k)) for k in FIELDS) if isinstance(cumulative, dict) else None
            if signature is not None and all(v is None for v in signature):
                signature = None
            inputs, outputs = max(0, raw_input - cached), max(0, raw_output - reasoning)
            total = inputs + outputs + cached + reasoning
            if total > MAX_INT:
                continue
        except ValueError:
            continue
        repeated = signature is not None and signature == previous
        if signature is not None:
            previous = signature
        if repeated:
            continue
        result["lifetimeTokens"] += total
        date = instant(row.get("timestamp"))
        if date is None or not month <= date < tomorrow:
            continue
        result["tokens"] += total
        result["reported"] += total if total_reported is None else total_reported
        for key, value in (("input", inputs), ("output", outputs), ("cacheRead", cached), ("reasoning", reasoning)):
            result[key] += value
        rate = rate_for(model + tier, rates)
        if rate is None:
            if total > 0:
                unpriced.add(model + tier)
        else:
            result["mtdUsd"] += (inputs * rate[0] + cached * rate[1] + (outputs + reasoning) * rate[2]) / 1_000_000
    result["unpricedModels"] = len(unpriced)
    return result


def self_check(rates):
    reference = dt.datetime(2026, 10, 29, tzinfo=dt.timezone.utc)
    def event(cumulative, last):
        return {"type": "event_msg", "timestamp": "2026-10-28T10:00:00Z",
                "payload": {"type": "token_count", "info": {"total_token_usage": cumulative, "last_token_usage": last}}}
    first = dict(input_tokens=100, output_tokens=20, cached_input_tokens=20, reasoning_output_tokens=5, total_tokens=120)
    second = dict(input_tokens=130, output_tokens=20, cached_input_tokens=20, reasoning_output_tokens=5, total_tokens=150)
    rows = [{"type": "turn_context", "payload": {"model": "gpt-6.1-sol"}}, event(first, first), event(first, first),
            {"type": "event_msg", "payload": {"type": "thread_settings_applied", "thread_settings": {"service_tier": "priority"}}},
            event(second, dict(input_tokens=30, total_tokens=30))]
    result = count_rows(rows, reference, rates)
    assert result["tokens"] == result["reported"] == result["lifetimeTokens"] == 150
    assert result["input"] == 110 and result["cacheRead"] == 20 and result["output"] == 15 and result["reasoning"] == 5
    assert abs(result["mtdUsd"] - 0.000482) < 1e-12


def main():
    args = argparse.ArgumentParser()
    args.add_argument("root", type=Path)
    args.add_argument("end", type=float)
    args.add_argument("seed", type=Path)
    options = args.parse_args()
    rates = seed_rates(options.seed)
    self_check(rates)
    reference = dt.datetime.fromtimestamp(options.end, dt.timezone.utc)
    candidates = sorted(p for p in (options.root / "sessions").rglob("*")
                        if p.is_file() and not p.is_symlink() and (p.suffix == ".jsonl" or p.name.endswith(".jsonl.zst"))
                        and not any(part.startswith(".") for part in p.relative_to(options.root / "sessions").parts))
    plain = {p for p in candidates if p.suffix == ".jsonl"}
    files = [p for p in candidates if p.suffix == ".jsonl" or p.with_suffix("") not in plain]
    result = dict(files=len(files), compressedFiles=0, errors=0, selfCheck=True)
    zstd = shutil.which("zstd")
    if zstd is None:
        zstd = next((p for p in ("/opt/homebrew/bin/zstd", "/usr/local/bin/zstd") if Path(p).is_file()), None)
    for path in files:
        if path.suffix == ".zst":
            if zstd is None:
                raise RuntimeError("zstd is absent")
            result["compressedFiles"] += 1
            process = subprocess.Popen([zstd, "-q", "-d", "-c", "--", str(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            with process.stdout as stream:
                counts = count_rows(records(stream), reference, rates)
            if process.wait() != 0:
                result["errors"] += 1
                continue
        else:
            with path.open("rb") as stream:
                counts = count_rows(records(stream), reference, rates)
        for key, value in counts.items():
            result[key] = result.get(key, 0) + value
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
