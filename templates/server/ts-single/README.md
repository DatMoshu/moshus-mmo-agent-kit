# ts-single: one-database world module in TypeScript

**Status: VERIFIED** on SpacetimeDB 2.14.0 with Node 24 on Linux: typecheck, publish, the TS-SDK two-player
smoke, the Godot two-player smoke and a 50-bot load gate (see `docs/VERIFICATION.md`).

The same game as [`rust-single`](../rust-single/README.md), written as a TypeScript module. Table names,
column names, reducer names and argument names match the Rust module exactly, so the kit's bots
(`tools/loadtest/bots`), the Godot starter and the web admin work against either one without new bindings.

Pick TypeScript when your team lives in TS and the world is small to medium. Pick Rust for the
hottest loops, the largest worlds and the 2.14 sharding template (`rust-sharded`). See `docs/decision-tree.md`.

## Files

| File | What |
|---|---|
| `src/index.ts` | Tables, lifecycle hooks, reducers, the scheduled tick |
| `package.json` | Pins `spacetimedb` to the version in `stdb.lock` |
| `tsconfig.json` | Strict typecheck (`npm run typecheck`) |

## Build and publish

```bash
npm install
npm run typecheck
spacetime publish mmo-dev --server http://127.0.0.1:3000 --module-path . --yes
# or from the kit root:
python tools/kit.py publish --module templates/server/ts-single
python tools/kit.py smoke
```

`spacetime publish` bundles the TypeScript itself. There is no separate build step.

## TypeScript module rules that bit us (see `rules/typescript-module.md`)

* Builders (`schema`, `table`, `t`, `SenderError`) come from `spacetimedb/server`; runtime classes
  (`ScheduleAt`, `Timestamp`, `Identity`) come from `spacetimedb`.
* `schema({...})` takes **one object** and must be the **default export**. The keys are the `ctx.db`
  accessors. This template uses snake_case keys and columns on purpose, for wire compatibility.
* Lifecycle hooks and reducers must be `export const`. Helpers stay unexported.
* `u64`/`i64`/timestamps are `bigint` (`0n`). `u8`..`u32`, `i8`..`i32` and floats are `number`.
* Compare identities with `a.isEqual(b)`, never `===`.
* `ctx.sender` is a property, not a method (Rust uses `ctx.sender()`).
* Use `ctx.random`, never `Math.random` or `Date.now()`.
* Throw `SenderError` for errors the caller should see.
