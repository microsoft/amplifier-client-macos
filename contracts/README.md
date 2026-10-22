# Contract index

The [vision](../docs/VISION.md) defines the destination. Contracts define
observable promises. The [assessment](../docs/contract-assessment.md) compares
those promises with specific evidence and derives remaining work.

| Owner | Document | Boundary |
| --- | --- | --- |
| Unified | DC, CX, CS, CD at the [reviewed baseline](../docs/compatibility.md#shared-contract-baseline) | Shared desktop experience, common action meanings, host/client state and change discipline |
| Mac client | [MP1–5: Mac experience](mac-experience.v1.md) | Native controls, appearance, attention presentation, notice interaction and browser adapter |
| Mac client | [MR1–6: connection and distribution](mac-connection-release.v1.md) | OS credentials, private reply journal, connection controls, login, signing and updates |
| Mac client (DRAFT) | [MB1–3: optional browser setup](mac-browser-setup.v1.md) | Explicit external-browser handoff; no native execution authority |

[DJ1–DJ7](../docs/compatibility.md#shared-contract-baseline) are the shared
desktop acceptance journeys, reusable by the future Windows client. macOS
materials, Keychain, SMAppService, Sparkle, window APIs and badge geometry are
Mac implementations, not Windows requirements.

The [interaction guide](../docs/ux-contract.md), architecture and privacy guide
explain the implementation. They do not create competing shared semantics.

These contracts record approved existing requirements as RATIFIED. A proposed
new promise is DRAFT until approved. Ratified does not mean implemented or tested.
Keep clause IDs stable; reference rather than restate a promise owned elsewhere.
Record changes with their basis and affected consumers. Method provenance and
its deliberately limited adoption are in [compatibility](../docs/compatibility.md#method-sources-reviewed).
