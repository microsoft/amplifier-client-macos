#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin ]] || { echo 'Build this app on macOS.' >&2; exit 1; }
swift test
# Test keyboard routing without reading or changing the system clipboard.
tempo_check_dir=$(mktemp -d)
trap 'rm -rf "$tempo_check_dir"' EXIT
swiftc Sources/AmplifierApp/LoginItemController.swift Checks/Login/main.swift -o "$tempo_check_dir/login-check"
"$tempo_check_dir/login-check"
swiftc Sources/AmplifierApp/EditingWindow.swift Checks/main.swift -o "$tempo_check_dir/editing-check"
"$tempo_check_dir/editing-check"
swiftc Sources/AmplifierApp/LoginItemController.swift Sources/AmplifierApp/AvatarAppearance.swift Sources/AmplifierApp/TempoInteraction.swift Sources/AmplifierApp/SettingsWindow.swift Sources/AmplifierApp/TempoSurface.swift Sources/AmplifierApp/TempoBubbles.swift Sources/AmplifierApp/TempoComposer.swift Sources/AmplifierApp/EditingWindow.swift Checks/Surface/main.swift -o "$tempo_check_dir/surface-check"
"$tempo_check_dir/surface-check"
swift build -c release --arch arm64 --arch x86_64
companion_bin_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
companion_app="$PWD/dist/Amplifier.app"
rm -rf "$companion_app"
mkdir -p "$companion_app/Contents/MacOS" "$companion_app/Contents/Resources"
cp "$companion_bin_dir/Amplifier" "$companion_app/Contents/MacOS/"
cp Info.plist "$companion_app/Contents/Info.plist"
# Notification Center needs the main bundle's compiled app icon catalog as well
# as the legacy ICNS fallback. Both are derived from the official artwork.
python3 scripts/package-app-icon.py "$companion_app" Assets/Amplifier.icns
python3 configure-updates.py "$companion_app/Contents/Info.plist"
mkdir -p "$companion_app/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$companion_app/Contents/Frameworks/Sparkle.framework"
# SwiftPM's generated Bundle.module accessor looks beside the executable or
# under Bundle.main.resourceURL. Preserve its resource bundle name.
cp -R "$companion_bin_dir/AmplifierMac_AmplifierApp.bundle" "$companion_app/Contents/Resources/"
# Record the source, not build-machine paths or local configuration.
python3 - <<'METADATA'
import json, plistlib, subprocess
from pathlib import Path
info = plistlib.loads(Path('Info.plist').read_bytes())
metadata = {
    'product': 'Amplifier for Mac',
    'bundleIdentifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'sourceRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'architectures': ['arm64', 'x86_64'],
    'notarizationRequired': __import__('os').environ.get('AMPLIFIER_REQUIRE_NOTARIZATION') == '1',
    'diskImageNotarizationRequired': __import__('os').environ.get('AMPLIFIER_REQUIRE_NOTARIZATION') == '1',
    'updateFeed': __import__('os').environ.get('AMPLIFIER_UPDATE_FEED_URL') or None,
}
Path('dist/BUILD-INFO.json').write_text(json.dumps(metadata, indent=2) + '\n')
METADATA
cp "$PWD/dist/BUILD-INFO.json" "$companion_app/Contents/Resources/"
tempo_archs=$(lipo -archs "$companion_app/Contents/MacOS/Amplifier")
[[ " $tempo_archs " == *" arm64 "* && " $tempo_archs " == *" x86_64 "* ]] || { echo "Missing universal architecture." >&2; exit 1; }
bash sign-app.sh "$companion_app"
ditto -c -k --keepParent "$companion_app" "$PWD/dist/Amplifier-macOS.zip"
if [[ "${AMPLIFIER_REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
    bash notarize-app.sh "$companion_app" "$PWD/dist/Amplifier-macOS.zip"
fi
bash scripts/package-dmg.sh
(cd dist && shasum -a 256 Amplifier-macOS.zip Amplifier-macOS.dmg > SHA256SUMS)
echo "Built: $companion_app"
echo 'Check BUILD-INFO.json and release notes for distribution qualification.'
