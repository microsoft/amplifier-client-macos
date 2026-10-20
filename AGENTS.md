# Working on Amplifier for Mac

Read docs/VISION.md, contracts/README.md, docs/compatibility.md and
docs/contract-assessment.md before changing product behavior. Use
docs/architecture.md and docs/ux-contract.md for implementation detail. Amplifier
is the app; Tempo is its optional companion. Keep implemented behavior and future workspace/device capabilities clearly separated.

Run meaningful core/native checks for behavioral changes and release-tool tests
for packaging/publication changes. Native acceptance requires macOS; fixtures do
not establish focus, notifications, signing or update behavior. Use isolated,
synthetic host state for integration tests. Never restart or modify a user's
shared host to test this client.

This is public source. Do not include personal paths, machine names, account
identifiers, private chat content, screenshots, credentials or diagnostic dumps.
Use reserved example domains and synthetic fixtures. Preserve required license,
security, support and artwork attribution. Commit identity may use GitHub's
noreply address. Keep build outputs and signing materials outside Git.

Use pull requests and the canonical repository ruleset. Never bypass checks by
weakening protection or force-pushing main. Release only through the signed
workflow and its qualification gate. Clean owned temporary test resources after
preserving useful nonsecret evidence; do not touch another task's resources.

Keep MP/MR clause IDs stable and link work to the applicable promise and observable
failure. Shared DC/CX/CS rules stay in Unified; do not copy them into a platform
contract. Record reviewed revisions, affected consumers, compatibility and evidence
for shared changes. A new Windows client needs its own OS implementation and
qualification; Mac results do not establish Windows parity. Keep DRAFT proposals,
RATIFIED direction, implementation observations and actual release/adoption distinct.
