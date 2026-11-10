# Optional browser setup integration

Status: approved setup-only scope; implementation in review, not included in
released 0.1.0. The governing contract is [MB1–3](../contracts/mac-browser-setup.v1.md); existing MP/MR promises
remain unchanged. This is an optional route into host setup, not native execution.

## Journey and ownership

Settings → Connection → Browser access checks anonymous device discovery at the
entered address and opens `/connect` in the default external browser. Chat pairing
stays separate. No automatic discovery runs for chat-only users, and the address
draft is not saved as a side effect. The app neither receives execution credentials
nor enrolls a device. Closing Settings cancels a pending handoff.

Use the host setup page in the Edge/Chrome profile where the extension is installed.
If the default browser is different, open that same page in the intended profile;
the Mac app does not inspect profiles or copy browser cookies. Extension installation
and owner approval remain explicit. Opening the page is not evidence of enrollment.

The extension connects directly to Unified, independently of this app. This allows
a mobile chat to target an enrolled browser while the companion is hidden or absent.
The extension owns locally selected tabs, exact target revisions and immediate Stop;
the host owns separately revocable grants and task admission. Shared UI-use owns
decisions/providers. Neither Mac Quit nor chat Disconnect stops the extension.

## Reviewed peer and compatibility

Source-reviewed against Unified's proposed device integration at
`6ab3476a0` (`contracts/device-connections.v1.md`, `contracts/ui-use.v1.md`,
`amplifier_web/device_connections.py`, `device_connection_pages.py`, `auth.py`
and `device_client/`). This is a feature-branch protocol, not a released-host floor.

The handoff requires anonymous `GET /api/connections/v1`, protocolVersion 1,
outbound-poll transport, browser.observe support and the expected same-origin
enrollment/token/self endpoints. It then opens the fixed `/connect` route.
Additional discovery fields are ignored. HTTP redirects, unauthenticated HTML,
unsupported versions and invalid bodies fail closed. A missing feature reports
unavailable setup without changing chat access or escalating to a broader token.

The reviewed host preserves `/connect` through its login redirect in source.
Its extension distribution is currently a development preview requiring manual
installation. Public browser-control readiness needs reproducible dependencies,
bounded screenshot/observation handling, an appropriate extension distribution
path and matching host/extension qualification. The Mac button does not solve
those service-owned prerequisites.

## Focused implementation evidence

Mac revision `0b879a3a644654d721cc14fa4e1bdfe26b76689c` passed
[hosted macOS checks](https://github.com/microsoft/amplifier-client-macos/actions/runs/39716625596):
31 core tests, including four discovery tests; native editing/login/surface checks,
including setup target capture, chat preservation and cancellation; 11 publisher
tests; universal development packaging and artifact-transfer verification.
These are component and packaging checks, not physical browser-control acceptance.

## Qualification before broader claims

- Run core and native Settings checks and record the exact Mac revision and CI run.
- With an agreed synthetic target on an isolated host, verify default and alternate
  browser profiles, signed-out login returning to setup, explicit grants and local
  selection. Do not use private tabs or real account actions as test fixtures.
- From an ordinary chat, verify selected-tab operation, navigation invalidation,
  local Stop, revocation and no replay after sleep/network loss. Check that stopping
  or quitting the Mac app does not misrepresent the extension's separate state.
- Keep chat-only setup, notifications and connection recovery independent. Qualify
  the signed candidate separately before distributing a new Mac release.

## Native desktop remains future work

Browser access does not control native Mac apps or the desktop. That needs a
separately approved signed Mac executor using canonical computer-use, explicit
Accessibility/Screen Recording permissions, exact app/display targets, immediate
local Stop, bounded operations and unknown-effect recovery. Define ownership and
qualify sleep, reconnect, user takeover and permission revocation before shipping.
Native messaging, if adopted, needs signed helper packaging plus browser-specific
host registration and an explicit extension allowlist. None is installed here.
