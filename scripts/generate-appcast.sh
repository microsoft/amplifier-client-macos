#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${AMPLIFIER_UPDATE_FEED_URL:?Update feed URL required}"
: "${AMPLIFIER_UPDATE_PUBLIC_KEY:?Public update key required}"
: "${AMPLIFIER_UPDATE_DOWNLOAD_PREFIX:?Version-specific download URL prefix required}"
: "${AMPLIFIER_SPARKLE_PRIVATE_KEY:?Private update signing key required}"
# Input validation runs before passing a URL to the feed generator.
python3 - <<'PY'
import os
from urllib.parse import urlsplit
url = urlsplit(os.environ['AMPLIFIER_UPDATE_DOWNLOAD_PREFIX'])
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
    raise SystemExit('Update download prefix must be a credential-free HTTPS URL')
PY
printf '%s' "$AMPLIFIER_SPARKLE_PRIVATE_KEY" | swift scripts/verify-update-key.swift
# Only the archive belongs in Sparkle's source directory; metadata is not an update.
tempo_feed_dir=$(mktemp -d)
trap 'rm -rf "$tempo_feed_dir"' EXIT
cp dist/Amplifier-macOS.zip "$tempo_feed_dir/"
cp RELEASE_NOTES.md "$tempo_feed_dir/Amplifier-macOS.md"
printf '%s' "$AMPLIFIER_SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --ed-key-file - --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "$AMPLIFIER_UPDATE_DOWNLOAD_PREFIX" -o "$tempo_feed_dir/appcast.xml" "$tempo_feed_dir"
# A missing signature is a publication failure, not an unsigned fallback.
python3 - "$tempo_feed_dir/appcast.xml" <<'PY'
from pathlib import Path
import sys, xml.etree.ElementTree as ET
path = Path(sys.argv[1]); text = path.read_text()
root = ET.fromstring(text)
enclosures = root.findall('./channel/item/enclosure')
if len(enclosures) != 1 or not enclosures[0].get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'):
    raise SystemExit('Appcast is missing its signed update enclosure')
PY
printf '%s' "$AMPLIFIER_SPARKLE_PRIVATE_KEY" | .build/artifacts/sparkle/Sparkle/bin/sign_update \
  --verify --ed-key-file - "$tempo_feed_dir/appcast.xml"
cp "$tempo_feed_dir/appcast.xml" dist/appcast.xml
