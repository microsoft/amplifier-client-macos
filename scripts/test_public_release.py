"""Publication safety gates with synthetic artifacts; no network or real signing."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-public.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.metadata = {'product': 'Amplifier for Mac', 'bundleIdentifier': 'com.microsoft.amplifier.macos',
                         'notarizationRequired': True, 'diskImageNotarizationRequired': True, 'updateFeed': publisher.FEED,
                         'version': '1.2.3', 'build': '24', 'sourceRevision': 'revision'}
        self.write_info()
        archive = b'synthetic artifact, not an actual signed app'
        (self.root / publisher.ARCHIVE).write_bytes(archive)
        (self.root / publisher.DISK_IMAGE).write_bytes(b'synthetic disk image')
        (self.root / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256((self.root / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in (publisher.ARCHIVE, publisher.DISK_IMAGE)))
        self.feed = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>24</sparkle:version>
          <enclosure url="{publisher.ROOT}/download/v1.2.3/{publisher.ARCHIVE}" length="{len(archive)}"
          sparkle:edSignature="{base64.b64encode(bytes(64)).decode()}" /></item></channel></rss>'''
        (self.root / 'appcast.xml').write_text(self.feed)

    def write_info(self):
        (self.root / 'BUILD-INFO.json').write_text(json.dumps(self.metadata))

    def test_expected_artifact(self):
        self.assertEqual(publisher.validate(self.root, 'v1.2.3', 'revision'), 24)

    def test_unsigned_or_wrong_source_or_feed_rejected(self):
        for key, value in [('product', 'Other app'), ('bundleIdentifier', 'com.example.other'),
                           ('notarizationRequired', False), ('diskImageNotarizationRequired', False),
                           ('updateFeed', 'https://example.invalid/feed'), ('sourceRevision', 'other'), ('build', '0')]:
            with self.subTest(key=key):
                old = self.metadata[key]
                self.metadata[key] = value
                self.write_info()
                with self.assertRaises(ValueError):
                    publisher.validate(self.root, 'v1.2.3', 'revision')
                self.metadata[key] = old

    def test_preview_tag_rejected(self):
        with self.assertRaises(ValueError):
            publisher.validate(self.root, 'v1.2.3-preview.1', 'revision')

    def test_tampered_archive_rejected(self):
        (self.root / publisher.ARCHIVE).write_bytes(b'tampered')
        with self.assertRaises(ValueError):
            publisher.validate(self.root, 'v1.2.3', 'revision')

    def test_tampered_disk_image_rejected(self):
        (self.root / publisher.DISK_IMAGE).write_bytes(b'tampered')
        with self.assertRaises(ValueError):
            publisher.validate(self.root, 'v1.2.3', 'revision')

    def test_missing_or_duplicate_checksums_rejected(self):
        checksums = self.root / 'SHA256SUMS'
        first = checksums.read_text().splitlines()[0] + '\n'
        for content in (first, first + first):
            checksums.write_text(content)
            with self.assertRaises(ValueError):
                publisher.validate(self.root, 'v1.2.3', 'revision')

    def test_foreign_archive_or_version_rejected(self):
        for before, after in [('/download/v1.2.3/', '/download/v0.1.0/'), ('>24<', '>23<')]:
            (self.root / 'appcast.xml').write_text(self.feed.replace(before, after))
            with self.assertRaises(ValueError):
                publisher.validate(self.root, 'v1.2.3', 'revision')

    def test_publication_stages_before_latest(self):
        with patch.dict(os.environ, GH_TOKEN='synthetic', RELEASE_TAG='v1.2.3', SOURCE_REVISION='revision'), \
             patch('sys.argv', ['publish', str(self.root), 'notes.md']), \
             patch.object(publisher, 'gh', side_effect=[json.dumps({'private': False}),
                 json.dumps({'sha': 'revision'}), '[]', '', '']) as gh:
            publisher.main()
        self.assertEqual(gh.call_args_list[3].args[:3], ('release', 'create', 'v1.2.3'))
        self.assertIn('--draft', gh.call_args_list[3].args)
        self.assertIn('--verify-tag', gh.call_args_list[3].args)
        self.assertNotIn('--target', gh.call_args_list[3].args)
        self.assertEqual(gh.call_args_list[4].args[:3], ('release', 'edit', 'v1.2.3'))
        self.assertIn('--latest', gh.call_args_list[4].args)

    def test_moved_source_tag_never_creates_release(self):
        with patch.dict(os.environ, GH_TOKEN='synthetic', RELEASE_TAG='v1.2.3', SOURCE_REVISION='revision'), \
             patch('sys.argv', ['publish', str(self.root), 'notes.md']), \
             patch.object(publisher, 'gh', side_effect=[json.dumps({'private': False}),
                 json.dumps({'sha': 'other'})]) as gh:
            with self.assertRaises(ValueError):
                publisher.main()
            self.assertTrue(all(call.args[0] == 'api' for call in gh.call_args_list))

    def test_existing_release_is_not_replaced(self):
        with patch.dict(os.environ, GH_TOKEN='synthetic', RELEASE_TAG='v1.2.3', SOURCE_REVISION='revision'), \
             patch('sys.argv', ['publish', str(self.root), 'notes.md']), \
             patch.object(publisher, 'gh', side_effect=[json.dumps({'private': False}),
                 json.dumps({'sha': 'revision'}), json.dumps([{'tag_name': 'v1.2.3'}])]) as gh:
            with self.assertRaises(ValueError):
                publisher.main()
            self.assertTrue(all(call.args[0] == 'api' for call in gh.call_args_list))

    def test_older_build_does_not_publish(self):
        with patch.dict(os.environ, GH_TOKEN='synthetic', RELEASE_TAG='v1.2.3', SOURCE_REVISION='revision'), \
             patch('sys.argv', ['publish', str(self.root), 'notes.md']), \
             patch.object(publisher, 'gh', side_effect=[json.dumps({'private': False}),
                 json.dumps({'sha': 'revision'}),
                 json.dumps([{'tag_name': 'v1.2.2', 'draft': False, 'prerelease': False}]),
                 json.dumps({'assets': [{'name': 'BUILD-INFO.json', 'url': 'https://api.github.com/synthetic'}]}),
                 json.dumps({'build': '25'})]) as gh:
            with self.assertRaises(ValueError):
                publisher.main()
            self.assertEqual(gh.call_count, 5)


if __name__ == '__main__':
    unittest.main()
