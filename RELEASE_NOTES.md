# Amplifier for Mac 0.1.8

Choose when Tempo's notices appear in Settings → Tempo: **Visible**, **Hidden**,
or **On hover**. The avatar keeps showing activity and attention in all three.

- Hover reveals the saved collapsed or expanded view. Move onto its cards to
  interact; leaving tucks it away with a short grace period for crossing the gap.
- Dragging and resizing keep the list available. Hover-out/in retains its scroll
  position, height and grouping. Collapsed/expanded choice now survives restart.
- Explicit Show/Hide and Escape remain available. In hover mode they affect the
  current visit without changing the saved mode.
- Ongoing-work inclusion is independent of visibility. Visible mode also shows
  available unread-only updates. The default remains Visible.

No host update, browser permission or attention acknowledgement is introduced.
Existing connections, saved replies, notification permissions and avatar settings
are preserved. Core/native checks and actual synthetic Mac pointer acceptance
cover the changed behavior, including unchanged foreground focus. Signed app/DMG
and upgrade qualification precede publication; a full VoiceOver/display matrix
remains separate coverage.

## Previous release: 0.1.7

Tempo's scrolling notice list softly fades clipped cards at the top and bottom
instead of ending with a hard visual cut. Only edges with more content fade;
complete first/last cards and lists that fit remain fully visible. The header
stays crisp, and transparent gaps and faded edges continue to accept scrolling.

This is native presentation polish. Service connections, ordering/grouping,
attention, saved list height, avatar settings and replies are preserved. No
server update is required. Native scroll/end/fit-all checks and synthetic glass
window capture qualify the changed surface; signed app/DMG and upgrade checks
precede publication. Manual VoiceOver and the full display matrix remain
separate coverage.

## Previous release: 0.1.6

Tempo's expanded activity list stays directly above the avatar when resized or
moved toward the top of a display. It reduces the scroll viewport instead of
jumping below or covering the avatar, then restores the saved height when space
returns. Fit-all and a manually chosen height cap remain intact.

- Notices sort across services by default: requests for input and errors, unread
  updates, then ongoing work.
- Settings → Tempo adds **Group by service** to apply that order within each
  service, and **Show service headings** for optional labels and separators.
- Group headings do not count as updates or change chat/dismiss targets. Changing
  grouping preserves the visible card and scroll offset.
- The ongoing-work toggle now lives in Settings → Tempo alongside these options.

Connections, credentials, avatar choices and saved replies are preserved. No
server update is required. Core/native checks cover sorting, fractional display
coordinates, resize/drag limits, recovery of saved height and grouped scrolling.
Signed app/DMG and upgrade qualification precede publication; manual VoiceOver
and the full physical display matrix remain separate coverage.

## Previous release: 0.1.5

Connect Amplifier for Mac to multiple Amplifier Unified services and see their
chat activity together in Tempo.

- Add and name services in Settings, choose a default, and pause, resume or forget
  each connection independently. Each service requires its own browser approval.
- Chat menus and activity cards identify their service. One unavailable service
  does not interrupt the others.
- Replies and saved drafts retain their original service and chat destination,
  even when the default changes or a connection is unavailable.
- Existing single-service connections and preferences migrate automatically;
  credentials remain in Keychain.

No server upgrade is required. Browser execution and PWA auto-hide are not added
by this release. Core and native component checks cover connection isolation,
request cancellation, destination capture and Settings interaction. Signed app,
DMG and upgrade qualification precede publication; manual VoiceOver and physical
Intel coverage remain separate.

## Previous release: 0.1.4

Tempo's activity cards show clearer action details and make better use of their space.

- App controls show the available action, such as window focus, instead of only
  the tool name. File operations and other tools use readable labels and selected
  host-provided hints; raw commands, prompts and result bodies stay out of cards.
- Response snippets remove Markdown formatting. Detail gets its own wider line,
  independent of the title, status icon and dismiss control.
- Overlapping tools retain useful activity with a compact additional-tool count.
  A chat with an unread answer and ongoing work shows its current action alongside
  the unread cue instead of presenting the older answer as current work.

Existing connections, settings, avatars and saved replies are preserved. Older
hosts without action hints keep readable fallback labels. No server upgrade is
required. Core/native checks and universal compilation precede signed app/DMG
and upgrade qualification; manual VoiceOver and physical Intel remain separate
coverage. PWA auto-hide is not included.

## Previous release: 0.1.3

Tempo’s expanded notices keep your reading position as activity updates arrive.

- Drag the top bar to resize the list. At full extent it follows the contents up
  to the screen edge; drag shorter to remember a maximum height. It always
  shrinks when fewer cards remain.
- Dismiss cards directly. Working cards return when their activity changes;
  dismissing a card does not mark the chat read or clear its host attention badge.
- Sidebar-style status icons make activity easier to recognize. Model waits read
  “Thinking…”; other work shows the available public action label and summary.
- Transparent scrolling gaps, screen margins and nonactivating controls remain.

The existing connection, preferences, avatars and saved messages are preserved.
PWA auto-hide is not included in this update. Native component and universal
build checks pass; signed app/DMG and upgrade qualification precede publication.
Manual VoiceOver, physical Intel and the full multi-display matrix remain
follow-up coverage, not claims made by this release.

## Previous release: 0.1.2

Tempo resumes its working animation after a completion or error reaction when
other chats are still working. Unread updates and errors keep their indicators;
they no longer leave the avatar static while the status pill shows activity.
Reactions still play once per event, and Reduce Motion and hidden/offline
animation suspension remain intact. Applies to all six shapes and both finishes.

## Previous release: 0.1.1

Tempo has a refreshed family of six crystal avatars: Relay, Accord, d20, Crest,
Meter and a Clippy tribute. Each has Clear and Dark artwork, eight color choices,
and lights and motion designed for working, idle, response ready, needs input,
error, connecting and offline states.

- Relay's circulating lights, Accord's column pulses, d20's rotating glow,
  Crest's flexing light paths, Meter's varied EQ rhythm and Clippy's attentive
  expressions give each shape its own character.
- Completion and error reactions settle after playing once. Ordinary host
  refreshes do not restart them, and reading a chat clears attention when the
  host reports it as read.
- Reduce Motion uses a stable pose; hidden and offline companions suspend
  animation. Status colors continue to mean the same thing in every palette.
- Existing Arc/Fold choices become d20; Chord becomes Accord. Other appearance
  settings, connections and saved messages are preserved.

Requires an existing compatible Amplifier Unified host and macOS 13 or later.
The workspace opens in a browser or installed web app. This update does not add
browser execution or native desktop control.

Source and native component qualification are recorded in
[the avatar release readiness record](docs/avatar-release-readiness.md).
Signed-candidate installation and upgrade qualification must complete before
this release is published. A development build is not the public installer.
