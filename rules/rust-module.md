# Rust module rules (SpacetimeDB 2.14)

The reference implementation is `templates/server/rust-single/src/lib.rs`.

## Versions

- R1. `spacetimedb = "=2.14.0"`, pinned exactly. The toolchain is pinned with `rust-toolchain.toml` (1.97.1) and the
  `wasm32-unknown-unknown` target. `crate-type = ["cdylib"]`.
- R2. No `spacetimedb-sdk` in a module. That crate is the client SDK.

## Authority

- R3. The caller is `ctx.sender()`. Never authorize with an `Identity`, player id or name passed as an argument.
- R4. The module's own identity is `ctx.database_identity()`. `ctx.identity()` is deprecated.
- R5. Every scheduled reducer starts with `if ctx.sender() != ctx.database_identity() { return Err(..) }`.
- R6. Admin reducers start with `require_admin(ctx)?`. The admin identity lives in a table written at `init`, never in
  source.
- R7. Admission (if any) is checked in `client_connected` **and** in every player reducer.
- R8. IDC receivers allow-list sender database identities, including in `client_connected`.
- R31. No public reducer may end every session, wipe or reset the world, or trigger a module update (`module_update`,
  `kick_all`, `reset_world`, ...) for any caller. Gate it with `require_admin(ctx)?` (or `require_operator(ctx)?` from
  `recipes/operator-role.md` for delegated, non-destructive ops) and log who called it.

## Determinism

- R9. No `std::time`, `std::fs`, `std::net`, threads, `rand::thread_rng` or `getrandom`. Use `ctx.timestamp`,
  `ctx.random()` and `ctx.rng()`.
- R10. Never let `HashMap`/`HashSet` iteration order affect outcomes. Use `BTreeMap` or sort.
- R11. External I/O goes through `#[procedure]` (short HTTP via `ctx.http`, then `ctx.with_tx`) or a sidecar.

## Data

- R12. Every table has a `#[primary_key]`. Natural keys get `#[unique]`.
- R13. Every column used in `find`/`filter`, a subscription `WHERE` or a view gets an index.
- R14. Tables are private unless every row is safe for every client. Per-player data is exposed through views or
  visibility filters.
- R15. Hot state (per-tick) lives in narrow tables, separate from cold state. Write only on change.
- R16. Spatial tables carry AOI cell columns with a composite btree index.
- R17. Seed data comes from idempotent `ensure_*` reducers, not only `init` (which runs once).
- R18. Prefer additive schema changes. Destructive changes follow `skills/stdb-migration`.
- R29. On a world with players, new fields go in a **side table** keyed by the same id, not as a new column on an
  existing table. 2.13 refused new columns even with a default (field report). 2.14.0 accepts an appended
  `#[default]` column but disconnects every client (verified). New tables publish without a disconnect.
- R30. Prefer private tables plus `#[view]`s over `#[client_visibility_filter]` row-level security. In 2.14.0 RLS
  needs the crate's `unstable` feature, nested `IN (SELECT ...)` filters are refused at publish, and a JOIN-based filter
  makes client JOIN subscriptions on that table fail (verified). 2.10.1 had the same nested-`IN` refusal and broke live
  JOIN subscriptions (field report).

## Reducers

- R19. Return `Result<(), String>`. Validate every argument (bounds, `is_finite`, length in chars, charset) before
  writing.
- R20. Player-callable reducers do bounded work: no full scans of hot tables, and collections in arguments are
  length-capped.
- R21. Rate-limit writes per identity where abuse is possible (chat, crafting, building).
- R22. Updates go through a unique index: `ctx.db.t().id().update(Row { .., ..old })`.
- R23. Reducers invoked over HTTP, by other databases or by sidecars are idempotent (request or message ids).

## Tick

- R24. One fixed-rate tick via `scheduled(tick)` + `ScheduleAt::Interval`, created once in `ensure_world`.
- R25. The tick measures its own lateness into `tick_health` and sheds optional work at level >= 2.
- R26. No per-entity logging in the tick.

## Style

- R27. Keep game rules in plain functions that take values and return values, so they are testable. Reducers do
  validation, load, call rules, then store.
- R28. Comments explain *why*, especially for any deviation from these rules (mark it `// RULE-EXCEPTION Rn: reason`).
