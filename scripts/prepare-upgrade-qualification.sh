#!/bin/bash
# Isolated initial-release upgrade fixture. Never publish these files as a release.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${AMPLIFIER_SIGNING_IDENTITY:?Developer ID required}"
: "${AMPLIFIER_SPARKLE_PRIVATE_KEY:?Update signing seed required}"
[[ "${AMPLIFIER_REQUIRE_NOTARIZATION:-0}" == 1 ]] || { echo 'Notarization is required.' >&2; exit 1; }
[[ ! -e upgrade-qualification ]] || { echo 'Qualification directory already exists.' >&2; exit 1; }
python3 - <<'PY'
import json
from pathlib import Path
info = json.loads(Path('dist/BUILD-INFO.json').read_text())
if info['version'] != '0.1.0' or info['build'] != '1':
    raise SystemExit('This fixture is only for the initial 0.1.0 build 1 release.')
PY
mkdir -p upgrade-qualification/baseline upgrade-qualification/feed
ditto dist/Amplifier.app upgrade-qualification/baseline/Amplifier.app
python3 - <<'PY'
import json, plistlib
from pathlib import Path
app = Path('upgrade-qualification/baseline/Amplifier.app')
path = app / 'Contents/Info.plist'
info = plistlib.loads(path.read_bytes())
# Keep the bundle's production HTTPS feed so AppUpdater initializes normally.
# Sparkle's loopback feed override is passed only at test launch, never persisted.
info.update(CFBundleShortVersionString='0.0.0', CFBundleVersion='0',
            SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
path.write_bytes(plistlib.dumps(info))
path = app / 'Contents/Resources/BUILD-INFO.json'
metadata = json.loads(path.read_text())
metadata.update(version='0.0.0', build='0', qualificationOnly=True,
                updateFeed=info['SUFeedURL'])
path.write_text(json.dumps(metadata, indent=2) + '\n')
PY
baseline_app="$PWD/upgrade-qualification/baseline/Amplifier.app"
baseline_zip="$PWD/upgrade-qualification/baseline/Amplifier-upgrade-baseline.zip"
bash sign-app.sh "$baseline_app"
ditto -c -k --keepParent "$baseline_app" "$baseline_zip"
bash notarize-app.sh "$baseline_app" "$baseline_zip"
# The update is the exact release archive; do not modify its bundle or feed URL.
cp dist/Amplifier-macOS.zip upgrade-qualification/feed/
printf '%s' "$AMPLIFIER_SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --ed-key-file - --maximum-deltas 0 \
  --download-url-prefix http://127.0.0.1:49340/ \
  -o upgrade-qualification/feed/appcast.xml upgrade-qualification/feed
printf '%s' "$AMPLIFIER_SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/sign_update \
  --verify --ed-key-file - upgrade-qualification/feed/appcast.xml
python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path('upgrade-qualification')
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(root / 'feed/Amplifier-macOS.zip') == digest(Path('dist/Amplifier-macOS.zip'))
receipt = {
    'purpose': 'Initial signed upgrade qualification only; not a public installer',
    'candidate': json.loads(Path('dist/BUILD-INFO.json').read_text()),
    'sha256': {str(p.relative_to(root)): digest(p) for p in [
        root / 'baseline/Amplifier-upgrade-baseline.zip',
        root / 'feed/Amplifier-macOS.zip', root / 'feed/appcast.xml']},
}
(root / 'QUALIFICATION.json').write_text(json.dumps(receipt, indent=2) + '\n')
PY
