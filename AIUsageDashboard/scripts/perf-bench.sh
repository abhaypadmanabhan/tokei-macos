#!/usr/bin/env bash
# Release-only performance check. Uses a disposable app identity, synthetic HOME,
# CFFIXED_USER_HOME (Foundation paths), provider overrides and disabled network.
# Workload is fixed: 128 Claude and 128 Cline sessions, 128 records each; one
# Claude assistant record appended each second. Includes real parsers and views.
# Requires Python 3 and macOS libproc; no packages, credentials or GUI automation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I - "$SCRIPT_DIR/perf-budget.json" "${1:?Usage: perf-bench.sh /path/to/Tokei.app}" <<'PY'
import ctypes
import datetime
import json
import os
import pathlib
import plistlib
import pwd
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid

budget = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = pathlib.Path(sys.argv[2]).resolve()
if not (source / 'Contents/MacOS/Tokei').is_file():
    sys.exit('perf-bench: expected a built Tokei.app')

# Layout: rusage_info_v2 in sys/resource.h. CPU times are Mach absolute ticks,
# not nanoseconds (on Apple Silicon the conversion is commonly 125/3).
class RUsage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_ubyte * 16)] + [(name, ctypes.c_uint64) for name in (
        'user_time', 'system_time', 'pkg_idle_wkups', 'interrupt_wkups', 'pageins',
        'wired_size', 'resident_size', 'phys_footprint', 'proc_start_abstime',
        'proc_exit_abstime', 'child_user_time', 'child_system_time',
        'child_pkg_idle_wkups', 'child_interrupt_wkups', 'child_pageins',
        'child_elapsed_abstime', 'diskio_bytesread', 'diskio_byteswritten')]

libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libproc.proc_pid_rusage.restype = ctypes.c_int
def usage(pid):
    value = RUsage()
    if libproc.proc_pid_rusage(pid, 2, ctypes.byref(value)) != 0:
        raise RuntimeError('proc_pid_rusage failed: ' + str(ctypes.get_errno()))
    return value

class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]
timebase = Timebase()
if ctypes.CDLL('/usr/lib/libSystem.B.dylib').mach_timebase_info(ctypes.byref(timebase)) != 0:
    sys.exit('perf-bench: could not read the Mach CPU timebase')
tick_ns = timebase.numer / timebase.denom
# An independent clock catches wrong units/layout before any publishable number.
calibration = usage(os.getpid())
calibration_cpu = time.process_time_ns()
calibration_end = time.monotonic() + 0.05
while time.monotonic() < calibration_end:
    pass
calibrated = usage(os.getpid())
observed_ns = ((calibrated.user_time + calibrated.system_time
               - calibration.user_time - calibration.system_time) * tick_ns)
expected_ns = time.process_time_ns() - calibration_cpu
if not 0.9 < observed_ns / expected_ns < 1.1:
    sys.exit('perf-bench: libproc CPU clock failed independent calibration')

def claude_record(identifier):
    return json.dumps({'type': 'assistant', 'timestamp': timestamp,
        'requestId': 'request-' + identifier, 'message': {'id': identifier,
        'model': 'claude-sonnet-4-5', 'role': 'assistant',
        'usage': {'input_tokens': 100, 'output_tokens': 50,
                  'cache_read_input_tokens': 20, 'cache_creation_input_tokens': 10}}}) + '\n'

def cleanup_preferences(identity):
    # cfprefsd ignores the child's Foundation home. Delete only this run's exact
    # disposable domain, then verify both daemon state and the real-home plist.
    if re.fullmatch(r'ai\.padzy\.tokei\.perf\.[0-9a-f]{32}', identity) is None:
        raise ValueError('refusing to delete a non-benchmark preferences domain')
    real_home = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)
    defaults_environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(real_home),
                            'CFFIXED_USER_HOME': str(real_home)}
    subprocess.run(['/usr/bin/defaults', 'delete', identity], env=defaults_environment,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    preferences = real_home / 'Library/Preferences' / (identity + '.plist')
    preferences.unlink(missing_ok=True)
    read = subprocess.run(['/usr/bin/defaults', 'read', identity], env=defaults_environment,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    if read.returncode != 1 or preferences.exists():
        raise RuntimeError('perf-bench: benchmark preferences cleanup failed')

process = None
def interrupt(signum, frame):
    raise KeyboardInterrupt()
signal.signal(signal.SIGTERM, interrupt)
signal.signal(signal.SIGINT, interrupt)

with tempfile.TemporaryDirectory(prefix='tokei-perf-') as temporary:
    root = pathlib.Path(temporary)
    home = root / 'home'
    home.mkdir()
    (home / '.tokei-perf-home').touch()
    (root / 'tmp').mkdir()
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    claude = home / '.claude/projects/synthetic'
    claude.mkdir(parents=True)
    cline = home / '.cline/data/sessions'
    cline.mkdir(parents=True)
    for session in range(128):
        (claude / f'{session}.jsonl').write_text(''.join(
            claude_record(f'message-{session}-{row}') for row in range(128)))
        folder = cline / str(session)
        folder.mkdir()
        (folder / f'{session}.messages.json').write_text(json.dumps({'messages': [
            {'id': f'cline-{session}-{row}', 'ts': time.time(),
             'metrics': {'inputTokens': 100, 'outputTokens': 50, 'cost': 0.001}}
            for row in range(128)]}))
    for directory in ('.codex/sessions', '.gemini', '.copilot/session-state', '.local/share/opencode'):
        (home / directory).mkdir(parents=True)
    active = claude / 'active.jsonl'
    active.write_text(claude_record('active-0'))

    app = root / 'Tokei.app'
    # Copy first: never re-sign or edit the given app, especially /Applications.
    subprocess.run(['/usr/bin/ditto', str(source), str(app)], check=True)
    info = app / 'Contents/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    identity = 'ai.padzy.tokei.perf.' + uuid.uuid4().hex
    metadata.update(CFBundleIdentifier=identity, SUEnableAutomaticChecks=False)
    info.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    # Do not inherit agent auth, provider roots, or DYLD injection from the caller.
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(home),
        'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(root / 'tmp') + '/',
        'CLAUDE_CONFIG_DIR': str(home / '.claude'), 'CODEX_HOME': str(home / '.codex'),
        'ANTIGRAVITY_DATA_DIR': str(home / '.gemini/antigravity'), 'TOKEI_PERF_PROBE': '1'}
    args = [str(app / 'Contents/MacOS/Tokei'), '-ApplePersistenceIgnoreState', 'YES']
    for key in ('claudeNetworkUsageEnabled', 'codexLiveQuotaEnabled', 'cursorNetworkUsageEnabled',
                'antigravityOnlineQuotaEnabled', 'geminiNetworkUsageEnabled', 'predictiveQuotaWarningsEnabled',
                'burnNudgesEnabled', 'SUEnableAutomaticChecks'):
        args += ['-' + key, 'NO']
    log = root / 'app.log'
    def events():
        return [json.loads(line[7:]) for line in log.read_text(errors='replace').splitlines()
                if line.startswith('[perf] ')]
    try:
        with log.open('w') as output:
            launched = time.time()
            process = subprocess.Popen(args, env=environment, stdout=output, stderr=output)
            deadline = time.monotonic() + 60
            while True:
                if process.poll() is not None:
                    raise RuntimeError('app exited before sample: ' + log.read_text(errors='replace')[-4000:])
                records = events()
                kinds = {entry['event'] for entry in records}
                if {'isolated', 'first_window', 'window_closed', 'initial_refresh_complete'} <= kinds:
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError('missing benchmark hooks or first window; use an instrumented Release build')
                time.sleep(0.05)
            isolated = next(entry for entry in records if entry['event'] == 'isolated')
            if pathlib.Path(isolated['home']).resolve() != home.resolve():
                raise RuntimeError('Foundation did not adopt the synthetic home')
            launch_ms = (float(next(entry for entry in records if entry['event'] == 'first_window')['timestamp'])
                         - launched) * 1000
            # Identical three-second settle on both builds, outside the CPU sample.
            time.sleep(3)
            first = usage(process.pid)
            started = time.monotonic()
            sample_epoch = time.time()
            print('perf-bench: sampling 120 seconds with all windows closed', file=sys.stderr, flush=True)
            footprints = []
            writes = 0
            duration = budget['sample_seconds']
            for second in range(duration):
                with active.open('a') as stream:
                    stream.write(claude_record(f'active-{second + 1}'))
                writes += 1
                time.sleep(max(0, started + second + 1 - time.monotonic()))
                if process.poll() is not None:
                    raise RuntimeError('app exited during sample')
                footprints.append(usage(process.pid).phys_footprint / (1024 * 1024))
            last = usage(process.pid)
            elapsed = time.monotonic() - started
        counts = dict.fromkeys(('claude_code', 'codex', 'cursor', 'antigravity', 'cline',
                               'opencode', 'gemini', 'copilot'), 0)
        for entry in events():
            if entry['event'] == 'provider_refresh' and float(entry['timestamp']) >= sample_epoch:
                counts[entry['provider']] += 1
        result = {'average_cpu_percent': round((last.user_time + last.system_time - first.user_time
                    - first.system_time) * tick_ns / 1e9 / elapsed * 100, 3),
                  'physical_footprint_mb': round(sum(footprints) / len(footprints), 3),
                  'peak_footprint_mb': round(max(footprints), 3),
                  'cold_launch_to_window_ms': round(launch_ms, 1),
                  'sample_seconds': round(elapsed, 3), 'writes': writes,
                  'provider_refreshes': counts, 'synthetic_home_verified': True,
                  'defaults_suite': identity, 'workload_version': 1}
        failures = [key for key in ('average_cpu_percent', 'physical_footprint_mb',
                                    'cold_launch_to_window_ms') if result[key] > budget[key]]
        result['budget_passed'] = not failures
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        cleanup_preferences(identity)
    result['preferences_cleaned'] = True
    print(json.dumps(result, sort_keys=True), flush=True)
    print('Metric                              Measured        Budget')
    for key, unit in (('average_cpu_percent', '%'), ('physical_footprint_mb', 'MB'),
                      ('cold_launch_to_window_ms', 'ms')):
        print(f'{key:34} {result[key]:9.3f} {unit:3} {budget[key]:9.3f} {unit}')
    print('Provider refreshes (120 seconds, window closed): ' + json.dumps(counts, sort_keys=True))
    if failures:
        print('OVER BUDGET: ' + ', '.join(failures), file=sys.stderr)
        sys.exit(1)
PY
