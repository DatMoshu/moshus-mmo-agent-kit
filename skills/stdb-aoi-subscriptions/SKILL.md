---
name: stdb-aoi-subscriptions
description: Implement cell-based interest management (AOI) for SpacetimeDB worlds on server and client, and measure its bandwidth. Use for any world with more than about 50 entities or when bandwidth grows with player count.
---

# AOI subscriptions

## Why

Subscription cost is roughly rows in view x update rate x subscribers. In our load test, 100 moving bots in a 3x3-cell
AOI at 20 Hz sent each client about 1,700 row updates per second. Unbounded queries scale with the square of the
player count.

## Server

- Every spatial hot table stores `cell_x`/`cell_y` with a composite btree index (`by_cell`). The tick updates the cell
  when an entity crosses a boundary.
- Choose a cell size near view radius / 1-2. The template uses `CELL_SIZE = 50` for a view of about 75.
- Keep the hot table narrow (id, x, y, cell, a few flags) and quantize. Write only on change.

## Client

1. Subscribe to your own transform first (`WHERE identity = <me>`). You need your position to know your cells.
2. Compute the 3x3 block around your cell. Subscribe one query per cell:
   `SELECT * FROM entity_transform WHERE cell_x = 3 AND cell_y = -2`.
3. When your cell changes, diff the sets. Unsubscribe cells you left and subscribe the new ones. Never re-issue one
   giant overlapping query.
4. Read from the cache filtered by your current cell set. Some SDKs (notably the Godot GDScript SDK) keep stale rows
   after an unsubscribe and do not ref-count overlapping subscriptions.
5. Render remote entities with interpolation, 100-150 ms behind.

## Tiers (only when measured need)

- **Near:** full rows at the tick rate (3x3).
- **Far:** a per-cell summary table updated every N ticks, for example population counts and a boss position.
- **Global:** small public tables such as `world_config` and `tick_health`.

## Measure

`python tools/kit.py loadtest --bots 100` reports `updates_per_bot_per_sec`. The budgets in
`tools/loadtest/budgets.json` are warn 2,000 and fail 10,000. Record before/after numbers for any AOI change.

## Wrong vs right

| Wrong | Right |
|---|---|
| `SELECT * FROM entity_transform` | per-cell queries for the 3x3 block |
| one radius query rebuilt every move | cell-set diff on boundary crossing |
| positions as f64 written every tick | quantized f32/i32, written on change |
| names and stats in the transform row | cold `player` table, subscribed once |
