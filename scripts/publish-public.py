"""Publish only artifacts from the completed signed/notarized tag build job."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

REPO = 'microsoft/amplifier-client-macos'
ROOT = 'https://github.com/' + REPO + '/releases'
FEED = ROOT + '/latest/download/appcast.xml'
ARCHIVE = 'Amplifier-macOS.zip'
DISK_IMAGE = 'Amplifier-macOS.dmg'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate(directory, tag, revision):
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Only stable version tags may enter the public update channel')
    info = json.loads((directory / 'BUILD-INFO.json').read_text())
    if (info.get('product') != 'Amplifier for Mac' or info.get('bundleIdentifier') != 'com.microsoft.amplifier.macos'
            or info.get('notarizationRequired') is not True or info.get('diskImageNotarizationRequired') is not True or info.get('updateFeed') != FEED
            or info.get('version') != tag[1:] or info.get('sourceRevision') != revision):
        raise ValueError('Expected the signed, notarized build for this source and public channel')
    build = int(info['build'])
    if build < 1:
        raise ValueError('Build number must be positive')
    archive = directory / ARCHIVE
    expected = {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                for name in (ARCHIVE, DISK_IMAGE)}
    rows = [line.split() for line in (directory / 'SHA256SUMS').read_text().splitlines()]
    if (len(rows) != 2 or any(len(row) != 2 for row in rows)
            or {row[1]: row[0] for row in rows} != expected):
        raise ValueError('Release checksum mismatch')
    feed = ET.fromstring((directory / 'appcast.xml').read_bytes())
    enclosures = feed.findall('./channel/item/enclosure')
    if len(enclosures) != 1:
        raise ValueError('Expected exactly one update')
    enclosure = enclosures[0]
    if (enclosure.get('url') != ROOT + '/download/' + tag + '/' + ARCHIVE
            or int(enclosure.get('length', '0')) != archive.stat().st_size
            or int(feed.findtext('./channel/item/' + SPARKLE + 'version', '0')) != build
            or len(base64.b64decode(enclosure.get(SPARKLE + 'edSignature', ''), validate=True)) != 64):
        raise ValueError('Appcast does not describe this signed archive')
    # Cryptographic feed/archive verification happened in the macOS build job;
    # this publisher accepts only that run's artifact, never external input.
    return build


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def main():
    directory, notes = Path(sys.argv[1]), Path(sys.argv[2])
    tag = os.environ['RELEASE_TAG']
    build = validate(directory, tag, os.environ['SOURCE_REVISION'])
    if not os.environ.get('GH_TOKEN'):
        raise ValueError('A repository-scoped release credential is required')
    repo = json.loads(gh('api', 'repos/' + REPO))
    if repo['private']:
        raise ValueError('The release repository must be public')
    # The public source tag must already exist and identify this exact build.
    tag_commit = json.loads(gh('api', 'repos/' + REPO + '/commits/' + tag))
    if tag_commit['sha'] != os.environ['SOURCE_REVISION']:
        raise ValueError('The public source tag does not match the built revision')
    releases = json.loads(gh('api', 'repos/' + REPO + '/releases?per_page=100'))
    if any(row['tag_name'] == tag for row in releases):
        raise ValueError('Release already exists; never replace published update assets')
    if any(not row['draft'] and not row['prerelease'] for row in releases):
        latest = json.loads(gh('api', 'repos/' + REPO + '/releases/latest'))
        asset = next(row for row in latest['assets'] if row['name'] == 'BUILD-INFO.json')
        previous = json.loads(gh('api', asset['url'], '-H', 'Accept: application/octet-stream'))
        if int(previous['build']) >= build:
            raise ValueError('Refusing to move the public update channel backward')
    # Publish an explicit artifact allowlist; never signing logs or credentials.
    assets = [str(directory / name) for name in (ARCHIVE, DISK_IMAGE, 'SHA256SUMS', 'BUILD-INFO.json', 'appcast.xml')]
    gh('release', 'create', tag, *assets, '--repo', REPO, '--verify-tag',
       '--draft', '--title', 'Amplifier for Mac ' + tag[1:], '--notes-file', str(notes))
    # The latest-feed redirect switches only after all assets exist in the draft.
    gh('release', 'edit', tag, '--repo', REPO, '--draft=false', '--latest')


if __name__ == '__main__':
    main()
