#!/usr/bin/env python3
"""Prepare a reviewed, locally signed release; never publishes or exports keys."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'build/Jolt.app'
TOOLS = ROOT / 'build/SwiftPM/artifacts/sparkle/Sparkle/bin'
ACCOUNT = 'co.simonsc.jolt'


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    if len(sys.argv) != 2:
        sys.exit('Usage: scripts/prepare-release.py RELEASE_NOTES.md')
    notes = Path(sys.argv[1]).resolve()
    if not notes.is_file() or not notes.read_text().strip():
        sys.exit('Provide nonempty release notes.')
    with (APP / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version) or not re.fullmatch(r'[1-9][0-9]*', build):
        sys.exit('Release version must be MAJOR.MINOR.PATCH without leading zeros and build must be a positive integer.')
    if info['CFBundleIdentifier'] != ACCOUNT:
        sys.exit('Refusing to release a different bundle identifier.')
    if info.get('SUFeedURL') != 'https://smnsc.github.io/Jolt/appcast.xml':
        sys.exit('Refusing to release an app using a test update feed.')
    public_key = run(TOOLS / 'generate_keys', '--account', ACCOUNT, '-p', capture_output=True, text=True).stdout.strip()
    if public_key != info.get('SUPublicEDKey'):
        sys.exit('The app public key does not match the signing key in Keychain.')
    feed = ROOT / 'docs/appcast.xml'
    if feed.exists():
        run(TOOLS / 'sign_update', '--account', ACCOUNT, '--verify', feed)
        previous = [int(item.text) for item in ET.parse(feed).iter('{http://www.andymatuschak.org/xml-namespaces/sparkle}version')]
        if previous and int(build) <= max(previous):
            sys.exit('Build number must exceed every previously published build.')
    output = ROOT / 'build/releases' / f'v{version}'
    if output.exists():
        sys.exit(f'{output} already exists; keep published releases immutable. Use a new version or move an unpublished staging folder aside.')
    output.mkdir(parents=True)
    run('codesign', '--verify', '--deep', '--strict', APP)
    run(ROOT / 'scripts/package-dmg.sh')
    dmg = output / f'Jolt-{version}.dmg'
    shutil.copy2(ROOT / 'build/Jolt.dmg', dmg)
    archive = output / f'Jolt-{version}.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', APP, archive)
    # Generate the feed from ZIP only; DMG is the manual/Homebrew installer.
    updates = output / 'updates'
    updates.mkdir()
    shutil.move(archive, updates / archive.name)
    shutil.copy2(notes, updates / f'Jolt-{version}.md')
    if feed.exists():
        shutil.copy2(feed, updates / 'appcast.xml')
    run(TOOLS / 'generate_appcast', '--account', ACCOUNT, '--maximum-deltas', '0',
        '--download-url-prefix', f'https://github.com/smnsc/Jolt/releases/download/v{version}/',
        '--embed-release-notes', '--link', 'https://smnsc.github.io/Jolt/', updates)
    run(TOOLS / 'sign_update', '--account', ACCOUNT, '--verify', updates / 'appcast.xml')
    shutil.move(updates / archive.name, archive)
    shutil.copy2(updates / 'appcast.xml', output / 'appcast.xml')
    shutil.copy2(notes, output / 'RELEASE_NOTES.md')
    checksums = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [dmg, archive]}
    (output / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in checksums.items()))
    cask = f'''cask "jolt" do
  version "{version}"
  sha256 "{checksums[dmg.name]}"

  url "https://github.com/smnsc/Jolt/releases/download/v#{{version}}/Jolt-#{{version}}.dmg"
  name "Jolt"
  desc "Native read-only Jira Cloud issue search"
  homepage "https://smnsc.github.io/Jolt/"

  auto_updates true
  depends_on macos: :sonoma

  app "Jolt.app"

  caveats <<~EOS
    Jolt is ad-hoc signed and is not Apple-notarized.
    After opening it once, use System Settings > Privacy & Security > Open Anyway
    if macOS blocks it. Jira may need reconnecting after an update.
  EOS
end
'''
    (output / 'jolt.rb').write_text(cask)
    print(f'Release prepared: {output}\nVersion {version}+build.{build} (Jolt build {build})\nPublish the release assets before deploying appcast.xml or updating the tap.')


if __name__ == '__main__':
    main()
