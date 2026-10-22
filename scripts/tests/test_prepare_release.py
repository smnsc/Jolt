#!/usr/bin/env python3
"""Offline regression checks for release numbering and automatic release notes."""
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import unittest

spec = importlib.util.spec_from_file_location(
    'prepare_release', Path(__file__).resolve().parents[1] / 'release/prepare.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseNumberingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.feed = Path(self.directory.name) / 'appcast.xml'

    def write_feed(self, entries):
        root = release.ET.Element('rss')
        channel = release.ET.SubElement(root, 'channel')
        for version, build in entries:
            item = release.ET.SubElement(channel, 'item')
            release.ET.SubElement(item, release.SPARKLE + 'shortVersionString').text = version
            release.ET.SubElement(item, release.SPARKLE + 'version').text = str(build)
        release.ET.ElementTree(root).write(self.feed)

    def test_exact_reset_preserves_source(self):
        self.write_feed([('0.1.1', 1791449100), ('0.1.0', 100)])
        original = self.feed.read_bytes()
        self.assertTrue(release.requires_feed_reset(self.feed, '0.1.2', '116'))
        self.assertEqual(self.feed.read_bytes(), original)

    def test_other_decreases_are_rejected(self):
        for prior, version, build in [
            (1791449100, '0.1.2', '115'),
            (1791449100, '0.1.3', '116'),
            (1791449101, '0.1.2', '116'),
        ]:
            with self.subTest(prior=prior, version=version, build=build):
                self.write_feed([('0.1.1', prior)])
                with self.assertRaises(ValueError):
                    release.requires_feed_reset(self.feed, version, build)

    def test_subsequent_releases_must_increase(self):
        self.write_feed([('0.1.2', 116)])
        self.assertFalse(release.requires_feed_reset(self.feed, '0.1.3', '117'))
        for version, build in [('0.1.3', '116'), ('0.1.3', '115'), ('0.1.2', '117')]:
            with self.subTest(version=version, build=build):
                with self.assertRaises(ValueError):
                    release.requires_feed_reset(self.feed, version, build)

    def test_reset_output_excludes_old_builds(self):
        self.write_feed([('0.1.2', 116)])
        release.validate_generated_feed(self.feed, '0.1.2', '116', True)
        for entries in [
            [('0.1.2', 116), ('0.1.1', 1791449100)],
            [('0.1.2', 116), ('0.1.0', 100)],
            [('0.1.2', 117)],
        ]:
            self.write_feed(entries)
            with self.assertRaises(ValueError):
                release.validate_generated_feed(self.feed, '0.1.2', '116', True)

    def test_normal_output_may_retain_older_short_builds(self):
        self.write_feed([('0.1.3', 117), ('0.1.2', 116)])
        release.validate_generated_feed(self.feed, '0.1.3', '117', False)

    def test_missing_feed_and_malformed_feed(self):
        self.assertFalse(release.requires_feed_reset(self.feed, '0.1.2', '116'))
        for entries in [[], [('invalid', 116)], [('0.1.1', 'invalid')]]:
            self.write_feed(entries)
            with self.assertRaises(ValueError):
                release.requires_feed_reset(self.feed, '0.1.2', '116')


class ReleaseNotesTests(unittest.TestCase):
    write_feed = ReleaseNumberingTests.write_feed

    def setUp(self):
        ReleaseNumberingTests.setUp(self)
        self.repository = Path(self.directory.name) / 'repository'
        self.repository.mkdir()
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Release Test')
        self.git('config', 'user.email', 'release-test@example.invalid')
        self.commit('Initial app')

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repository), *args],
                              check=True, capture_output=True, text=True)

    def commit(self, subject):
        self.git('commit', '--quiet', '--allow-empty', '-m', subject)

    def notes(self):
        return release.generate_release_notes('0.2.0', '200', self.feed, self.repository)

    def test_notes_start_after_previous_feed_release(self):
        self.git('tag', 'v0.1.4')
        self.write_feed([('0.1.3', 120), ('0.1.4', 121)])
        self.commit('Improve search')
        # An unrelated newer tag must not change the feed boundary.
        self.git('tag', 'v0.1.5')
        self.commit('Fix window focus')
        notes = self.notes()
        self.assertNotIn('Initial app', notes)
        self.assertLess(notes.index('Improve search'), notes.index('Fix window focus'))
        self.assertIn('Jolt build 200', notes)
        self.assertIn('not Apple-notarized', notes)

    def test_first_release_uses_all_history(self):
        self.assertIn('## Changes\n\n- Initial app\n\n', self.notes())

    def test_missing_tag_is_actionable(self):
        self.write_feed([('0.1.4', 121)])
        with self.assertRaisesRegex(ValueError, 'Fetch release tags'):
            self.notes()

    def test_unrelated_tag_is_rejected(self):
        original = self.git('rev-parse', 'HEAD').stdout.strip()
        self.git('checkout', '--orphan', 'other')
        self.commit('Other history')
        self.git('tag', 'v0.1.4')
        self.git('checkout', '--detach', original)
        self.write_feed([('0.1.4', 121)])
        with self.assertRaisesRegex(ValueError, 'HEAD history'):
            self.notes()

    def test_empty_range_has_nonempty_notes(self):
        self.git('tag', 'v0.1.4')
        self.write_feed([('0.1.4', 121)])
        self.assertIn('No source commits', self.notes())

    def test_shallow_checkout_is_rejected(self):
        clone = Path(self.directory.name) / 'shallow'
        subprocess.run(['git', 'clone', '--quiet', '--depth=1',
                        self.repository.as_uri(), str(clone)], check=True)
        with self.assertRaisesRegex(ValueError, 'full history'):
            release.generate_release_notes('0.2.0', '200', self.feed, clone)

    def test_subject_markup_is_literal(self):
        self.commit('Fix <script> and [links](url) with *stars* in full-screen 0.1.5 (test) #123!')
        notes = self.notes()
        self.assertNotIn('<script>', notes)
        self.assertIn(r'\[links\](url)', notes)
        self.assertIn(r'\*stars\*', notes)
        self.assertIn('full-screen 0.1.5 (test) #123!', notes)


if __name__ == '__main__':
    unittest.main(buffer=True)
