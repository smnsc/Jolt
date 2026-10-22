#!/usr/bin/env python3
"""Exercise the local build workflow without compiling or signing an app."""
import importlib.util
import contextlib
import io
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('local_build', Path(__file__).resolve().parents[1] / 'build.py')
local_build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_build)


class LocalBuildTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'Resources').mkdir()
        self.plist = self.root / 'Resources/Info.plist'
        self.plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.1.4', 'CFBundleVersion': '126'}))
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/release').mkdir()
        shutil.copy2(Path(__file__).resolve().parents[1] / 'release/prepare.py', self.root / 'scripts/release')
        self.script('test.sh', 'echo test >> steps')
        self.script('macos/build-app.sh', 'echo build >> steps')
        for args in [('init', '--quiet'), ('config', 'user.name', 'Test'),
                     ('config', 'user.email', 'test@example.invalid'),
                     ('commit', '--quiet', '--allow-empty', '-m', 'Improve search')]:
            subprocess.run(['git', '-C', str(self.root), *args], check=True)

    def script(self, name, body):
        path = self.root / 'scripts' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('#!/bin/bash\nset -e\n' + body + '\n')
        path.chmod(0o755)

    def run_build(self, args):
        with patch('sys.stdin.isatty', return_value=False):
            local_build.build(args, self.root)

    def info(self):
        return plistlib.loads(self.plist.read_bytes())

    def test_new_version_tests_then_builds_and_generates_notes(self):
        self.run_build(['0.2.0'])
        self.assertEqual((self.root / 'steps').read_text(), 'test\nbuild\n')
        self.assertEqual(self.info()['CFBundleVersion'], '127')
        self.assertEqual(self.info()['CFBundleShortVersionString'], '0.2.0')
        notes = (self.root / 'dev-docs/releases/0.2.0.md').read_text()
        self.assertTrue(notes.startswith('# Jolt 0.2.0\n'))
        self.assertIn('Improve search', notes)

    def test_completion_is_reported_only_by_app_builder(self):
        self.script('macos/build-app.sh', 'echo "Built app — Jolt build 127"')
        # Capture child output and Python output together, as in a terminal.
        output_file = self.root / 'output.txt'
        with output_file.open('w+') as output, contextlib.redirect_stdout(io.StringIO()) as messages:
            original_run = subprocess.run

            def capture(*args, **kwargs):
                return original_run(*args, stdout=output, stderr=output, **kwargs)

            with patch.object(local_build.subprocess, 'run', side_effect=capture):
                self.run_build(['--build-only'])
            output.flush()
            output.seek(0)
            combined = messages.getvalue() + output.read()
        self.assertEqual(combined.count('Built '), 1)
        self.assertIn('Jolt build 127', combined)

    def test_existing_notes_are_preserved(self):
        notes = self.root / 'dev-docs/releases/0.2.0.md'
        notes.parent.mkdir(parents=True)
        notes.write_text('# Jolt 0.2.0\nReviewed notes\n')
        self.run_build(['0.2.0'])
        self.assertEqual(notes.read_text(), '# Jolt 0.2.0\nReviewed notes\n')

    def existing_current_notes(self):
        notes = self.root / 'dev-docs/releases/0.1.4.md'
        notes.parent.mkdir(parents=True)
        notes.write_text('# Jolt 0.1.4\nReviewed notes\n')
        return notes

    def test_regenerates_current_version_notes_with_latest_commits(self):
        notes = self.existing_current_notes()
        subprocess.run(['git', '-C', str(self.root), 'commit', '--quiet',
                        '--allow-empty', '-m', 'Fix latest search bug'], check=True)
        with patch('sys.stdin.isatty', return_value=True), patch(
                'builtins.input', side_effect=['', 'yes']) as prompt:
            local_build.build([], self.root)
        self.assertIn('Regenerate from scratch', prompt.call_args.args[0])
        regenerated = notes.read_text()
        self.assertTrue(regenerated.startswith('# Jolt 0.1.4\n'))
        self.assertIn('Jolt build 127', regenerated)
        self.assertIn('Improve search', regenerated)
        self.assertIn('Fix latest search bug', regenerated)
        self.assertNotIn('Reviewed notes', regenerated)
        self.assertEqual(self.info()['CFBundleShortVersionString'], '0.1.4')

    def test_declining_regeneration_preserves_existing_notes(self):
        notes = self.existing_current_notes()
        original = notes.read_bytes()
        for answer in ['', 'no', 'n']:
            with self.subTest(answer=answer), patch('sys.stdin.isatty', return_value=True), patch(
                    'builtins.input', return_value=answer):
                local_build.build(['--build-only'], self.root)
            self.assertEqual(notes.read_bytes(), original)

    def test_no_terminal_or_eof_preserves_existing_notes(self):
        notes = self.existing_current_notes()
        original = notes.read_bytes()
        with patch('builtins.input') as prompt:
            self.run_build(['--build-only'])
        prompt.assert_not_called()
        with patch('sys.stdin.isatty', return_value=True), patch(
                'builtins.input', side_effect=EOFError):
            local_build.build(['--build-only'], self.root)
        self.assertEqual(notes.read_bytes(), original)

    def test_failed_tests_preserve_notes_even_after_regeneration_confirmed(self):
        notes = self.existing_current_notes()
        original_notes = notes.read_bytes()
        original_plist = self.plist.read_bytes()
        self.script('test.sh', 'exit 1')
        with patch('sys.stdin.isatty', return_value=True), patch(
                'builtins.input', return_value='y'), self.assertRaises(subprocess.CalledProcessError):
            local_build.build(['--build-only'], self.root)
        self.assertEqual(notes.read_bytes(), original_notes)
        self.assertEqual(self.plist.read_bytes(), original_plist)

    def test_no_version_only_increments_build(self):
        self.run_build([])
        self.assertEqual(self.info()['CFBundleShortVersionString'], '0.1.4')
        self.assertEqual(self.info()['CFBundleVersion'], '127')
        self.assertFalse((self.root / 'dev-docs').exists())

    def test_prompt_accepts_version_or_blank(self):
        for answer, expected in [('0.2.0', '0.2.0'), ('', '0.1.4')]:
            with self.subTest(answer=answer):
                self.plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.1.4', 'CFBundleVersion': '126'}))
                with patch('sys.stdin.isatty', return_value=True), patch('builtins.input', return_value=answer):
                    local_build.build([], self.root)
                self.assertEqual(self.info()['CFBundleShortVersionString'], expected)

    def test_failed_tests_do_not_change_files(self):
        before = self.plist.read_bytes()
        self.script('test.sh', 'exit 1')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_build(['0.2.0'])
        self.assertEqual(self.plist.read_bytes(), before)
        self.assertFalse((self.root / 'dev-docs').exists())

    def test_invalid_or_old_version_does_not_run_tests(self):
        for version in ['bad', '0.1.04', '0.1.3', '0.1.4']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.run_build([version])
        self.assertFalse((self.root / 'steps').exists())

    def test_build_failure_retains_identity_for_retry(self):
        self.script('macos/build-app.sh', 'exit 1')
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_build(['--build-only'])
        self.assertEqual(self.info()['CFBundleVersion'], '127')


if __name__ == '__main__':
    unittest.main(buffer=True)
