#!/usr/bin/env python3
"""Offline regression checks for the one-time release numbering reset."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'prepare_release', Path(__file__).with_name('prepare-release.py'))
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


if __name__ == '__main__':
    unittest.main()
