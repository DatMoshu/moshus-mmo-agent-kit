# TypeScript module rules (SpacetimeDB 2.14)

The reference is `templates/server/ts-single` (same game as the Rust template). The API reference is
`skills/vendor/official/typescript-server/SKILL.md`.

- T1. The `spacetimedb` package is pinned to the `stdb.lock` version, never a caret range for production.
- T2. Import builders from `spacetimedb/server` (runtime classes such as `ScheduleAt` from `spacetimedb`). Define tables
  with `table({ name, public }, { ...columns })` and export one `schema({...})` as default. The `ctx.db`
  accessors are the keys you pass to `schema`.
- T3. The caller is `ctx.sender` (a property in TypeScript). Reject with `throw new SenderError('...')`. Never take
  an identity argument for authorization.
- T4. Determinism: no `Date.now()`, `new Date()`, `Math.random()`, `fetch`, timers or `async` reducers. Use
  `ctx.timestamp` and `ctx.random`. HTTP goes through procedures (`ctx.http`) or a sidecar.
- T5. Never cast strings to `Identity`. Identities come from `ctx.sender` or `t.identity()` columns.
- T6. The scheduled tick checks that the sender is the module itself before doing work.
- T7. Every filtered column has an index (`.index('btree')` or a named `indexes` entry). Every table has a
  `.primaryKey()` column.
- T8. Use `bigint` for u64/i64 columns and timestamps. Don't mix with `number` arithmetic.
- T9. The AOI, hot/cold, validation, rate-limit and idempotency rules from `rust-module.md` (R12-R26) apply unchanged.
