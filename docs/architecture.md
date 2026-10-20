# Architecture

## Current client

The root Swift package has two targets. `ClientCore` owns endpoint validation,
restricted device pairing, compact host observation, URL routing and durable
reply intent. `AmplifierApp` owns AppKit, UserNotifications, Keychain, login
startup, Sparkle and the Tempo surfaces. The app does not embed an agent runtime.

`HostClient` uses the host's current HTTP API. It attaches a native client,
follows bounded companion/activity pagination and polls every five seconds.
Errors back off to sixty seconds; waking the Mac reconnects. Response previews
are bounded and requested when needed, not by loading the whole history.

The host owns canonical attention receipts and chat classification. Local
notification delivery deduplication is not another unread-state authority.
Commands capture their endpoint, durable host identity and chat before waiting.
The journal retains original command IDs before sending; reconnect never replays
old uncertain replies automatically. The host owns command admission and receipts.

`companion-v1` grants compact reads, bounded previews, managed-chat creation and
sending messages. It does not grant settings changes, approvals, arbitrary
filesystem access, device administration or local browser control. Native client
IDs are separate from credentials and are bound to the approving device.

## Local identity and storage

The app bundle and Keychain service use `com.microsoft.amplifier.macos`.
Preferences use the app's standard defaults domain. The owner-only journal is
`~/Library/Application Support/Amplifier for Mac/journal.json`. Keep these identities
stable after public release. Changing branding does not require changing storage.
No credential is placed in preferences, navigation URLs, release metadata or logs.

The official icon is compiled into the main app bundle; avatar artwork resides
in the generated `AmplifierMac_AmplifierApp.bundle`. Both are signed with the app.
Release signing includes nested Sparkle code before signing the containing app.

## Future workspace seam

The first integrated workspace can render the shared web client in a native
window. A single connection/navigation owner coordinates workspace, composer,
notifications and Tempo. An embedded page must not reach arbitrary native APIs:
allowlist app origins and bridge operations, bind requests to the current
navigation and capability grants, and reject untrusted frames/content. Define
web/native version negotiation, sign-in, downloads, file pickers and window reuse
before qualifying this as a complete client. None of that workspace bridge ships
in the initial companion-focused preview.

## Optional device seam

A future device capability can use an outbound authenticated channel, a signed
local helper and an explicitly enrolled browser extension. It needs separately
revocable execution grants, exact browser/profile/tab identity, local Stop/Take
over, bounded queues and honest unknown-effect recovery. Browser native messaging
is initiated by the extension; it is not a server-initiated connection to the Mac.
Shared UI-use owns task decisions and browser adapters; canonical computer-use
owns desktop fallback. See the roadmap; this is not implemented browser control.
