#!/bin/bash
# Sign nested executable code inside-out; never use --deep to sign.
set -euo pipefail
tempo_app=$1
tempo_identity=${AMPLIFIER_SIGNING_IDENTITY:--}
tempo_options=(--timestamp=none)
if [[ "$tempo_identity" != - ]]; then
  [[ "$tempo_identity" == "Developer ID Application:"* ]] || { echo 'Distribution requires a Developer ID Application identity.' >&2; exit 1; }
  tempo_options=(--options runtime --timestamp)
fi
if [[ "${AMPLIFIER_REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
  [[ "$tempo_identity" != - && -n "${AMPLIFIER_NOTARY_PROFILE:-}" ]] || { echo 'Signed release requires Developer ID and a notary profile.' >&2; exit 1; }
fi
tempo_framework="$tempo_app/Contents/Frameworks/Sparkle.framework"
for tempo_part in "$tempo_framework/Versions/B/XPCServices/Downloader.xpc" \
                  "$tempo_framework/Versions/B/XPCServices/Installer.xpc" \
                  "$tempo_framework/Versions/B/Updater.app" \
                  "$tempo_framework/Versions/B/Autoupdate" \
                  "$tempo_framework" "$tempo_app"; do
  [[ -e "$tempo_part" ]] || { echo "Missing required code: $tempo_part" >&2; exit 1; }
  codesign --force "${tempo_options[@]}" --sign "$tempo_identity" "$tempo_part"
done
codesign --verify --deep --strict "$tempo_app"
