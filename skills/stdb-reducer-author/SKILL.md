---
name: stdb-reducer-author
description: Write correct SpacetimeDB 2.14 Rust reducers with authority checks, input validation, deterministic logic and rollback. Use for any reducer you add or change.
---

# Reducer authoring (Rust, 2.14)

## Shape

```rust
use spacetimedb::{reducer, ReducerContext, Table};

#[reducer]
pub fn rename(ctx: &ReducerContext, name: String) -> Result<(), String> {
    require_admitted(ctx)?;                                   // 1. admission, every reducer
    let name = validate_name(&name)?;                         // 2. validate and bound inputs
    let me = ctx.db.player().identity().find(ctx.sender())    // 3. authority is ctx.sender()
        .ok_or("join first")?;
    if ctx.db.player().name().find(&name).is_some() {         // 4. invariants via indexes
        return Err("name taken".into());
    }
    ctx.db.player().identity().update(Player { name, ..me }); // 5. writes last
    Ok(())                                                    // Err anywhere = full rollback
}
```

## Rules

- **The caller is `ctx.sender()`.** Never accept an `Identity` or player id argument for authorization. Admin powers
  check `ctx.sender()` against an admin identity stored in a table at `init`.
- **Lifecycle reducers:** `#[reducer(init)]`, `#[reducer(client_connected)]`, `#[reducer(client_disconnected)]`.
  `client_connected` returning `Err` rejects the connection.
- **Module identity:** `ctx.database_identity()`. `ctx.identity()` is deprecated in 2.14.
- **Determinism:**
  - Time is `ctx.timestamp`.
  - Randomness is `ctx.random::<T>()` or `ctx.rng()` with `use spacetimedb::rand::Rng`.
  - No `std::time`, no `rand::thread_rng`, no file or network I/O.
  - Never let HashMap iteration order decide an outcome.
- **Updates go through a unique index:** `ctx.db.t().id().update(Row { field, ..old })`. Insert returns the row (with
  `auto_inc` filled in).
- **Imports:** `use spacetimedb::Table;` is needed for `insert`, `iter` and `count` on table handles.
- **Bounded work:** no unbounded `iter()` over a hot table in a player reducer. Index or paginate instead.
- **Logging:** `log::info!` sparingly. Never per entity per tick.
- **Idempotency:** reducers triggered over HTTP or by other databases must dedupe by a request or message id. Since
  2.13, a 504 means the outcome is unknown.

## Validation checklist

- Strings: trim, then check the length in chars, then the charset.
- Numbers: check range, reject NaN for floats (`v.is_finite()`), and clamp directions to -1..=1.
- Rates: cap per-identity actions with a `last_action_at` column, compared to `ctx.timestamp`.
- Ownership: the target row's owner must equal `ctx.sender()`.

## Tests

Write a two-identity test for every reducer that touches shared or owned state. Identity A must not be able to change
B's rows. Use the bot harness (`tools/loadtest/bots`) or module tests.

## Done

Run `python tools/kit.py check`, then build the wasm, publish, regenerate bindings and run the smoke test.
