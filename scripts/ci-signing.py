"""Import release-only secrets into a disposable macOS keychain. Never log them."""
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        # security/notarytool diagnostics may echo inputs; keep those out of CI logs.
        raise RuntimeError(f'{args[0]} failed while configuring signing (exit {result.returncode})')
    return result.stdout


root = Path(os.environ['RUNNER_TEMP']) / 'tempo-signing'
if sys.argv[1:] == ['cleanup']:
    if root.is_dir():
        previous = root / 'previous-keychains.json'
        if previous.exists():
            run('security', 'list-keychains', '-d', 'user', '-s', *json.loads(previous.read_text()))
        keychain = root / 'release.keychain-db'
        if keychain.exists():
            run('security', 'delete-keychain', str(keychain))
        shutil.rmtree(root)
    sys.exit()

required = ['AMPLIFIER_CERTIFICATE_P12', 'AMPLIFIER_CERTIFICATE_PASSWORD', 'AMPLIFIER_SIGNING_IDENTITY',
            'AMPLIFIER_NOTARY_KEY_P8', 'AMPLIFIER_NOTARY_KEY_ID', 'AMPLIFIER_NOTARY_ISSUER_ID']
if any(not os.environ.get(name) for name in required):
    raise SystemExit('Signed releases are enabled but required signing/notarization secrets are missing.')
if root.exists():
    raise SystemExit('Signing directory already exists; clean the previous setup first.')
root.mkdir(mode=0o700)
previous = [line.strip().strip('"') for line in run('security', 'list-keychains', '-d', 'user').splitlines() if line.strip()]
(root / 'previous-keychains.json').write_text(json.dumps(previous))
keychain = str(root / 'release.keychain-db')
password = secrets.token_urlsafe(48)
p12 = root / 'certificate.p12'
p12.write_bytes(base64.b64decode(os.environ['AMPLIFIER_CERTIFICATE_P12'], validate=True)); p12.chmod(0o600)
key = root / 'notary.p8'
key.write_text(os.environ['AMPLIFIER_NOTARY_KEY_P8']); key.chmod(0o600)
try:
    run('security', 'create-keychain', '-p', password, keychain)
    run('security', 'set-keychain-settings', '-lut', '21600', keychain)
    run('security', 'unlock-keychain', '-p', password, keychain)
    run('security', 'import', str(p12), '-k', keychain, '-P', os.environ['AMPLIFIER_CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
    run('security', 'list-keychains', '-d', 'user', '-s', keychain, *previous)
    run('xcrun', 'notarytool', 'store-credentials', 'tempo-release', '--keychain', keychain,
        '--key', str(key), '--key-id', os.environ['AMPLIFIER_NOTARY_KEY_ID'], '--issuer', os.environ['AMPLIFIER_NOTARY_ISSUER_ID'])
finally:
    p12.unlink(missing_ok=True); key.unlink(missing_ok=True)
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.write('AMPLIFIER_SIGNING_KEYCHAIN=' + keychain + '\nAMPLIFIER_NOTARY_PROFILE=tempo-release\nAMPLIFIER_REQUIRE_NOTARIZATION=1\n')
