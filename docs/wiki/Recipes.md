# Extension recipes

The [recipe index](../../recipes/README.md) contains focused examples. Read the complete recipe and schema before copying a snippet; a compiled example is not a full subsystem.

| Goal | Recipe | Validation to add |
|---|---|---|
| Feature workflow | [Add a feature](../../recipes/add-a-feature.md) | Behavior-specific positive/negative cases |
| Reduce delivered rows | [AOI](../../recipes/aoi-subscriptions.md) | Own-transform bootstrap, cell crossing, subscription removal |
| Chat | [Chat](../../recipes/chat.md) | Sender authority, size limits, visibility |
| Atomic exchanges | [Inventory/trades](../../recipes/inventory-and-trades.md) | Ownership, balance, rollback |
| Repeatable requests | [Idempotency](../../recipes/idempotent-requests.md) | Duplicate operation gives one outcome |
| Operator authority | [Operator role](../../recipes/operator-role.md) | Ordinary caller rejected |
| Private playtest | [Admission](../../recipes/invite-only-playtest.md) | Revocation on existing connection |
| Follow region ownership | [Handoff client](../../recipes/region-handoff-client.md) | Same identity, activation, both directions |
| External NPC work | [Sidecar brain](../../recipes/sidecar-npc-brain.md) | Server validation and yielding under load |

For tile content use [the adapter contract](../SHARD_CORE.md). Validate a world document before mutation, seed through operator reducers, and separate presentation from server collision data. The synthetic fixture avoids proprietary installations/assets.

Identify new tables, indexes, subscriptions, reducers and bindings. Keep hot rows narrow and I/O outside reducers. Validate sidecar results on the server. Bound work and retained history explicitly: chat logs and idempotency receipts grow without a retention policy.

Run feature tests and [module gates](Testing.md). Historical snippet compilation in [VERIFICATION.md](../VERIFICATION.md) is narrower than a complete game test. Preserve provenance for external material.
