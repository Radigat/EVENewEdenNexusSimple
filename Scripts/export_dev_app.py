#!/usr/bin/env python3
"""Package a separate local DEV app with a consistent copy of supplied app data.

No keychain access. The output must not already exist. Invoke from the project root.
"""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
from datetime import datetime, timezone


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def source_state(root):
    state = {}
    for path in root.rglob('*'):
        if path.is_symlink():
            raise ValueError('Symlinks in source data are not supported')
        if path.is_file() and not path.name.endswith('-shm'):
            stat = path.stat()
            state[str(path.relative_to(root))] = (stat.st_size, stat.st_mtime_ns)
    return state


def snapshot(source, destination):
    with source.open('rb') as stream:
        sqlite = stream.read(16) == b'SQLite format 3\x00'
    if not sqlite:
        shutil.copyfile(source, destination)
        return
    with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as original:
        with closing(sqlite3.connect(destination)) as copy:
            original.backup(copy)
            if copy.execute('PRAGMA journal_mode=DELETE').fetchone() != ('delete',):
                raise ValueError('Snapshot journal could not be finalized')
            if copy.execute('PRAGMA quick_check').fetchall() != [('ok',)]:
                raise ValueError('SQLite snapshot verification failed')
    for suffix in ('-wal', '-shm'):
        Path(str(destination) + suffix).unlink(missing_ok=True)


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-app', type=Path, required=True)
    parser.add_argument('--source-data', type=Path, required=True)
    parser.add_argument('--preferences-file', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = args.source_data.resolve(strict=True)
    output = args.output.absolute()
    if output.exists() or output.is_symlink():
        raise ValueError('Output already exists; it will not be overwritten')
    if source in output.parents:
        raise ValueError('Output must be outside the source data')
    preferences = args.preferences_file.read_bytes()
    pref_values = plistlib.loads(preferences)
    if any(word in key.lower() for key in pref_values
           for word in ('token', 'password', 'secret', 'credential')):
        raise ValueError('Sensitive preference key detected; inspect before export')
    before = source_state(source)
    with tempfile.TemporaryDirectory(prefix='eve-dev-package-') as temporary:
        stage = Path(temporary) / output.name
        run('ditto', '--norsrc', '--noextattr', args.base_app, stage)
        info_path = stage / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        original_executable = info['CFBundleExecutable']
        if info['CFBundleIdentifier'] != 'com.local.EVENexusSimple':
            raise ValueError('Expected the canonical release app as input')
        info.update(CFBundleIdentifier='com.local.EVENexusSimple.DEV',
                    CFBundleName=output.stem, CFBundleDisplayName=output.stem,
                    CFBundleExecutable='DEVLauncher',
                    EVENexusOriginalExecutable=original_executable)
        info_path.write_bytes(plistlib.dumps(info))
        seed = stage / 'Contents/Resources/DevSeed'
        seed.mkdir()
        files = {}
        sqlite_count = 0
        for relative in sorted(before):
            if relative.endswith(('-wal', '-shm')):
                continue  # Committed WAL contents are in the online SQLite snapshot.
            destination = seed / 'data' / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            snapshot(source / relative, destination)
            with destination.open('rb') as stream:
                sqlite_count += stream.read(16) == b'SQLite format 3\x00'
            files['data/' + relative] = sha256(destination)
        if source_state(source) != before or args.preferences_file.read_bytes() != preferences:
            raise ValueError('Source changed during copying; no app exported. Retry with a stable source.')
        if 'data/ApplicationData/EVENexusSimple.store' not in files:
            raise ValueError('Canonical application database is missing')
        (seed / 'preferences.plist').write_bytes(preferences)
        files['preferences.plist'] = sha256(seed / 'preferences.plist')
        manifest = dict(format=1, createdUTC=datetime.now(timezone.utc).isoformat(),
                        files=files, keychainExported=False, sqliteSnapshots=sqlite_count)
        (seed / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        run('xcrun', 'swiftc', '-O', '-target', 'arm64-apple-macos14.0',
            Path(__file__).with_name('DevAppLauncher.swift'),
            '-o', stage / 'Contents/MacOS/DEVLauncher')
        run('xattr', '-cr', stage)
        for framework in sorted((stage / 'Contents/Frameworks').glob('*.framework')):
            run('codesign', '--force', '--sign', '-', '--timestamp=none', '--options', '0', framework)
        # The original app executable is now nested code, separate from the launcher.
        run('codesign', '--force', '--sign', '-', '--timestamp=none', '--options', '0',
            stage / 'Contents/MacOS' / original_executable)
        run('codesign', '--force', '--sign', '-', '--timestamp=none', '--options', '0', stage)
        run('codesign', '--verify', '--deep', '--strict', stage)
        output.parent.mkdir(parents=True, exist_ok=True)
        run('ditto', '--norsrc', '--noextattr', stage, output)
        run('xattr', '-cr', output)
        run('codesign', '--verify', '--deep', '--strict', output)
        print(json.dumps(dict(output=str(output), seedFiles=len(files),
                              seedBytes=sum((seed / path).stat().st_size for path in files),
                              sqliteSnapshots=sqlite_count, signatureVerified=True)))


if __name__ == '__main__':
    main()
