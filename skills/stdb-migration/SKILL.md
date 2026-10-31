---
name: stdb-migration
description: Ship SpacetimeDB schema changes to a world that already has data, without wipes. Use when changing tables after players exist.
---

# Schema migration on a live world

## Classify

| Change | Kind | How |
|---|---|---|
| New table | additive | publish |
| New index | usually additive | publish; check publish output |
| New column | check the publish diagnostics (2.11+ explains why a change is rejected) | prefer a new side table keyed by the same id |
| Remove/rename/reorder column, change type, change primary key | destructive | dual-table migration |
| Make a public table private (or back) | behaviour change | publish, then audit clients |

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

## Clients

Regenerate bindings (`python tools/kit.py bindings`) and ship clients that understand both shapes during release N+1.
