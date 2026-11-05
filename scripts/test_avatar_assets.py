"""Ensure the packaged catalog is complete and agrees with its public receipt."""
import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'Sources/AmplifierApp/Resources'
SHAPES = ['relay', 'accord', 'd20', 'crest', 'meter', 'clippy']


def chunks(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    offset = 8
    while offset < len(data):
        length, kind = struct.unpack('>I4s', data[offset:offset+8])
        yield kind, data[offset+8:offset+8+length]
        offset += length + 12


class AvatarAssets(unittest.TestCase):
    def test_catalog_and_frame_metadata(self):
        records = json.loads((ROOT/'GENERATED-ARTWORK.json').read_text())['assets']
        expected = set()
        for shape in SHAPES:
            for suffix in ['', '-dark']:
                base = shape + suffix
                expected.add(base + '.png')
                if shape not in ['relay', 'meter']:
                    expected.add(base + '-working.png')
        self.assertEqual(set(records), expected)
        total = 0
        for name, receipt in records.items():
            with self.subTest(name=name):
                path = ROOT/name
                data = path.read_bytes(); total += len(data)
                self.assertEqual(hashlib.sha256(data).hexdigest(), receipt['sha256'])
                self.assertEqual(len(data), receipt['bytes'])
                parts = list(chunks(path)); header = dict(parts)[b'IHDR']
                width, height, depth, color = struct.unpack('>IIBB', header[:10])
                self.assertEqual([width, height], receipt['size'])
                self.assertEqual((depth, color), (8, 6), 'RGBA preserves transparent desktops')
                shape = name.split('-')[0].split('.')[0]
                if '-working' in name:
                    frames, loops = struct.unpack('>II', dict(parts)[b'acTL'])
                    self.assertEqual(frames, receipt['frames']); self.assertEqual(loops, 0)
                    self.assertEqual((width, height), (256, 256))
                    controls = [body for kind, body in parts if kind == b'fcTL']
                    self.assertEqual(len(controls), frames)
                    duration = sum(struct.unpack('>HH', body[20:24])[0] / (struct.unpack('>HH', body[20:24])[1] or 100) for body in controls)
                    self.assertAlmostEqual(duration, {'accord':3.6,'d20':4.8,'crest':4.8,'clippy':4}[shape], delta=0.02)
                else:
                    count = 6 if shape == 'relay' else (8 if shape in ['accord','clippy'] else 16)
                    self.assertEqual((width, height), (1280, 320*((count+3)//4)))
        self.assertLess(total, 150*1024*1024)
        self.assertFalse((ROOT/'arc.png').exists())
        self.assertFalse((ROOT/'chord.png').exists())


if __name__ == '__main__':
    unittest.main()
