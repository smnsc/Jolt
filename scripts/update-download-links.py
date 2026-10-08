#!/usr/bin/env python3
"""Set website download buttons from the committed feed, without editing the feed."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def update_links(site):
    feed = site / 'appcast.xml'
    if not feed.exists():
        print('No release feed yet; keeping the releases-page fallback.')
        return
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    items = ET.parse(feed).findall('./channel/item')
    item = max(items, key=lambda entry: int(entry.findtext(ns + 'version')))
    version = item.findtext(ns + 'shortVersionString')
    if not version or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Invalid release version in feed')
    prefix = f'https://github.com/smnsc/Jolt/releases/download/v{version}/Jolt-{version}'
    if item.find('enclosure').get('url') != prefix + '.zip':
        raise ValueError('Unexpected update download URL')
    html = site / 'index.html'
    content, count = re.subn(r'data-jolt-download href="[^"]*"',
                             f'data-jolt-download href="{prefix}.dmg"', html.read_text())
    html.write_text(content)
    print(f'Updated {count} download links to Jolt {version}.dmg')


if __name__ == '__main__':
    update_links(Path(__file__).resolve().parent.parent / 'docs')
