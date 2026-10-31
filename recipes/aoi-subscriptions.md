# AOI (area-of-interest) subscriptions

**Problem.** `SELECT * FROM entity_transform` sends every moving entity to every client. Cost grows with
players², so it becomes the first wall you hit. **Fix:** keep fast-changing rows in a narrow table with an indexed cell,
and let each client subscribe only to the cells around it.

## Server (already in `rust-single`)

```rust
#[table(accessor = entity_transform, public, index(accessor = by_cell, btree(columns = [cell_x, cell_y])))]
pub struct EntityTransform { #[primary_key] pub identity: Identity, pub x: f32, pub y: f32, pub cell_x: i32, pub cell_y: i32, /* ... */ }
```

The tick recomputes `cell_x/cell_y = floor(pos / CELL_SIZE)` and writes only rows that changed.
Set `CELL_SIZE` to about view radius ÷ 1.5. With a 3×3 window, everything within one cell of the player is visible.

## Client

Resubscribe **only when your own cell changes**. Subscribe to the new set first, then drop the old one, so nothing flickers.

TypeScript (from `tools/loadtest/bots/src/main.ts`):

```ts
const q = `SELECT * FROM entity_transform WHERE cell_x >= ${cx - 1} AND cell_x <= ${cx + 1} AND cell_y >= ${cy - 1} AND cell_y <= ${cy + 1}`;
const next = conn.subscriptionBuilder().subscribe(q);
for (const s of old) s.unsubscribe();
```

GDScript (from `templates/client/godot/net/net_session.gd`) keeps one subscription per cell. On each cell change it
subscribes only the cells that entered the window and unsubscribes the cells that left, so the 6 unchanged cells are never re-sent.

Unity and Unreal: same idea. Keep a `Dictionary<(int,int), SubscriptionHandle>` and diff it on every cell change.

## Also

* Your own row can leave your window during a handoff or teleport. Subscribe to it separately (`WHERE identity = ...`),
  or use a view such as `my_player`.
* Static or cold data (names, appearance) goes in a separate table that you subscribe to once, or by cell at a lower rate.
* Measure it. `python tools/kit.py loadtest --bots 100` reports rows/s per client; the budget is in `tools/loadtest/budgets.json`.
* Skill: `skills/stdb-aoi-subscriptions`.
