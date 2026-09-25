"""Offline export/start/restart checks using generated synthetic data only."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--base-app', type=Path, required=True)
args = parser.parse_args()
work = Path(tempfile.mkdtemp(prefix='eve-dev-check-'))
scripts = Path(__file__).resolve().parent
info = plistlib.loads((args.base_app / 'Contents/Info.plist').read_bytes())
exe = args.base_app / 'Contents/MacOS' / info['CFBundleExecutable']
source_root = work / 'source'
env = dict(os.environ)
env.update(EVE_NEXUS_APPLICATION_SUPPORT_ROOT=str(source_root),
           EVE_NEXUS_USER_DEFAULTS_SUITE='com.local.EVENexusSimple.fixture.' + work.name,
           EVE_NEXUS_DISABLE_BACKGROUND_SERVICES='1', EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT='1')


def run(arguments, *, environment=env, expected=0):
    result = subprocess.run([str(a) for a in arguments], env=environment,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode != expected:
        raise AssertionError(f'{arguments[0]} exited {result.returncode}: {result.stdout.decode()}')
    return result.stdout.decode()


run([exe])
data_root = source_root / 'com.local.EVENexusSimple'
preferences = work / 'preferences.plist'
preferences.write_bytes(plistlib.dumps({'app.devFixture': 'synthetic-only'}))
wal = sqlite3.connect(data_root / 'fixture.sqlite')
wal.execute('PRAGMA journal_mode=WAL')
wal.execute('PRAGMA wal_autocheckpoint=0')
wal.execute('CREATE TABLE fixture (value TEXT)')
wal.execute("INSERT INTO fixture VALUES ('committed-in-wal')")
wal.commit()
app = work / 'Fixture-DEV.app'
run(['python3', scripts / 'export_dev_app.py', '--base-app', args.base_app,
     '--source-data', data_root, '--preferences-file', preferences, '--output', app])
seed = app / 'Contents/Resources/DevSeed'
with sqlite3.connect((seed / 'data/fixture.sqlite').as_uri() + '?mode=ro', uri=True) as db:
    assert db.execute('SELECT value FROM fixture').fetchall() == [('committed-in-wal',)]
db.close()
wal.close()

launcher = app / 'Contents/MacOS/DEVLauncher'
dev_root = work / 'first-start'
dev_env = dict(env, EVE_NEXUS_DEV_ACCEPTANCE_ROOT=str(dev_root),
               EVE_NEXUS_APPLICATION_SUPPORT_ROOT=str(work / 'production-sentinel'),
               EVE_NEXUS_USER_DEFAULTS_SUITE='must.never.be.used')
run([launcher], environment=dev_env)
assert (dev_root / 'com.local.EVENexusSimple/ApplicationData/EVENexusSimple.store').exists()
assert not (work / 'production-sentinel').exists()
changed = dev_root / 'com.local.EVENexusSimple/dev-change.txt'
changed.write_text('preserve on restart')
run([launcher], environment=dev_env)
assert changed.read_text() == 'preserve on restart'

# Observe the bundle identity and effective namespaces in the exec'd payload.
probe = work / 'Probe.swift'
probe.write_text('''import Foundation
let env = ProcessInfo.processInfo.environment
let domain = env["EVE_NEXUS_USER_DEFAULTS_SUITE"]!
let values: [String: String] = [
  "bundle": Bundle.main.bundleIdentifier ?? "missing",
  "root": env["EVE_NEXUS_APPLICATION_SUPPORT_ROOT"] ?? "missing",
  "suite": domain,
  "preference": UserDefaults(suiteName: domain)?.string(forKey: "app.devFixture") ?? "missing"
]
print(String(data: try JSONEncoder().encode(values), encoding: .utf8)!)
''')
payload = app / 'Contents/MacOS' / info['CFBundleExecutable']
run(['xcrun', 'swiftc', probe, '-o', payload])
run(['codesign', '--force', '--sign', '-', '--timestamp=none', payload])
run(['codesign', '--force', '--sign', '-', '--timestamp=none', app])
observed = json.loads(run([launcher], environment=dev_env))
assert observed['bundle'] == 'com.local.EVENexusSimple.DEV', observed
assert observed['root'] == str(dev_root), observed
assert observed['suite'].startswith('com.local.EVENexusSimple.DEV.smoke.'), observed
assert observed['preference'] == 'synthetic-only', observed

# A partial existing destination is never replaced.
partial = work / 'partial'
partial.mkdir()
(partial / 'preserve.txt').write_text('existing')
run([launcher], environment=dict(dev_env, EVE_NEXUS_DEV_ACCEPTANCE_ROOT=str(partial)), expected=1)
assert list(partial.iterdir()) == [partial / 'preserve.txt']

# A corrupt bundled snapshot must be rejected before any destination is created.
(seed / 'preferences.plist').write_text('corrupt')
run(['codesign', '--force', '--sign', '-', '--timestamp=none', app])
bad_root = work / 'bad-seed'
run([launcher], environment=dict(dev_env, EVE_NEXUS_DEV_ACCEPTANCE_ROOT=str(bad_root)), expected=1)
assert not bad_root.exists()
print(json.dumps(dict(workspace=str(work), checks=[
    'committed WAL captured', 'first startup succeeded', 'production namespace untouched',
    'restart preserves changes', 'DEV bundle and preferences confirmed in payload',
    'partial destination preserved', 'corrupt seed rejected']), indent=2))
