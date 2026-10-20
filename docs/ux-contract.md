# Amplifier for Mac interaction contract

Amplifier for Mac follows the shared [client experience contract](https://github.com/microsoft/amplifier-unified/blob/main/contracts/client-experience.v1.md), including CX8: UX is like golf. Minimize the strokes to achieve a result without overwhelming the interface.

Tempo is the optional desktop companion. Application settings, connections,
notifications and updates belong to Amplifier. Hiding Tempo preserves those
services; quitting Amplifier stops the client.

## Direct choices

- Expose the eight color swatches and the Clear / Dark avatar finishes. Each selection takes one action from Appearance, applies immediately to every preview and the avatar, and retains a visible and accessible selected state. Clear is the default; the interface itself follows macOS appearance.
- Keep six shapes in a three-by-two grid: Relay, Accord, Arc, Crest, Chord, Meter. New installations use blue Relay.
- Apply reversible preferences immediately. Connection fields remain drafts until Connect; credentials and external effects do not gain automatic submission merely to save a click.
- Use disclosure for large chat lists and uncommon diagnostics. Count complete journeys, including opening menus and saving; compare clarity and keyboard use as well as pointer actions.

## Native materials and controls

Use standard platform components in their intended context, built with the current SDK. A native glass API is not a reason to apply glass to every control. Let the OS own focus, pressed/disabled states, dimensions, adaptive appearance and accessibility. Prefer system layout metrics and constraints over fixed frames. Apple's [adoption guide](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) is the implementation baseline.

Liquid Glass is the elevated control/navigation layer. Settings content, grouped rows and avatar previews use standard content surfaces. Do not put a separate glass background behind every field, group or gallery item, and do not stack glass controls inside another glass surface. Within a shared glass container use the native contained-control treatment or a thin selection overlay. This follows [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).

Choose regular adaptive glass for Tempo's text-heavy floating UI over arbitrary desktops. Apple's clear material is intended for media backgrounds with controlled legibility; it is unrelated to our Clear / Dark avatar artwork. Label that preference **Avatar finish** and default to Clear. Do not let it override the application's system appearance or material settings.

Use color selectively for status, selection and important actions. Keep the artwork and swatches colorful, but avoid large accent-filled backgrounds competing across the gallery, finish control and navigation. Selection must also have a non-color cue. See [Color](https://developer.apple.com/design/human-interface-guidelines/color) and [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles).

## Settings structure

For Tempo's three peer panes, prefer a persistent, noncustomizable native settings toolbar: Appearance, Notifications, Connection. Indicate selection, restore the last pane and update the window title to that pane. Retain Command-Comma, ordinary window level, and disabled minimize/maximize controls. Apple's [Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings) describes this pattern; the system-wide Settings application's large category sidebar is not a template every small app needs to copy. AppKit's [toolbar tab style](https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabstyle-swift.enum/toolbar) supports this without replacing the application framework.

Use a native single-selection segmented control for Clear / Dark. Keep eight directly selectable swatches with names, keyboard access and a visible selected mark, plus the six-avatar three-by-two gallery with a restrained selection outline/check. All remain one-action preferences. Use ordinary native field editors, appropriate switches/checkboxes and a standard Connect action within grouped content. [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) group closely related alternatives and communicate selection.

For floating companion surfaces, retain a single coherent glass treatment for each functional group. The composer and capsule can share glass behind their contained controls. A notice panel should keep its readable list content distinct from its elevated controls. Collapsed-stack reveals must not create nested full glass effects. This is Tempo's application of the layering guidance, not an Apple-prescribed companion layout.

## Attention and work

The menu bar contains the Amplifier logo and an optional flat 10-point blue attention badge at the lower-right, never a number. Keep the logo a system-tinted template. Apple’s [menu-bar guidance](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) recommends adaptive symbols/icons but does not prescribe badge geometry; the marker follows neighboring status badges without a success checkmark. Work alone does not add that badge. Your chats and its rows distinguish updates, working, and simultaneous work plus updates with status symbols and descriptions. Exact attention counts remain inside the menu and companion; they do not count ongoing work. Animation supplements static meaning and stops for Reduce Motion, hidden or offline surfaces.

Unread state belongs to the host's canonical attention receipts, shared with the
sidebar. A response clears after its latest content is actually visible in a focused
chat; opening a link alone never acknowledges it. Tempo reconciles that feed on
its next poll (normally within five seconds). The local delivery ledger only avoids
repeating desktop notifications; it is not a separate unread list. A chat with both
an update and ongoing work gets one update card; after review, ongoing work may
remain without an attention badge.

The resting pill uses semantic colors independent of avatar shape, palette and
finish: red for an unread session error, blue for other updates to review, teal
for work alone, gray for idle and amber for disconnection, in that priority order.
Status descriptions and animation retain meaning without color; Reduce Motion
removes animation.

Avatar, pill and notice panels must not become key/main windows. Hovering,
clicking controls, expanding/collapsing, scrolling and dragging leave the previous
application's keyboard focus intact. Chat navigation deliberately focuses Amplifier;
opening the composer or Settings deliberately enables keyboard input. Do not repair
focus afterward by reactivating a remembered app: avoid stealing it initially.

## Acceptance

Verify actual native controls on a Mac, not just static artwork. Choosing a color or glass finish from Appearance is one action (previously opening a menu plus choosing). Selecting a shape is one action. Check all swatches, both finishes and six avatars, persisted selection, keyboard focus, readable system appearance and selected-state feedback. Exercise active/inactive windows, bright and dark desktop backgrounds, system Liquid Glass preferences, accent colors, Reduce Transparency, Increase Contrast, Reduce Motion, keyboard navigation and VoiceOver. Native defaults help but do not prove that custom elements pass these checks. Validate no badge for work alone, an attention badge with no digits, and separate/combined chat status. Document any extra step whose clarity or authorization benefit warrants it.

## Opening Amplifier

Double-clicking the avatar and Open Amplifier activate/reopen the installed app,
without navigating its current page. Chat links carry only the selected chat ID
and reuse the PWA through its launch handler. Match installation metadata by origin
and scope, never just the application name.

Chromium app launches can silently target the wrong profile after switching browser
profiles. Honor an explicit per-app profile binding, then a profile declared in the
launcher metadata, otherwise leave selection to the browser. Never assume every
installation uses Default, scan private browser profiles, or copy account data.
The uncommon override lives under Advanced → Browser profile, is scoped to the
exact installed app identity, persists across restarts, and can be cleared. This
extra setup step is justified only for ambiguous multi-profile installations; routine
notification opening remains one click. A successful OS launch callback is not proof
of chat selection: qualify real navigation, foregrounding and window reuse on a Mac.

## Login startup

Notifications settings exposes **Open Amplifier at login** as a native switch. Use Apple's
`SMAppService.mainApp` registration on supported macOS versions. Startup is opt-in;
opening Settings or starting Tempo must not register it. Read actual system state
when Settings opens and when the app becomes active, so a change in macOS Settings
wins over any old UI state. Pending OS approval must be labeled and offer a direct
link to Login Items. Registration failures remain visible and never masquerade as
success. Turning this off unregisters future login launches without quitting Tempo.
Quit remains a real quit; this is not a keep-alive service or crash restart loop.

## Connection approval and updates

The primary connection action opens browser approval for the entered host and
shows the comparison code in Tempo. The user signs into that host and explicitly
approves restricted chat access. Store only the issued credential in Keychain;
never copy browser cookies, reveal host control tokens, or send credentials in
navigation URLs. Cancellation, denial, expiry and an unsupported older host keep
the existing saved connection. Retain manual access tokens behind disclosure for
older hosts and migration; those tokens still grant full host authority.

Use Sparkle's standard update UI and verified installer instead of a custom
replacement helper. Let users choose automatic checks and when to install/relaunch.
Update archives and feeds must be signed; the configured feed uses HTTPS and
contains no credentials. Preserve bundle identity, settings, Keychain and pending
messages. An unconfigured preview offers the authenticated downloads page and
never claims automatic updates are active. GitHub credentials must not be bundled
in the application or published feed.

## Recovery and connection controls

The resting status pill is one native regular Liquid Glass surface on macOS 26+,
with a restrained semantic tint; older systems use native material. Keep its full
click/drag target and nonactivating behavior. Do not layer another glass control
inside it or tie the status tint to the avatar palette.

A fresh explicit notification reply is saved before delivery and may wait up to
30 seconds for the exact saved endpoint and durable host identity to connect.
Timeout, pause, changed endpoint or changed host leaves it saved. Reconnection
and repeated notification callbacks never automatically resend old messages.
Review is read-only; Retry is explicit and retains the original command identity.

Disconnect pauses the saved connection across restarts. Resume uses its saved
credential. Forget requires confirmation naming the saved host, deletes only its
local Keychain credential, and preserves messages and preferences. Explain that
host revocation is separate. Refuse connection changes while a message is being
sent or awaiting startup delivery; never silently retarget a pending message.
