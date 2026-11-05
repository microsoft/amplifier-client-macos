# Avatar release candidate readiness

Proposed identity: **0.1.1 / build 2**. The tag remains uncreated until reviewed
main is frozen. Recheck availability before freezing; the browser-setup feature
is independently reviewed and is not included in this avatar change.

## Completed source and development checks

- 32 Swift core tests: existing protocol/navigation/recovery checks plus avatar
  state priority, host-read clearing, once-only reactions, host scoping, saved
  choice migration, suspension and bounded choreography.
- Universal arm64/x86_64 release compilation passed locally. Hosted packaging
  qualification remains separate.
- Existing native surface checks: settings selection, semantic status, panel
  behavior, first-click controls, drag/edge geometry and editing.
- 84 actual AppKit render combinations: six shapes × two finishes × seven states;
  transparent corners, eight palette loads and reaction continuity.
- All eight APNG loops decoded and drawn on an Apple-silicon Mac. Measured mean
  frame decode/draw cost was 0.79–1.04 ms at 192 pixels. This is an isolated
  component measurement, not whole-app energy usage or an Intel performance claim.
- Twelve Python release-tooling/asset checks: public publisher gates plus complete
  asset catalog, SHA-256 receipts, RGBA format, frame counts and loop timing.

Native checks used macOS 27.2 / Xcode 27.2 in an isolated build directory. No
installed app, host connection, preferences, pairing or private browser tab was
changed. Synthetic native render receipts contain only the avatar artwork.

## Publication gates still required

1. Exact public PR head passes hosted universal macOS build and normal independent
   code-owner review. Existing protections stay in place.
2. Reviewed main version/notes match a new immutable tag; the signed workflow
   builds the candidate. No feature-branch artifact is relabeled as that build.
3. Qualify that exact signed/notarized app and DMG: signature, Gatekeeper, version,
   feed, launch and upgrade from shipped 0.1.0 in an isolated installation that
   also isolates preferences. Preserve the user's running client.
4. Protected public-release approval publishes the same qualified artifacts;
   verify anonymous downloads, checksums and the signed update feed afterward.

Physical Intel, the complete VoiceOver/display/accessibility matrix, energy
measurement and sleep/wake acceptance remain unclaimed. The existing host
compatibility limits still apply. This feature introduces no service dependency.
