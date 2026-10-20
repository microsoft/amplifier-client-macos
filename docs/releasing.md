# Releasing Amplifier for Mac

Public source and release assets share `microsoft/amplifier-client-macos`.
The app is `Amplifier.app`, bundle ID `com.microsoft.amplifier.macos`. Downloads
are `Amplifier-macOS.dmg` (installation) and `Amplifier-macOS.zip` (Sparkle).

## Repository setup

Use the Microsoft Amplifier repo-audit recipe's canonical boilerplate and ruleset.
Issues are centralized by repository policy; Wiki and Projects are disabled.
Main requires PR review, stale-review dismissal, code-owner review, resolved
threads and linear history. Admin/Amplifier maintainer bypass is limited to PR
merges, never direct pushes. Keep the secret-scanning and push-protection features
provided by the organization enabled.

`checks.yml` builds ad-hoc development artifacts on PRs/main with read-only token
permissions and no release secrets. Every action is pinned to a commit. It runs
release-tool tests, core tests, native interaction checks and the universal build.

Set up the `signing` and `public-release` GitHub environments with the release
owner. Restrict deployments to main and configure required reviewers on
`public-release`. Leave repository variable `AMPLIFIER_PUBLIC_RELEASES` false
until real release acceptance and the review gate are ready. No release is
published merely by pushing source or a tag.

## Signing environment

Configure these secrets in the `signing` environment through approved secure
channels, never source files, issues, PRs or command transcripts:

| Secret | Value |
| --- | --- |
| `AMPLIFIER_CERTIFICATE_P12` | Base64 Developer ID Application identity export |
| `AMPLIFIER_CERTIFICATE_PASSWORD` | Export password |
| `AMPLIFIER_NOTARY_KEY_P8` | App Store Connect notarization API private key |
| `AMPLIFIER_SPARKLE_PRIVATE_KEY` | Base64 Ed25519 update signing seed |

Configure environment variables `AMPLIFIER_SIGNING_IDENTITY`,
`AMPLIFIER_NOTARY_KEY_ID`, `AMPLIFIER_NOTARY_ISSUER_ID` and
`AMPLIFIER_UPDATE_PUBLIC_KEY`. Only the last is embedded in the app. The release
owner must approve signing ownership before the first public installer.

The signing helper imports credentials into a disposable CI keychain, removes
transfer files, and restores the previous keychain list on cleanup. Signing
walks nested Sparkle code inside-out, uses hardened runtime and timestamps, and
verifies the complete bundle. App and DMG notarization, stapling and Gatekeeper
checks fail closed. A timed-out or rejected submission requires inspection;
never silently publish an unsigned fallback or blindly resubmit a rejection.

## Candidate and publication

1. Complete the applicable [release-readiness checks](release-readiness.md).
2. Update `Info.plist` version/build and `RELEASE_NOTES.md` through a PR. Builds
   increase monotonically after the first public release. Merge to main.
3. Create the matching version tag, such as `v0.1.0`, on the intended main commit.
4. Run **Signed release** from main with that existing tag. `publish=false`
   produces a signed candidate artifact without a GitHub release. For an intended
   publication run, use `publish=true`; it will wait at the protected
   `public-release` environment after the build.
5. Download that run's `Amplifier-macOS-signed` artifact. Qualify the exact app/DMG
   and signed feed before approving publication for that same run. A rebuilt
   candidate is a new artifact requiring its own verification.
6. Approve the protected publication job only after qualification. It uses the
   repository-scoped `GITHUB_TOKEN`; no cross-repository publishing token is needed.
7. Verify anonymous download, checksums and the installed update configuration.

The workflow validates the tag/version and that its commit belongs to main,
then builds that exact revision. The publisher rechecks the public tag against
build metadata, product/bundle identity, version/build, checksums and appcast.
It refuses an existing release or a backward build. It uploads the five allowed
assets to a draft and only then makes the release latest. Never replace assets
in a published release; make a new version. A failed draft needs deliberate
inspection/cleanup before retrying publication.

The public feed is:
`https://github.com/microsoft/amplifier-client-macos/releases/latest/download/appcast.xml`.
Archive URLs are version-specific under `/releases/download/vX.Y.Z/`.
Sparkle verifies signed feeds and archives before extraction; users choose when
to install. The public key is checked against the signing seed before generation.
Unconfigured development builds never claim an automatic update channel exists.

## Evidence and privacy

Record source revision, version/build, architectures and checksums in public
release metadata. Do not include workstation paths/names, local usernames,
host addresses, chat content, signing credentials or private diagnostic logs.
Native screenshots and signing investigations stay in private acceptance storage.
Apple signing necessarily identifies the approved publisher; review that identity
before release. The initial identity's signed-upgrade gate concerns future public
updates and does not require migration from development apps.

Run `python3 -m unittest discover -s scripts -p 'test_*.py'` for synthetic
publication checks. They do not prove signing, notarization, installation or
update acceptance. Real-device evidence must name the tested limitations.
