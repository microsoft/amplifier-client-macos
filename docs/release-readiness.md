# Initial public release readiness

Status: the initial preview's signed distribution and new app identity are
qualified. Broader interaction and hardware coverage remains explicitly tracked
below. Do not describe this early preview as comprehensive platform acceptance.

## Initial preview distribution gate

- [x] Owner creates `microsoft/amplifier-client-macos` through the required process.
- [x] Initialize fresh source with canonical Microsoft templates, contributor/security
      guidance, maintainer-team ownership and default-branch protections.
- [x] Configure protected signing/public-release environments, a team release-review
      gate, read-only default workflow permissions and a disabled publication switch.
- [x] Confirm release signing ownership and install credentials only through the
      approved GitHub environments. No personal credentials are copied in source.
- [x] Configure a separate public Sparkle key and protected credentials, protect
      version tags, and require environment approval before publication.
- [x] Pass hosted core, native, universal build and release-tooling checks.
- [x] Sign/notarize/staple the exact candidate app and DMG; validate Gatekeeper.
- [x] Exercise the new identity: browser-approved connection, synthetic quick-chat
      delivery, notification permission and actual icon, disconnect/resume,
      host-side revocation and local credential removal.
- [x] Qualify signed update between two builds of the new app identity using an
      isolated test channel, then verify the exact public feed configuration.
- [x] Review public docs, artwork attribution and privacy.
- [ ] Verify anonymous release downloads and the published feed after publication.

## Remaining preview acceptance

- [ ] Fresh end-to-end native Reply, terminated-app Reply and saved-message
      recovery with nonempty uncertain messages.
- [ ] Fresh new-identity PWA navigation/window-reuse qualification. The opener's
      component checks and earlier live behavior evidence remain applicable.
- [ ] Repeat the full physical Tempo interaction matrix across system appearances.
      Core/native checks cover controls, layout and nonactivating panel policy;
      earlier physical behavior checks do not replace every new-device scenario.
- [ ] VoiceOver/keyboard matrix, Reduce Motion/Transparency, multiple displays,
      Spaces, sleep/wake and longer network loss.
- [ ] Sustained idle CPU/memory measurement and physical Intel acceptance.

These are visible limits of the early preview, not passed checks. The public
release notes retain them so distribution qualification is not mistaken for
complete behavioral or hardware coverage.

## Evidence discipline

The initial source passed the GitHub macOS build with Xcode 26.3 and a separate
isolated Mac build with Xcode 27.1: 27 core tests, native checks, 11 publication
tests, universal compilation and development app/DMG/ZIP packaging. These builds
used ad-hoc signing; they do not qualify a Developer ID installer or signed updates.
Repository configuration was prepared against the Microsoft repository-audit
recipe; this is not a claim that the full recipe has been run.

The subsequent signed release run qualified version 0.1.0, build 1, source
`22acd60acf4c3a46ab55b00a6f0ffa5b5d01a394`. Apple accepted the app and DMG;
the downloaded app passed signature, stapling and Gatekeeper checks on
macOS 27.0.1 / Apple silicon. Sparkle installed the exact candidate ZIP over a
separately signed/notarized 0.0.0 test fixture. Connection and appearance
preferences, client identity and an accepted synthetic command receipt survived.
The fixture's loopback feed was an argument-only override; the installed bundle
retains the production HTTPS feed. Private acceptance screenshots and account
details are intentionally excluded from this repository.

Record exact source commit, artifact checksums, versions, platform, tested flows
and limits. Earlier component evidence informs the work; the new name, identity,
package layout and public workflow require their own acceptance. Native UI and
signed distribution checks must run on macOS. Synthetic publisher tests exercise
publication gates but do not validate Apple signing or real update installation.

Keep personal screenshots, chat content, private endpoints and signing evidence
outside the public source tree. Retain a short nonsecret release receipt with the
published source/artifacts. Unfinished acceptance is visible, not relabeled passed.
