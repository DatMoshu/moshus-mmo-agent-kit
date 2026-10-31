# Correct snippets (must produce zero findings)

The wrong form `ctx.identity()` mentioned in prose is fine.

```rust
#[spacetimedb::table(accessor = tick_schedule, scheduled(tick))]
pub struct TickSchedule { #[primary_key] #[auto_inc] scheduled_id: u64, scheduled_at: ScheduleAt }

#[spacetimedb::reducer]
pub fn tick(ctx: &ReducerContext, _row: TickSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() { return Err("internal".into()); }
    let _t = ctx.timestamp;
    Ok(())
}
```
