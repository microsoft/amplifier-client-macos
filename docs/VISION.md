# Amplifier for Mac — Vision (RATIFIED 2026-10-20)

This is the approved destination, not a claim of completed implementation.
The [contracts](../contracts/README.md) hold observable promises; the
[assessment](contract-assessment.md) records evidence and work derived from gaps.
Amend the direction before implementing a change to its meaning. Publication
and ratification do not establish native acceptance or deployed adoption.

## Identity

- Product: **Amplifier for Mac**.
- Installed application: **Amplifier.app**; system display name: **Amplifier**.
- Optional floating companion: **Tempo**.
- Repository and public releases: `microsoft/amplifier-client-macos`.
- Initial public version: `0.1.0`; bundle ID: `com.microsoft.amplifier.macos`.

Tempo names a way of interacting with Amplifier. Notifications, settings,
connection management and updates belong to the application. Hiding Tempo does
not disconnect the host or turn off notifications. Quitting Amplifier ends all
of this client's connections.

## What Amplifier for Mac is

Reach the same continuing work from a Mac window, a quick interaction, or a quiet
companion. Native interaction respects the person using the computer: ordinary
keyboard conventions, deliberate focus changes, accessible controls, appropriate
materials and clear permission boundaries.

The three experiences share one connection and navigation authority:

1. **Workspace:** full conversations, projects, artifacts and settings in an
   ordinary application window. Planned; the preview opens the existing web UI.
2. **Quick interaction:** menu bar, notifications, inline replies and a compact
   composer. Implemented; additional shortcuts and system integrations can follow.
3. **Tempo:** optional desktop artwork and attention surfaces. Implemented; never
   required to use the rest of the application.

## Evolution

Begin the full workspace with a native shell around the shared web client,
retaining feature coverage. Adopt native views where they improve a real user
journey. The rendering technology is an implementation choice; shared meaning,
state and behavior are the product commitment.

A workspace web view uses an intentional sign-in flow and a narrow, versioned
native bridge restricted to trusted application content. External websites do
not inherit native privileges. Opening a notification reuses the intended
workspace and chat; it must not create duplicate windows or restart the host.

Optional browser/device execution, voice and other OS capabilities require
explicit target identity, permissions, cancellation and recovery. They are
separate from permission to observe and reply to chats. The host owns accepted
work; shared providers/UI-use own models and task decisions. Tempo contains no
second agent runtime or provider configuration authority.

## Principles

- Minimize the actions needed to achieve a result without overwhelming the UI.
  Meaningful authorization and account selection justify an extra step.
- Keep the current application's focus during passive companion interaction.
- Use platform controls and materials in their intended context; native glass
  is not a reason to make every content surface translucent.
- Share attention and conversation state with the host; retain drafts and
  presentation state locally.
- Distinguish saved, admitted, running, completed and unknown outcomes.
- Keep the client optional and independently releasable. Installing it never
  silently adopts a new host release or enables local device control.

## What this deliberately resists

- A second runtime, model-selection authority or authoritative unread store.
- A companion that steals focus or becomes mandatory for ordinary work.
- Identical Mac and Windows widgets mistaken for a consistent experience.
- Chat permission silently growing into local browser or desktop control.
- Source tests or approved direction presented as complete device qualification.

## How you can tell it is working

- A person chooses 1 swatch and every avatar preview updates without a Save action.
- A person drags or collapses Tempo and types in their previous app with 0 refocus clicks.
- A person reads 1 latest response in a focused workspace and sees its desktop
  attention clear on the next successful poll, normally within 5 seconds.
- A person opens 2 updates into a supported warm workspace and gets 0 extra windows.
- A person restarts with 1 uncertain reply and causes 0 automatic resends.
- A recipient installs 1 signed update while retaining their connection and saved input.
- A Windows maintainer can trace 1 shared journey to its host contract without
  adopting a Mac framework or inventing a second definition of its status.

These are observable targets. The assessment determines which have evidence;
future Windows or embedded-workspace delivery is not implied.

## Shared ownership

Unified owns shared client and desktop promises; Mac owns platform presentation,
OS integration and distribution. Use the [reviewed contract baseline](compatibility.md),
not a copied shared specification. The current HTTP adapter is not completed
AHP/ACP adoption. A planned Windows client consumes the same shared journeys and
keeps its own platform vision, contracts and qualification evidence.

## Changelog

| Date | Change | Basis |
| --- | --- | --- |
| 2026-10-20 | Adopt Amplifier for Mac identity, workspace/quick interaction/optional Tempo direction. | Product-owner approval of public-project recommendations. |
| 2026-10-20 | Name document state, link stable contracts/evidence, add observable targets and Windows boundary. | Product-owner approval of methodology alignment; no new runtime or release claim. |
