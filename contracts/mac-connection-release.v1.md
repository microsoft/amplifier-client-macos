# Mac connection and distribution — v1 (RATIFIED 2026-10-20)

Clause prefix: **MR**. Parent: [Mac vision](../docs/VISION.md).
Governs native connection storage, recovery controls and independently released
Mac packages; shared authority and receipt rules remain owned by Unified.

## Who builds against this

Mac transport, persistence and release maintainers; host integration reviewers.
Use the [compatibility record](../docs/compatibility.md) for the exact reviewed
pairing, observation, command and chat-link specifications.

## What it is

```text
Entered HTTPS host -> browser approval + comparison code -> restricted credential
  -> macOS Keychain -> native attachment -> bounded observation / explicit send
Local reply intent -> durable journal -> host receipt / saved uncertain intent
Signed candidate -> notarization / Gatekeeper / upgrade qualification -> release
```

## The promises

1. **MR1 — Protect the approved connection.** Use Unified's browser approval seam
   and macOS Keychain. Failed/cancelled approval preserves the saved connection;
   the disclosed manual-token fallback retains its broader authority.
   Broken: a credential enters a URL, log or preferences file, or a failed setup
   replaces the saved host. Affected: people connecting to their own host.

2. **MR2 — Save intent before delivery.** Implement CS1/4 and DC6 with the private
   journal before sending. A fresh explicit startup reply may wait up to 30 seconds
   for its exact endpoint and durable host; old uncertain replies require Retry.
   Broken: restart loses a reply or a callback silently sends it twice.
   Affected: people replying through notifications and unreliable networks.

3. **MR3 — Connection controls preserve work.** Disconnect persists a pause;
   Resume uses the saved credential. Confirmed Forget removes that local credential
   while retaining messages/preferences and explaining separate host revocation.
   Broken: Forget deletes a draft or connection changes retarget an in-flight send.
   Affected: people managing connected devices.

4. **MR4 — Updates are verifiable and local.** Use signed Sparkle archives and
   HTTPS feeds, notarized app distribution and standard installation UI. Preserve
   app identity, credentials, preferences and saved intent across qualified upgrades.
   Broken: an unverified update installs or client installation changes the host.
   Affected: recipients and host operators.

5. **MR5 — Lifecycle stays user controlled.** Login startup is opt-in through
   SMAppService and reflects actual OS state. Hiding Tempo follows DC5; Quit is a
   real quit. Updates respect the user's check/install choices.
   Broken: opening settings enables login startup or Quit starts a keep-alive loop.
   Affected: people controlling what runs on their Mac.

6. **MR6 — Release claims match evidence.** Follow CD3/5/6 with exact source,
   artifact and peer records. Separate native, synthetic and installed checks;
   retain unsupported cases and compatibility gaps in public release notes.
   Broken: a universal build is called physical Intel acceptance or a version
   label is treated as a tested host floor. Affected: recipients and maintainers.

## Not in v1

Host upgrades, automatic device execution grants, cross-host credentials,
Windows credential/update mechanisms, or comprehensive platform acceptance.
An unknown recovery outcome is not permission to replay work.

## How the kit checks it

Use core journal/transport checks, native login controls, publisher tests and
DJ3/5/6 on a Mac with isolated host state. Qualify the exact signed candidate,
Gatekeeper and a real signed upgrade, then verify anonymous downloads/feed.
The [assessment](../docs/contract-assessment.md) records evidence and remaining work.

## Open questions

Which oldest released host supports the full restricted-client path under test?
What additional recovery cases must be demonstrated before expanding preview claims?

## Changelog

| Date | Change | Basis |
| --- | --- | --- |
| 2026-10-20 | Name MR1–6 without changing transport, authority or release gates. | Product-owner approval to align existing connection/distribution requirements with shared contracts and evidence. |
