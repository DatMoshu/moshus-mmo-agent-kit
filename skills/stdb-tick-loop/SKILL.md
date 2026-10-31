---
name: stdb-tick-loop
description: Add or change a fixed-rate scheduled game tick with self-measured health and load shedding in SpacetimeDB 2.14. Use for real-time simulation, AI, regen or any periodic work.
---

# Fixed-rate tick with tick_health

The reference implementation is `templates/server/rust-single/src/lib.rs` (`tick`, `tick_schedule`, `tick_health`).

## Schedule

```rust
#[table(accessor = tick_schedule, scheduled(tick))]
pub struct TickSchedule {
    #[primary_key] #[auto_inc] pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

// in init / ensure_world (only if no row exists yet):
ctx.db.tick_schedule().insert(TickSchedule {
    scheduled_id: 0,
    scheduled_at: ScheduleAt::Interval(TimeDuration::from_micros(1_000_000 / TICK_HZ as i64)),
});
```

- The attribute is `scheduled(fn)`, not `schedule`.
- `ScheduleAt::Interval` repeats. `ScheduleAt::Time(ts)` fires once.

## Guard it

Scheduled reducers are ordinary reducers that clients can call:

```rust
#[reducer]
pub fn tick(ctx: &ReducerContext, _row: TickSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("tick is internal".into());
    }
    ...
}
```

## Measure yourself

`ctx.timestamp` minus the previous tick's timestamp gives the real interval. The scheduler's *lateness* (real minus
expected) is a cheap, honest load signal. Keep an exponential average and a max in a singleton `tick_health` row, then
derive a level:

| level | meaning | action |
|---|---|---|
| 0 green | avg lateness < 25% of interval | everything runs |
| 1 yellow | < 50% | log once, no shedding |
| 2 orange | < 100% | skip optional work (housekeeping, far AI, cosmetic updates) |
| 3 red | >= 100% | shed more, alert ops |

## Budget the work

- Iterate only what moves. The template walks `entity_transform` (online players only) and looks up
  `player_input` by key.
- Write only rows that changed. A stationary entity costs zero row updates.
- Spread expensive passes across ticks (`tick_count % N`). Move pathfinding and mapgen to a sidecar (`stdb-sidecar`).
- 10-20 Hz is plenty for most MMOs. Higher rates multiply subscription fan-out linearly.

## Gotchas

- Many bot or player inputs per tick should overwrite one `player_input` row per player, not append rows.
- Don't do heavy `log::info!` in the tick.
- After changing the tick, run `python tools/kit.py loadtest` and compare `tick_health.avg_lateness_us` and
  `updates_per_bot_per_sec` with the last report.
