# Security and playtests

Reporting policy: [SECURITY.md](../../SECURITY.md). Before external exposure, use [stdb-security-review](../../skills/stdb-security-review/SKILL.md) and record a dated review for the candidate.

## Authority

Derive players from `ctx.sender()`. Validate prices, damage, positions, ownership, permissions, sequence and idempotency inside reducers. Client timestamps/positions are not authoritative. Admin reducers may take target identities but must authorize callers separately.

Scheduled entry points require `ctx.sender() == ctx.database_identity()`. Cross-database receivers need peer authorization and idempotency; a database caller is not automatically a trusted player/operator. Use deterministic module timestamps/randomness. Move network/files/heavy work outside reducers and validate results.

## Visibility and sessions

Public means every row is acceptable to every subscriber. The movement reference publishes saved positions and operator identity; assess that against your game. AOI optimizes delivery and does not prevent queries of other public cells. Hide sensitive state with private tables and authorized projections/views.

Development admission opens by default. Revocation need not close a live socket, so recheck admission on every protected reducer and test existing connections. Protect persisted tokens; test same-token reconnect and define multiple-connection semantics.

## Operations

Review input size, rate/retention limits, tick costs, subscription volume, migrations and restore procedures. Tick health signals pressure but enforces no entity budget. Protect seed/reset tools and operator identities. Choose transport/access controls for your host and verify its licensed production topology.

Scanners and smoke tests supplement authority review; they do not certify security or legal compliance.
