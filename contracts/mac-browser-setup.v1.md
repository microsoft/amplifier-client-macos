# Optional browser setup — v1 (RATIFIED 2026-10-21)

Clause prefix: **MB**. Parent: [Mac vision](../docs/VISION.md).
This contract governs only a setup handoff. Shared device authorization,
execution, Stop and UI-use decisions belong to Unified and its browser extension.
It does not establish native Mac execution or alter the released chat contract.

## Who builds against this

Mac Settings maintainers and host/device integration reviewers. Windows can use
the same host setup seam but must qualify its own browser launcher and lifecycle.

## The promises

1. **MB1 — Setup is explicit and separate.** Only choosing Browser access in
   Connection settings makes anonymous discovery at the entered host. Opening
   Settings, connecting chat and starting the app never enroll execution.
   Broken: chat setup silently grants browser access or starts device polling.

2. **MB2 — Preserve the destination and chat connection.** Capture the entered
   address, accept supported discovery, and open only that origin's `/connect`.
   Do not send chat credentials/cookies, follow discovery redirects or accept
   arbitrary navigation URLs from discovery. Unsupported or failed setup leaves
   chat credentials, saved address and replies unchanged. Closing Settings cancels
   pending activation. Broken: setup retargets a connection or leaks credentials.

3. **MB3 — Authority and lifecycle stay visible.** The external browser performs
   owner approval; its extension owns local target selection and immediate Stop.
   Setup grants nothing by itself. Mac Quit, Hide and chat Disconnect do not stop
   a separately running extension. Explain this boundary rather than presenting
   a native Stop that cannot enforce it. Broken: people believe quitting the
   companion stops an independently enrolled browser.

## Checks and limits

Core discovery tests cover missing/invalid capabilities, anonymous requests and
same-origin navigation. Native Settings checks cover explicit invocation, captured
address, no connection mutation and cancellation. These do not qualify a real
browser profile, extension installation, login, execution, sleep/reconnect or Stop.
See [integration scope and qualification](../docs/browser-setup.md).

## Not in v1

Automatic extension installation, native messaging registration, execution tokens
in the Mac app, a second device poller, OS permission requests, desktop control,
model selection, an agent loop, arbitrary CDP or shell operations.

## Changelog

| Date | Change | Basis |
| --- | --- | --- |
| 2026-10-21 | Ratify MB1–3 for optional setup handoff, independent extension enrollment and unchanged chat authority. | Product-owner agreement to browser-only scope; native Mac-app/desktop execution remains unavailable. |
