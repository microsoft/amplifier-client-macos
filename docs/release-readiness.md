# Initial public release readiness

Status: public source initialized and development builds verified. Signed release
qualification remains pending. Do not advertise a download until its artifacts
exist and the matching release is qualified.

## Before first publication

- [x] Owner creates `microsoft/amplifier-client-macos` through the required process.
- [x] Initialize fresh source with canonical Microsoft templates, contributor/security
      guidance, maintainer-team ownership and default-branch protections.
- [x] Configure protected signing/public-release environments, a team release-review
      gate, read-only default workflow permissions and a disabled publication switch.
- [ ] Confirm release signing ownership and install credentials only through the
      approved GitHub environments. No personal credentials are copied in source.
- [ ] Configure the public Sparkle key and credentials, verify release tag controls,
      and enable publication only after qualification as described in releasing.md.
- [x] Pass hosted core, native, universal build and release-tooling checks.
- [ ] Sign/notarize/staple the exact candidate app and DMG; validate Gatekeeper.
- [ ] Fresh install: connect, revoke, reconnect, notification permission, actual
      notification icon, Reply and terminated-app Reply, saved-message recovery.
- [ ] Open chat: existing PWA/window reuse and correct chat, with no reload storm.
- [ ] Tempo: transparent scroll gaps, drag/edge margins, collapsed stack, semantic
      status colors and no focus theft during passive interaction.
- [ ] VoiceOver/keyboard, Reduce Motion/Transparency, light/dark appearance,
      multiple displays/Spaces, sleep/wake and longer network loss.
- [ ] Record idle CPU/memory and identify tested hardware. Do not equate universal
      compilation with physical Intel acceptance.
- [ ] Qualify signed update between two builds of the new app identity using an
      isolated test channel, then verify the exact public feed configuration.
- [ ] Review public docs/artwork attribution and verify an anonymous download.

## Evidence discipline

The initial source passed the GitHub macOS build with Xcode 26.3 and a separate
isolated Mac build with Xcode 27.1: 27 core tests, native checks, 11 publication
tests, universal compilation and development app/DMG/ZIP packaging. These builds
used ad-hoc signing; they do not qualify a Developer ID installer or signed updates.
Repository configuration was prepared against the Microsoft repository-audit
recipe; this is not a claim that the full recipe has been run.

Record exact source commit, artifact checksums, versions, platform, tested flows
and limits. Earlier component evidence informs the work; the new name, identity,
package layout and public workflow require their own acceptance. Native UI and
signed distribution checks must run on macOS. Synthetic publisher tests exercise
publication gates but do not validate Apple signing or real update installation.

Keep personal screenshots, chat content, private endpoints and signing evidence
outside the public source tree. Retain a short nonsecret release receipt with the
published source/artifacts. Unfinished acceptance is visible, not relabeled passed.
