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
    count = 0

    def replace_download(match):
        nonlocal count
        tag = match.group()
        # Match attributes independently of whitespace, order, or quote style.
        if not re.search(r"\sdata-jolt-download(?=\s|=|/?>)", tag, re.I):
            return tag
        tag, replaced = re.subn(
            r"""(\shref\s*=\s*)(["'])(.*?)\2""",
            lambda href: href[1] + href[2] + prefix + '.dmg' + href[2],
            tag, flags=re.I | re.S)
        if replaced != 1:
            raise ValueError('Download button must have exactly one quoted href')
        count += 1
        return tag

    content = re.sub(r"""<a\b(?:[^>"']|"[^"]*"|'[^']*')*>""",
                     replace_download, html.read_text(), flags=re.I)
    if count == 0:
        raise ValueError('No data-jolt-download buttons found; refusing to deploy stale links')
    html.write_text(content)
    print(f'Updated {count} download links to Jolt {version}.dmg')


if __name__ == '__main__':
    update_links(Path(__file__).resolve().parent.parent / 'docs')
