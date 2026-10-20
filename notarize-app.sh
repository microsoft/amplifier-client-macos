#!/bin/bash
set -euo pipefail
tempo_app=$1
tempo_archive=$2
[[ -n "${AMPLIFIER_NOTARY_PROFILE:-}" ]] || { echo 'AMPLIFIER_NOTARY_PROFILE is required.' >&2; exit 1; }
tempo_notary_options=(--keychain-profile "$AMPLIFIER_NOTARY_PROFILE")
if [[ -n "${AMPLIFIER_SIGNING_KEYCHAIN:-}" ]]; then tempo_notary_options+=(--keychain "$AMPLIFIER_SIGNING_KEYCHAIN"); fi
tempo_submission=$(mktemp)
trap 'rm -f "$tempo_submission"' EXIT
# A rejected or timed-out submission fails the build; there is no unsigned fallback.
xcrun notarytool submit "$tempo_archive" "${tempo_notary_options[@]}" --wait --timeout 20m --output-format json > "$tempo_submission"
python3 - "$tempo_submission" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept this build for notarization. Inspect its notary submission log.')
print('Apple notarization accepted: ' + result['id'])
PY
xcrun stapler staple "$tempo_app"
xcrun stapler validate "$tempo_app"
spctl --assess --type execute --verbose=2 "$tempo_app"
# The distributed archive must contain the stapled app, not the earlier submission.
rm "$tempo_archive"
ditto -c -k --keepParent "$tempo_app" "$tempo_archive"
