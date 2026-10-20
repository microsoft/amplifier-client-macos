#!/bin/bash
# Package a stapled app for Finder installation; Sparkle continues to use the ZIP.
set -euo pipefail
cd "$(dirname "$0")/.."
tempo_stage=$(mktemp -d)
trap 'rm -rf "$tempo_stage"' EXIT
ditto 'dist/Amplifier.app' "$tempo_stage/Amplifier.app"
ln -s /Applications "$tempo_stage/Applications"
cp Install.txt "$tempo_stage/Install.txt"
tempo_dmg="$PWD/dist/Amplifier-macOS.dmg"
hdiutil create -volname 'Amplifier for Mac' -srcfolder "$tempo_stage" -format UDZO -ov "$tempo_dmg"
if [[ "${AMPLIFIER_REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
    [[ -n "${AMPLIFIER_SIGNING_IDENTITY:-}" && "$AMPLIFIER_SIGNING_IDENTITY" != '-' ]] || { echo 'Developer ID is required for a release disk image.' >&2; exit 1; }
    tempo_sign_options=(--sign "$AMPLIFIER_SIGNING_IDENTITY" --timestamp)
    if [[ -n "${AMPLIFIER_SIGNING_KEYCHAIN:-}" ]]; then tempo_sign_options+=(--keychain "$AMPLIFIER_SIGNING_KEYCHAIN"); fi
    codesign "${tempo_sign_options[@]}" "$tempo_dmg"
    tempo_notary_options=(--keychain-profile "${AMPLIFIER_NOTARY_PROFILE:?Notary profile required}")
    if [[ -n "${AMPLIFIER_SIGNING_KEYCHAIN:-}" ]]; then tempo_notary_options+=(--keychain "$AMPLIFIER_SIGNING_KEYCHAIN"); fi
    xcrun notarytool submit "$tempo_dmg" "${tempo_notary_options[@]}" --wait --timeout 20m --output-format json > "$tempo_stage/notary.json"
    python3 - "$tempo_stage/notary.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept the disk image. Inspect its submission log; do not publish.')
print('Disk image notarization accepted: ' + result['id'])
PY
    xcrun stapler staple "$tempo_dmg"
    xcrun stapler validate "$tempo_dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$tempo_dmg"
fi
