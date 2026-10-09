#!/usr/bin/env python3
"""Regression checks for download links in uploaded HTML."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'download_links', Path(__file__).with_name('update-download-links.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DownloadLinksTests(unittest.TestCase):
    def test_uploaded_html_formats(self):
        with tempfile.TemporaryDirectory() as directory:
            site = Path(directory)
            feed = (Path(__file__).resolve().parent.parent / 'docs/appcast.xml').read_bytes()
            (site / 'appcast.xml').write_bytes(feed)
            (site / 'index.html').write_text("""
<a class="button" data-jolt-download
 href="old.dmg">Download</a>
<a href='old.dmg' class='button' data-jolt-download>Download</a>
<a href="other.html">Help</a>
""")
            module.update_links(site)
            html = (site / 'index.html').read_text()
            version = module.ET.fromstring(feed).findtext(
                './channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString')
            self.assertEqual(html.count(f'Jolt-{version}.dmg'), 2)
            self.assertIn('href="other.html"', html)
            self.assertEqual((site / 'appcast.xml').read_bytes(), feed)
            module.update_links(site)
            self.assertEqual((site / 'index.html').read_text(), html)

    def test_missing_markers_fail_without_changing_html(self):
        with tempfile.TemporaryDirectory() as directory:
            site = Path(directory)
            (site / 'appcast.xml').write_bytes(
                (Path(__file__).resolve().parent.parent / 'docs/appcast.xml').read_bytes())
            original = '<a href="old.dmg">Download</a>'
            (site / 'index.html').write_text(original)
            with self.assertRaisesRegex(ValueError, 'No data-jolt-download'):
                module.update_links(site)
            self.assertEqual((site / 'index.html').read_text(), original)


if __name__ == '__main__':
    unittest.main()
