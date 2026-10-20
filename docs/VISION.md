# Amplifier for Mac — product vision

Direction adopted for public-project preparation on 2026-10-20. This document
separates the intended product from the current preview's implemented behavior.

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

## Product promise

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

## Design principles

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

The shared family direction and contracts remain owned by
[Amplifier Unified](https://github.com/microsoft/amplifier-unified/tree/main/contracts).
The current HTTP adapter is not an assertion of completed AHP/ACP adoption.
