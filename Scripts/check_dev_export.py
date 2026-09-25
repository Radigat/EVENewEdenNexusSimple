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
preferences.write_bytes(plistlib.dumps({
    'app.devFixture': 'synthetic-only', 'app.boolean': True, 'app.count': 3,
    'app.data': b'synthetic', 'app.list': ['one', 'two'],
    'app.dictionary': {'value': 42}}))
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

launcher = app / 'Contents/MacOS' / info['CFBundleExecutable']
assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleExecutable'] == launcher.name
assert not (app / 'Contents/MacOS/DEVLauncher').exists()
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

def preferences_in(domain):
    return plistlib.loads(run(['/usr/bin/defaults', 'export', domain, '-']).encode())

smoke_domain = 'com.local.EVENexusSimple.DEV.smoke.' + dev_root.name
for key, value in plistlib.loads(preferences.read_bytes()).items():
    assert preferences_in(smoke_domain)[key] == value

# Exercise the real first-launch branch, whose domain equals its bundle ID.
# Substitute only the bundle identifier so this test never writes real DEV preferences.
own_id = 'com.local.EVENexusSimple.DEV.fixture.' + work.name
own_root = Path.home() / 'Library/Application Support' / own_id
assert not own_root.exists()
own_app = work / 'OwnDomain-DEV.app'
run(['ditto', '--norsrc', '--noextattr', app, own_app])
own_info_path = own_app / 'Contents/Info.plist'
own_info = plistlib.loads(own_info_path.read_bytes())
own_info['CFBundleIdentifier'] = own_id
own_info_path.write_bytes(plistlib.dumps(own_info))
own_launcher = own_app / 'Contents/MacOS' / info['CFBundleExecutable']
run(['codesign', '--force', '--sign', '-', '--timestamp=none', own_app])
own_env = dict(env)
own_env.pop('EVE_NEXUS_DEV_ACCEPTANCE_ROOT', None)
run([own_launcher], environment=own_env)
owned = preferences_in(own_id)
for key, value in plistlib.loads(preferences.read_bytes()).items():
    assert owned[key] == value
assert (own_root / 'dev-preferences-imported').exists()
# Recover the state left by an interrupted/failed preference import without reseeding data.
(own_root / 'dev-preferences-imported').unlink()
preserve = own_root / 'com.local.EVENexusSimple/preserve-after-interrupted-import.txt'
preserve.write_text('existing DEV data')
run([own_launcher], environment=own_env)
assert preferences_in(own_id)['app.devFixture'] == 'synthetic-only'
assert preserve.read_text() == 'existing DEV data'
# Existing user edits to the DEV preferences must survive a normal restart.
run(['/usr/bin/defaults', 'write', own_id, 'app.devFixture', '-string', 'changed-in-DEV'])
run([own_launcher], environment=own_env)
assert preferences_in(own_id)['app.devFixture'] == 'changed-in-DEV'
# Only the uniquely named synthetic domain and directory are removed.
run(['/usr/bin/defaults', 'delete', own_id])
shutil.rmtree(own_root)

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
    'restart preserves changes', 'native declared executable and isolated preferences confirmed',
    'own bundle domain imports mixed property-list settings',
    'interrupted preference import resumes without reseeding', 'edited DEV preferences survive restart',
    'partial destination preserved', 'corrupt seed rejected']), indent=2))
