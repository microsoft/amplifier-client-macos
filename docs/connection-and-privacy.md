# Connection and privacy

Amplifier for Mac connects to the HTTPS origin you enter. Browser approval shows
a comparison code, requires host sign-in and issues a restricted chat credential.
The credential stays in macOS Keychain. The host stores a credential digest and
lets its owner revoke access at `/devices`. Request names are labels, not proof
of identity; compare the code and host before approving.

Restricted chat access includes reading chat activity/messages, creating managed
chats and sending messages across the host. It is not a per-chat access list.
It excludes host settings, approvals, arbitrary actions and device administration.
The optional manual-token fallback grants full host authority instead. Neither
connection method automatically grants browser or desktop control on this Mac.

Normal system certificate validation is enabled. HTTP is allowed only at loopback
for development. The app does not copy browser cookies, access CLI credentials,
collect analytics or send a Sparkle system profile. It checks the configured
host and, when enabled, the public update service. macOS handles notification
permission; notification content can be retained by macOS.

The private journal stores reply text, destination, command identities and local
notification deduplication. Response previews stay in app memory, although desktop
notifications can retain their own copies. A corrupt journal blocks sending to
avoid losing recovery identities. Saved or uncertain replies require explicit Retry.

## Disconnect and uninstall

Disconnect pauses the saved connection across restarts; Resume reconnects.
Forget removes the local host credential after confirmation and keeps saved
messages/preferences. Host revocation is separate: choose Manage connected devices.

To uninstall, disable Open Amplifier at login, revoke host access if desired,
Forget the local credential, quit Amplifier and remove Amplifier.app. Preferences
and saved messages remain in `~/Library/Application Support/Amplifier for Mac` and
the `com.microsoft.amplifier.macos` defaults domain. The application does not
remove host or CLI data. Full local-data removal is not currently an in-app action.
