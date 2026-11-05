# Mac experience — v1 (RATIFIED 2026-10-20)

Clause prefix: **MP**. Parent: [Mac vision](../docs/VISION.md).
Names the existing approved Mac presentation promises; implementation evidence
and unverified cases live in the [assessment](../docs/contract-assessment.md).

## Who builds against this

Mac UI maintainers and native acceptance reviewers. Shared desktop meaning belongs
to DC/CX/CS at the [reviewed Unified revision](../docs/compatibility.md), including
attention, focus, exact-chat navigation, authority and reply recovery.

## What it is

Amplifier is the application; Tempo is its optional floating companion.
The [interaction guide](../docs/ux-contract.md) specifies the platform details
under these promises. It is not a second shared desktop contract.

```text
Amplifier.app
  Workspace -> existing browser/PWA (preview)
  Quick interaction -> menu bar / notification reply / composer
  Tempo -> avatar / status pill / collapsed or expanded notices
  Settings -> appearance / notifications / connection
```

## The promises

1. **MP1 — Native interaction stays native.** Apply DC3 and CX6/8 using ordinary
   window levels, native editing/keyboard behavior and nonactivating companion
   panels. System materials adapt to the OS and accessibility settings.
   Broken: settings floats above unrelated apps or dragging steals typing.
   Affected: people using the Mac alongside their other work.

2. **MP2 — Appearance is a direct choice.** Expose six shapes, eight swatches and
   Clear/Dark finishes; one choice updates all previews immediately and persists.
   The six are Relay, Accord, d20, Crest, Meter and Clippy; retired Arc/Chord
   choices migrate to d20/Accord without changing other preferences.
   Default to blue Relay/Clear with a visible, accessible selection.
   Broken: changing color needs a second menu or changes only one preview.
   Affected: people personalizing the companion.

3. **MP3 — Attention has quiet surfaces.** Apply DC1/2 through a numberless menu
   badge, exact attention counts inside the app, and semantic status independent
   of avatar palette. The host feed, not delivery history, determines updates.
   State-specific light and motion remain consistent across finishes/palettes.
   Completion/error reactions play once per observed event, then ongoing work
   resumes its animation without clearing unread/error indicators. Offline and
   Reduce Motion remain still; animation never marks an update read.
   Notice symbols retain the sidebar's work/unread/question/error meanings.
   A local dismissal does not acknowledge host attention. Dismissed work stays
   hidden until its known execution state changes, not on each progress refresh.
   Broken: working alone increments attention or a palette disguises an error.
   Affected: people deciding what needs review.

4. **MP4 — Notices remain compact and usable.** Support collapsed reveals and
   explicit expansion/collapse; drag from notices and capture wheel input across
   transparent list gaps without visible scrollbars. Keep screen margins and
   close avatar spacing. Updates preserve the reader's row and scroll offset.
   Dragging the expanded header resizes the list: full extent follows content
   up to the screen boundary; dragging shorter remembers a height cap. Both
   modes shrink to fit fewer items. Show public action detail on one truncated
   line, with model waits labeled “Thinking…”. Broken: an update resets scrolling,
   scrolling gaps moves the app behind Tempo,
   or an opaque rectangle fills the notice list. Affected: companion users.

5. **MP5 — Handoffs respect installed identity.** Apply DC4 through an origin/scope
   matched browser/PWA opener. Honor explicit app-profile binding; never discover
   a destination by copying cookies or scanning private profiles.
   Broken: a notification targets another profile or repeatedly opens windows.
   Affected: people with several browser profiles or hosts.

## Not in v1

An embedded workspace, Safari discovery, Windows widgets or device execution.
Promote these only through their own approved boundary and acceptance work.
Mac material choices and badge geometry do not prescribe another platform's UI.

## How the kit checks it

Map MP1–5 to [DJ1–DJ7](../docs/compatibility.md#shared-contract-baseline).
Use native surface/editing checks and actual Mac interaction, including passive
focus, bright/dark backgrounds, keyboard/VoiceOver, reduced motion/transparency,
multiple displays and real warm/cold navigation. Record missing coverage.

## Open questions

Which physical accessibility/display combinations become the next qualified set?
What browser handoff coverage is needed before adding another supported browser?

## Changelog

| Date | Change | Basis |
| --- | --- | --- |
| 2026-11-05 | Extend MP3/4 with stable scrolling, resize/fit semantics, local dismissal and sidebar-style status/action detail. | Product-owner request; shared attention authority remains unchanged. |
| 2026-10-20 | Give existing Mac UX requirements MP1–5; delegate shared meanings to DC/CX/CS. | Product-owner approval of contract alignment; preserves the existing interaction guide and separates future Windows implementation. |
