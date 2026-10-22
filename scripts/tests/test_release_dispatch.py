#!/usr/bin/env python3
"""Exercise release guards with local Git repositories; never contact GitHub."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


class ReleaseDispatchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.root = self.directory / 'repo'
        self.root.mkdir()
        (self.root / 'scripts').mkdir()
        (self.root / 'Resources').mkdir()
        self.plist = self.root / 'Resources/Info.plist'
        self.write_version('0.1.5', '129')
        shutil.copy2(SCRIPTS / 'release.sh', self.root / 'scripts')
        self.git('init', '--quiet', '--initial-branch=main')
        self.git('config', 'user.name', 'Release Test')
        self.git('config', 'user.email', 'release-test@example.invalid')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Initial release')
        self.remote = self.directory / 'remote.git'
        subprocess.run(['git', 'init', '--quiet', '--bare', str(self.remote)], check=True)
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '--quiet', '-u', 'origin', 'main')
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        gh = self.bin / 'gh'
        gh.write_text('#!/bin/bash\nset -euo pipefail\nprintf "%s\\n" "$@" > "$TEST_DISPATCH"\n')
        gh.chmod(0o755)
        self.dispatch = self.directory / 'dispatch.txt'
        self.environment = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                                TEST_DISPATCH=str(self.dispatch))

    def write_version(self, version, build):
        self.plist.write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': version, 'CFBundleVersion': build}))

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args], check=True,
                              capture_output=True, text=True)

    def run_release(self, *args, answer=''):
        return subprocess.run([str(self.root / 'scripts/release.sh'), *args],
                              cwd=self.bin, env=self.environment, input=answer,
                              capture_output=True, text=True)

    def test_clean_checkout_dispatches_without_prompt(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Release 0.1.5 (Jolt build 129) requested', result.stdout)
        self.assertNotIn('Are you sure', result.stderr)
        self.assertEqual(self.dispatch.read_text().splitlines(),
                         ['workflow', 'run', 'release.yml', '--ref', 'main'])

    def test_each_type_of_file_change_prompts_and_defaults_to_cancel(self):
        for kind in ['unstaged', 'staged', 'untracked']:
            with self.subTest(kind=kind):
                self.git('reset', '--hard', 'HEAD')
                if kind == 'untracked':
                    (self.root / 'new-file.txt').write_text('new')
                else:
                    self.write_version('0.2.0', '130')
                    if kind == 'staged':
                        self.git('add', 'Resources/Info.plist')
                result = self.run_release(answer='\n')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Are you sure you want to continue?', result.stderr)
                self.assertIn('Release cancelled', result.stderr)
                self.assertFalse(self.dispatch.exists())

    def test_confirmation_releases_remote_version_instead_of_local_version(self):
        self.write_version('0.2.0', '130')
        result = self.run_release(answer='yes\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('remote main: Jolt 0.1.5 (Jolt build 129)', result.stderr)
        self.assertIn('will NOT be included', result.stderr)
        self.assertIn('Release 0.1.5 (Jolt build 129) requested', result.stdout)
        self.assertTrue(self.dispatch.exists())

    def test_unpushed_commits_prompt_even_when_no_files_are_dirty(self):
        self.git('commit', '--quiet', '--allow-empty', '-m', 'Unpushed change')
        result = self.run_release(answer='n\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('1 unpushed commit(s)', result.stderr)
        self.assertFalse(self.dispatch.exists())
        result = self.run_release(answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.dispatch.exists())

    def test_behind_remote_prompts(self):
        previous = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('commit', '--quiet', '--allow-empty', '-m', 'Remote update')
        self.git('push', '--quiet', 'origin', 'main')
        self.git('reset', '--hard', previous)
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('1 behind', result.stderr)
        self.assertIn('Release cancelled', result.stderr)
        self.assertFalse(self.dispatch.exists())

    def test_eof_cancels_dirty_release(self):
        self.write_version('0.2.0', '130')
        self.assertNotEqual(self.run_release().returncode, 0)
        self.assertFalse(self.dispatch.exists())

    def test_invalid_remote_version_does_not_dispatch_even_when_confirmed(self):
        self.write_version('invalid', '129')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Invalid metadata')
        self.git('push', '--quiet', 'origin', 'main')
        self.assertNotEqual(self.run_release(answer='yes\n').returncode, 0)
        self.assertFalse(self.dispatch.exists())

    def test_fetch_failure_does_not_dispatch(self):
        self.git('remote', 'set-url', 'origin', str(self.directory / 'missing.git'))
        self.assertNotEqual(self.run_release(answer='yes\n').returncode, 0)
        self.assertFalse(self.dispatch.exists())

    def test_old_arguments_are_rejected_with_usage(self):
        result = self.run_release('0.1.5', '129')
        self.assertEqual(result.returncode, 2)
        self.assertIn('reads version and build', result.stderr)
        self.assertFalse(self.dispatch.exists())


if __name__ == '__main__':
    unittest.main(buffer=True)
