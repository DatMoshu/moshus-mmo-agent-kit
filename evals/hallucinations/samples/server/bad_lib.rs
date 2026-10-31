// Deliberately wrong 1.x / invented SpacetimeDB code. Every block must be caught by rules/hallucinations.json.
use spacetimedb::{ReducerContext, Table, SpacetimeType};
use std::time::SystemTime;

#[spacetimedb(table)]
pub struct Legacy { pub id: u64 }

#[spacetimedb::table(name = player, public)]
pub struct Player { #[primary_key] pub identity: Identity, pub name: String }

#[derive(SpacetimeType)]
#[spacetimedb::table(accessor = monster)]
pub struct Monster { #[primary_key] pub id: u64 }

#[spacetimedb::table(accessor = tick_schedule, schedule(tick))]
pub struct TickSchedule { #[primary_key] #[auto_inc] pub scheduled_id: u64, pub scheduled_at: ScheduleAt }

#[spacetimedb::reducer]
pub fn tick(ctx: &ReducerContext, _r: TickSchedule) {
    if ctx.sender != ctx.identity() { return; }
    let now = SystemTime::now();
    let roll: u32 = rand::thread_rng().gen();
    let p = Player::filter_by_name(&"x".to_string());
    std::fs::write("log.txt", "tick").ok();
}
