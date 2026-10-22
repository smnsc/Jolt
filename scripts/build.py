#!/usr/bin/env python3
"""Test, number, and build Jolt locally; never commits or publishes."""
import importlib.util
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def build(arguments, root=ROOT):
    if len(arguments) > 1:
        raise ValueError('Usage: scripts/build.py [MAJOR.MINOR.PATCH | --build-only]')
    if arguments == ['--help']:
        print('Usage: scripts/build.py [MAJOR.MINOR.PATCH | --build-only]')
        print('Without an argument, prompts for a version; Enter keeps the current version.')
        print('Existing release notes prompt for regeneration; Enter preserves them.')
        return
    plist = root / 'Resources/Info.plist'
    with plist.open('rb') as source:
        info = plistlib.load(source)
    current = info['CFBundleShortVersionString']
    requested = arguments[0] if arguments else ''
    if not arguments and sys.stdin.isatty():
        try:
            requested = input(f'New version (current {current}; Enter for build only): ').strip()
        except EOFError:
            requested = ''
    if requested == '--build-only':
        requested = ''
    if requested:
        pattern = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
        if not re.fullmatch(pattern, requested):
            raise ValueError('Version must be MAJOR.MINOR.PATCH without leading zeros.')
        if tuple(map(int, requested.split('.'))) <= tuple(map(int, current.split('.'))):
            raise ValueError(f'New version must be greater than {current}; use --build-only to keep it.')
    version = requested or current
    build_number = str(int(info['CFBundleVersion']) + 1)
    notes_path = root / 'dev-docs/releases' / f'{version}.md'
    notes_text = None
    regenerate_notes = False
    if notes_path.exists() and sys.stdin.isatty():
        try:
            answer = input(
                f'{notes_path.relative_to(root)} exists. Regenerate from scratch to include '
                'new commits? This replaces any manual edits. [y/N] ')
        except EOFError:
            answer = ''
        regenerate_notes = answer.strip().lower() in ('y', 'yes')
    if regenerate_notes or (requested and not notes_path.exists()):
        spec = importlib.util.spec_from_file_location('prepare_release', root / 'scripts/release/prepare.py')
        release = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release)
        notes_text = release.generate_release_notes(version, build_number, root / 'docs/appcast.xml', root)
    # Fail tests before changing the tracked version or writing release notes.
    print(f'Testing before building Jolt {version} (build {build_number})…', flush=True)
    subprocess.run([str(root / 'scripts/test.sh')], cwd=root, check=True)
    subprocess.run(['/usr/libexec/PlistBuddy', '-c', f'Set :CFBundleShortVersionString {version}', str(plist)], check=True)
    subprocess.run(['/usr/libexec/PlistBuddy', '-c', f'Set :CFBundleVersion {build_number}', str(plist)], check=True)
    if notes_text is not None:
        notes_path.parent.mkdir(parents=True, exist_ok=True)
        with notes_path.open('w' if regenerate_notes else 'x') as notes:
            notes.write(notes_text)
        action = 'Regenerated' if regenerate_notes else 'Created'
        print(f'{action} {notes_path.relative_to(root)}; review before releasing.', flush=True)
    # Keep the new identity if compilation fails so the same build can be retried.
    subprocess.run([str(root / 'scripts/macos/build-app.sh')], cwd=root, check=True)


if __name__ == '__main__':
    try:
        build(sys.argv[1:])
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
