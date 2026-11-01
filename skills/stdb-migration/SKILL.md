---
name: stdb-migration
description: Ship SpacetimeDB schema changes to a world that already has data, without wipes. Use when changing tables after players exist.
---

# Schema migration on a live world

## Classify

| Change | Kind | How |
|---|---|---|
| New table (incl. a side table keyed by the same id) | additive, no client disconnect | publish. **The default for live worlds.** |
| New index | usually additive | publish; check publish output |
| New column on an existing table | version-dependent, see below | prefer a new side table keyed by the same id |
| Remove/rename/reorder column, change type, change primary key | destructive | dual-table migration |
| Make a public table private (or back) | behaviour change | publish, then audit clients |

### New columns: what each version does

| Version | Appending a column to an existing table | Source |
|---|---|---|
| 2.13 | Refused, **even with a default value**. Use a side table. | field report |
| 2.14.0 | Accepted only if the field is **appended last** and has `#[default(value)]`; existing rows get the default. The publish plan warns *"All clients will be disconnected due to breaking schema changes"*, and they are. Without `#[default]` it is refused: *"Adding a column ... requires a default value annotation"*. | verified locally 2026-11-01 |
| any | Inserting a column in the middle, renaming, reordering or changing a type | destructive: dual-table migration |

`#[default]` must not go on primary key, unique or auto-inc columns (`skills/vendor/official/rust-server/SKILL.md`).
Even where a defaulted column is accepted, it disconnects every client, so on a world with players prefer a **side
table**: `player_ext { #[primary_key] player_id, new_field }`, filled lazily or by a batched backfill. A new table
publishes without disconnecting anyone (verified on 2.14.0). Read the publish plan before you type `--yes`.

`spacetime publish` refuses changes it cannot migrate automatically. `--delete-data` wipes the world. It is fine for a
dev database and never acceptable on a world with players.

## Dual-table migration

1. **Release N:** add `player_v2` with the new shape. Write to both tables in reducers. Add a scheduled `migrate_step`
   reducer that copies about 500 rows per run from `player` to `player_v2`. It must be idempotent: skip ids already
   copied.
2. Wait until the counts match (`spacetime sql <db> "SELECT COUNT(*) FROM player_v2"`).
3. **Release N+1:** readers and clients switch to `player_v2`. Stop writing `player`.
4. **Release N+2:** drop `player`. This one is destructive, so plan it with a short maintenance window or leave the
   table unused.

## Seeding and backfills

- `init` runs only on the first publish. Seed with idempotent `ensure_*` reducers and a `schema_version` in a config
  row. The template's `ensure_world` is the model.
- Backfills run in batches from a scheduled reducer so they never blow the tick budget.

## Rehearse

1. Copy the data dir.
2. Run the same pinned server on another port with `--data-dir <copy>`.
3. Publish the new module there and run the migration.
4. Compare row counts, then run smoke and two-identity tests.
5. Only then publish to the real world.

## Who may trigger a migration or update

Never expose a public reducer (`module_update`, `migrate_now`, `reset_world`, `kick_all`, ...) that any client can call
to republish, wipe or end every session. Gate it with `require_admin(ctx)?`, or delegate with an operator role
(`recipes/operator-role.md`), and keep anything destructive on admin. Scheduled migration steps check
`ctx.sender() == ctx.database_identity()`. This is a design rule for every 2.x version.

## Clients

Regenerate bindings (`python tools/kit.py bindings`) and ship clients that understand both shapes during release N+1.
