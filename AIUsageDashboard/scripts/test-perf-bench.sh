#!/usr/bin/env bash
# Regression checks for the Release probe and its Python driver, using disposable
# bundles, preferences and homes only. No installed Tokei state is read or changed.
# Usage: test-perf-bench.sh /path/to/Tokei.app [all|python|launch|isolation]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I - "$SCRIPT_DIR" "${1:?Usage: test-perf-bench.sh /path/to/Tokei.app [all|python|launch|isolation]}" "${2:-all}" <<'PY'
import json
import os
import pathlib
import plistlib
import pwd
import subprocess
import sys
import tempfile
import time
import uuid

scripts, source = (pathlib.Path(value).resolve() for value in sys.argv[1:3])
mode = sys.argv[3]
if mode not in ('all', 'python', 'launch', 'isolation'):
    sys.exit('unknown test mode: ' + mode)
failures = []

def check(name, run):
    try:
        run()
        print('PASS ' + name, flush=True)
    except Exception as error:
        failures.append(name)
        print('FAIL ' + name + ': ' + str(error), flush=True)

def python_isolation():
    with tempfile.TemporaryDirectory(prefix='tokei-python-test-') as temporary:
        root = pathlib.Path(temporary)
        (root / 'json.py').write_text('raise RuntimeError("PERF_TEST_PYTHONPATH_LOADED")\n')
        environment = dict(os.environ, PYTHONPATH=str(root))
        result = subprocess.run(['/bin/bash', str(scripts / 'perf-bench.sh'), str(root / 'missing.app')],
                                cwd=root, env=environment, capture_output=True, text=True, timeout=15)
        assert result.returncode != 0, 'invalid input unexpectedly succeeded'
        assert 'PERF_TEST_PYTHONPATH_LOADED' not in result.stderr, 'loaded Python code from PYTHONPATH or cwd'
        assert 'perf-bench: expected a built Tokei.app' in result.stderr, result.stderr[-500:]

def launch_without_isolation(case):
    with tempfile.TemporaryDirectory(prefix='tokei-launch-test-') as temporary:
        root = pathlib.Path(temporary)
        home, app = root / 'home', root / 'Tokei.app'
        home.mkdir()
        (root / 'tmp').mkdir()
        if case == 'wrong_bundle':
            (home / '.tokei-perf-home').touch()
        prefix = 'ai.padzy.tokei.launch-test.' if case == 'wrong_bundle' else 'ai.padzy.tokei.perf.'
        identity = prefix + uuid.uuid4().hex
        subprocess.run(['/usr/bin/ditto', str(source), str(app)], check=True)
        info = app / 'Contents/Info.plist'
        metadata = plistlib.loads(info.read_bytes())
        metadata.update(CFBundleIdentifier=identity, SUEnableAutomaticChecks=False)
        info.write_bytes(plistlib.dumps(metadata))
        subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)],
                       check=True, capture_output=True)
        environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(home),
                       'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(root / 'tmp') + '/',
                       'CLAUDE_CONFIG_DIR': str(home / '.claude'), 'CODEX_HOME': str(home / '.codex'),
                       'ANTIGRAVITY_DATA_DIR': str(home / '.gemini/antigravity'), 'TOKEI_PERF_PROBE': '1'}
        arguments = [str(app / 'Contents/MacOS/Tokei'), '-ApplePersistenceIgnoreState', 'YES']
        for key in ('claudeNetworkUsageEnabled', 'codexLiveQuotaEnabled', 'cursorNetworkUsageEnabled',
                    'antigravityOnlineQuotaEnabled', 'geminiNetworkUsageEnabled', 'predictiveQuotaWarningsEnabled',
                    'burnNudgesEnabled', 'SUEnableAutomaticChecks'):
            arguments += ['-' + key, 'NO']
        process = None
        log = root / 'app.log'
        try:
            with log.open('w') as output:
                process = subprocess.Popen(arguments, env=environment, stdout=output, stderr=output)
                deadline = time.monotonic() + 15
                while True:
                    assert process.poll() is None, 'Release app exited ' + str(process.returncode) + ' before initial refresh'
                    records = [json.loads(line[7:]) for line in log.read_text(errors='replace').splitlines()
                               if line.startswith('[perf] ')]
                    events = {entry['event'] for entry in records}
                    assert 'isolated' not in events, 'unisolated launch entered benchmark mode'
                    if 'initial_refresh_complete' in events:
                        break
                    assert time.monotonic() < deadline, 'normal launch never completed its initial refresh'
                    time.sleep(0.05)
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            # cfprefsd uses the real home even when Foundation uses the test home.
            real_home = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)
            defaults_environment = {'PATH': '/usr/bin:/bin', 'HOME': str(real_home), 'CFFIXED_USER_HOME': str(real_home)}
            subprocess.run(['/usr/bin/defaults', 'delete', identity], env=defaults_environment,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            preference = real_home / 'Library/Preferences' / (identity + '.plist')
            preference.unlink(missing_ok=True)
            result = subprocess.run(['/usr/bin/defaults', 'read', identity], env=defaults_environment,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            assert result.returncode == 1 and not preference.exists(), 'test preferences cleanup failed'

def missing_isolation_fails_driver():
    with tempfile.TemporaryDirectory(prefix='tokei-isolation-test-') as temporary:
        root = pathlib.Path(temporary)
        # Fault injection: omit only the synthetic-home marker and shorten the wait.
        # The real Release app and the driver's failure path remain unchanged.
        script = (scripts / 'perf-bench.sh').read_text()
        for old, new in [("(home / '.tokei-perf-home').touch()", 'pass # deliberately omit isolation marker'),
                         ('deadline = time.monotonic() + 60', 'deadline = time.monotonic() + 5')]:
            assert script.count(old) == 1, 'benchmark test fixture no longer matches the driver'
            script = script.replace(old, new)
        driver = root / 'perf-bench.sh'
        driver.write_text(script)
        (root / 'perf-budget.json').write_bytes((scripts / 'perf-budget.json').read_bytes())
        result = subprocess.run(['/bin/bash', str(driver), str(source)], capture_output=True, text=True, timeout=30)
        assert result.returncode != 0, 'driver accepted a launch without isolation'
        assert 'missing benchmark hooks or first window' in result.stderr, result.stderr[-500:]

if mode in ('all', 'python'):
    check('driver ignores Python modules from PYTHONPATH and cwd', python_isolation)
if mode in ('all', 'launch'):
    for case in ('wrong_bundle', 'missing_marker'):
        check('unisolated Release launch proceeds (' + case + ')', lambda: launch_without_isolation(case))
if mode in ('all', 'isolation'):
    check('driver exits nonzero when isolation is missing', missing_isolation_fails_driver)
sys.exit(bool(failures))
PY
