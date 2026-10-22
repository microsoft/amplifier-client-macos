# Mac contract assessment and work derived from gaps

Assessment date: 2026-10-20. This is evidence, not a new promise or a blanket pass.
Use the [compatibility record](compatibility.md) for source/peer limits and
[release readiness](release-readiness.md) for the signed candidate record.

## Evidence keys

- **E1 — Source/component:** public 0.1.0 source
  `22acd60acf4c3a46ab55b00a6f0ffa5b5d01a394`; 27
  [core checks](../Tests/ClientCoreTests/ClientCoreTests.swift), native
  [editing](../Checks/main.swift), [login](../Checks/Login/main.swift) and
  [surface](../Checks/Surface/main.swift) checks; 11
  [publisher tests](../scripts/test_public_release.py).
- **E2 — Signed distribution:** [release run](https://github.com/microsoft/amplifier-client-macos/actions/runs/39472243127)
  and [0.1.0 artifacts](https://github.com/microsoft/amplifier-client-macos/releases/tag/v0.1.0);
  app/DMG notarization, Gatekeeper, real Sparkle upgrade from separately signed
  0.0.0 fixture to exact candidate, then anonymous published downloads/feed.
- **E3 — Physical Mac / synthetic host:** same candidate on macOS 27.0.1/arm64;
  browser-approved pairing, new/existing quick chat, notification permission and
  actual icon, disconnect/resume, revoke/Forget. Explicit canonical `attention.read`
  cleared the update summary. Navigation alone did not clear the fixture's manual
  unread marker; no new end-to-end latest-response read claim is made.
- **E4 — Earlier behavior:** earlier physical companion focus/PWA checks informed
  this implementation. They are not a repeat on the new public identity and do
  not close the gaps below. Private screenshots/accounts are not published.

E1–E3 are summarized in the public release receipt; account-specific raw evidence
remains private. The signed upgrade preserved an accepted synthetic command
receipt, not a nonempty uncertain-reply scenario. Universal compilation is not
physical Intel evidence. No runtime test was repeated for this documentation edit.

## Promise-to-evidence map

“Kept (bounded)” applies only to the named observation. “Can't check fully”
means evidence exists but the complete promise has not been qualified.
“Not yet” describes an unimplemented future slice. None is an aggregate platform
conformance score.

| Clause | Shared journey / dependency | Observation and verdict | Remaining work |
| --- | --- | --- | --- |
| MP1 | DJ4/7; DC3, CX6/8 | Can't check fully: E1 native editing/non-key panel policy; E4 physical focus | MAC1, MAC3 |
| MP2 | DJ7; CX8 | Can't check fully: E1 gallery/finish/swatch controls and E2 persisted preferences | MAC3: full keyboard/assistive-technology and appearance matrix |
| MP3 | DJ1/7; DC1/2 | Kept (bounded): E1 classification/status checks, E3 explicit canonical receipt cleared summary; full read journey can't check | MAC2, MAC3 |
| MP4 | DJ4/7; DC3, CX8 | Can't check fully: E1 surface checks; not a new full physical scrolling/edge/drag run | MAC3 |
| MP5 | DJ2; DC4 | Can't check fully: E1 origin/scope/profile and encoded URL checks; E4 earlier warm navigation | MAC1 |
| MR1 | DJ5; CS1/8 | Kept (bounded): E1 unsupported-host/redirect/scope checks; E3 approval, revoke and Forget | MAC4: released-host matrix and additional pending-admission revocation |
| MR2 | DJ3; DC6, CS1/4 | Can't check fully: E1 restart/identity/callback cases and E3 quick-chat delivery | MAC1: cold native Reply and uncertain saved-message recovery |
| MR3 | DJ5/6; CS1/4 | Kept (bounded): E3 disconnect/resume/revoke/Forget; source guards in-flight changes | MAC1, MAC4: delayed-send/connection-change races |
| MR4 | DJ6; CD3/6 | Kept (bounded): E2 exact signed installation/upgrade and published feed; E3 preferences/accepted receipt retained | MAC1: nonempty uncertain journal through upgrade; new signing identity requires fresh qualification |
| MR5 | DJ6; DC5 | Can't check fully: E1 login checks and lifecycle source; no full physical wake/OS-approval run | MAC3 |
| MR6 | All; CD3/5/6 | Kept (bounded): source/artifact receipt and explicit limits published; host floor remains unqualified | MAC4; refresh this record for each changed peer or release scope |

## Gap-derived work

| Item / owner | Source clauses | Acceptance and evidence required |
| --- | --- | --- |
| MAC1 — Mac integration maintainer | MP1/5, MR2/3/4; DJ2/3/4/6 | Exact public-identity cold notification Reply, repeated callback, offline/restart/uncertain intent and signed upgrade; warm/cold PWA navigation with window counts, preserved document/drafts, exact target and foreground result |
| MAC2 — Mac + host integration maintainers | MP3; DC1, DJ1 | Real completion event followed by focused/latest-content reading in web clears the same desktop fingerprint within its five-second normal poll bound; separate working-only and unread/error cases |
| MAC3 — Mac UI maintainer | MP1–4, MR5; DJ4/6/7 | Physical keyboard/VoiceOver, appearances, reduced motion/transparency, bright backgrounds, screen margins, transparent gap scrolling, Spaces/multiple displays and sleep/network recovery; record platform matrix and failures |
| MAC4 — Host + Mac integration maintainers | MR1/3/6; CD3, DJ5/6 | Pristine released-host matrix with exact source/package versions, supported capabilities, old-host pairing absence, protocol rejection, revocation races and pagination; establish the minimum only after testing |
| MAC5 — Mac release maintainer | MR4/6 | Physical Intel and sustained idle CPU/memory measurements with workload/duration; retain unmeasured cases rather than extrapolating from compilation |

These are remaining preview acceptance tasks, not newly imposed exhaustive release
gates. Existing [release policy](releasing.md) remains unchanged. Implementation
fixes need targeted checks; changed readiness claims need matching evidence.

## Future direction, separate from preview defects

The proposed [MB1–3 browser setup handoff](browser-setup.md) adds source/core and
native-harness checks, with execution and physical-browser qualification pending.
It grants no device authority and does not close the future execution gap below.

Embedded workspace, additional OS capabilities and device execution are **Not yet**.
They follow [the roadmap](roadmap.md) and shared DSK4/5, with approved bridge/grant
boundaries before implementation. Windows follows shared DSK3 and must produce
its own platform contracts and DJ1–DJ7 evidence; Mac results are not Windows passes.

## Updating the record

For a shared change, name the clause, affected host/client consumers and exact
reviewed revisions before implementation. Update the relevant evidence row after
checks, retaining failed/skipped observations and the resulting work item.
Keep identifiers stable; do not renumber an established clause to reuse its meaning.
Version/adoption and deployment remain separate from merging documentation.
