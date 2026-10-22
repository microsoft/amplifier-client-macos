# Contract and host compatibility record

This is a reviewed-input and qualification record, not a compatibility claim
about every newer host. [MR6](../contracts/mac-connection-release.v1.md) and
Unified CD3/5/6 govern how it changes.

## Shared contract baseline

Reviewed Unified baseline: `b9e114244380295821a5faa29c9c9512c8dc3365`.
The coordinated documentation revision below adds desktop consumers/DC without
changing wire fields or runtime behavior:
`03d698ed5a86cd78213f90a725d95fb52ca5087d`.

| Promise / specification | Exact reviewed source |
| --- | --- |
| Shared-client destination | [Vision](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/docs/clients/VISION.md) |
| Common experience and interaction economy | [CX1–8](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/contracts/client-experience.v1.md) |
| State, authority and recovery | [CS1–8](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/contracts/client-state.v1.md) |
| Desktop behavior | [DC1–6](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/contracts/desktop-client.v1.md) |
| Ownership and change discipline | [CD1–6](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/contracts/client-development.v1.md) |
| Shared desktop journeys and planned Windows consumer | [DJ1–DJ7 / DSK1–5](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/docs/clients/desktop-clients.md) |
| Browser approval and credential scope | [Native pairing](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/docs/clients/native-pairing.md) |
| Bounded observation and attention | [Observations](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/docs/clients/observations.md) |
| Current commands and receipts | [Live sessions](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/docs/clients/live-sessions.md) |
| Exact-chat navigation | [Chat links](https://github.com/microsoft/amplifier-unified/blob/03d698ed5a86cd78213f90a725d95fb52ca5087d/docs/clients/chat-links.md) |

Review this record when shared contracts or public APIs change. A pin identifies
what was read; it does not freeze supported hosts, claim runtime acceptance of that
commit, or permit ignoring later security/behavior changes. Before merging a
consumer change, confirm the referenced shared documentation has been integrated.

## Released client and tested peer

| Item | Evidence / limit |
| --- | --- |
| Public client | 0.1.0, build 1, source `22acd60acf4c3a46ab55b00a6f0ffa5b5d01a394` |
| Native acceptance | macOS 27.0.1 / Apple silicon; signed distribution and synthetic integration described in [release readiness](release-readiness.md) |
| Host fixture lineage | Owned synthetic fixture with tracked pairing changes through `2e63792063c1a3cd6ae46d8d150b64584c14cd4b`; integrated upstream as `a360a5626c851a50187c14fc7ec849d453c0a76f` in [PR #813](https://github.com/microsoft/amplifier-unified/pull/813) |
| Host qualification limit | Fixture used an editable source overlay, not a pristine released artifact. A complete immutable fixture-tree digest was not retained; this lineage is not exact released-host certification. |
| Oldest compatible release | **Not yet qualified.** Do not infer it from the fixture version label or merge date. |
| Latest released host | No fresh 0.1.0/live-host matrix established by this documentation change. |
| Protocol | Current HTTP native attachment and companion adapter, `protocolVersion:1`; restricted credentials use `companion-v1` |
| Target AHP/ACP | Architectural destination; not implemented transport in 0.1.0 |
| Windows | Planned consumer of shared contracts; no implementation or qualification supplied by Mac results |

## Required behavior and fallback

| Surface | Client dependency | Unsupported / recovery behavior |
| --- | --- | --- |
| Browser approval | Pairing endpoints and restricted `companion-v1` token | Unsupported, denied or expired pairing leaves the saved connection intact. Manual token is explicit, disclosed full host authority; it is not automatic escalation. |
| Attachment and reads | Native attachment, protocol version 1, bounded companion/activity pagination | Reject mismatched protocol and invalid/repeated cursors; do not turn an incomplete traversal into a complete attention baseline. |
| Quick chat and replies | Managed creation, conversation send, durable command receipts and host identity | Preserve uncertain intent; explicit Retry uses the captured destination and original identity. No automatic downgrade to another operation. |
| Navigation | Exact host-local chat URL; supported installed-browser launch behavior | Other browsers retain ordinary URL navigation. A successful OS launch callback alone is not proof of target/window reuse. |
| Agent-created classification | Host observation metadata | Absent metadata is unknown, not permission to guess from titles. Existing pinned/followed policy remains explicit. |

The current adapter is documented as temporary by Unified. A future adapter
change needs its own capability/version and peer qualification; neither a Windows
implementation nor a new protocol should inherit Mac compatibility by assumption.

## Method sources reviewed

The proposed optional [browser setup handoff](browser-setup.md) has a separate
device-v1 feature-branch dependency and qualification record. It does not change
the released companion-v1 chat protocol or establish a minimum released host.

- Converge family: `c63f1e6bea6d93e5ffb86b0e3dbcc698391cbe9c`,
  [format rationale](https://github.com/microsoft/amplifier-converge/blob/c63f1e6bea6d93e5ffb86b0e3dbcc698391cbe9c/docs/FORMAT.md).
- Converge Method: `86b9a4a457df22c48b80a4c423b3e421dd309292`,
  [documents](https://github.com/microsoft/amplifier-converge-method/blob/86b9a4a457df22c48b80a4c423b3e421dd309292/contracts/documents.v1.md)
  and [settling](https://github.com/microsoft/amplifier-converge-method/blob/86b9a4a457df22c48b80a4c423b3e421dd309292/contracts/settling.v1.md).

We apply explicit direction/state, stable observable clauses, one home per rule,
and gap-derived work with evidence. As in Unified's adopted method, this does not
import Converge's formal ledger service, session topology or exact line budgets.
Future changes to the product promise require approval before implementation.
This packet records previously approved behavior; it does not certify compliance
with the whole Converge kit or ratify future device capabilities.
