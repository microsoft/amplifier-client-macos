"""Set only public update configuration in the packaged (not source) plist."""
import base64
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import urlsplit


def configuration(feed, public_key):
    if not feed and not public_key:
        return {}
    if not feed or not public_key:
        raise ValueError('Both AMPLIFIER_UPDATE_FEED_URL and AMPLIFIER_UPDATE_PUBLIC_KEY are required')
    url = urlsplit(feed)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or url.query or url.fragment or any(c.isspace() for c in feed)):
        raise ValueError('The update feed must be a credential-free HTTPS URL')
    if len(base64.b64decode(public_key, validate=True)) != 32:
        raise ValueError('The update public key must be a base64 Ed25519 public key')
    return {'SUFeedURL': feed, 'SUPublicEDKey': public_key, 'SURequireSignedFeed': True,
            'SUVerifyUpdateBeforeExtraction': True, 'SUSendProfileInfo': False,
            'SUAutomaticallyUpdate': False}


if __name__ == '__main__':
    path = Path(sys.argv[1])
    info = plistlib.loads(path.read_bytes())
    info.update(configuration(os.environ.get('AMPLIFIER_UPDATE_FEED_URL', ''), os.environ.get('AMPLIFIER_UPDATE_PUBLIC_KEY', '')))
    path.write_bytes(plistlib.dumps(info))
