//! Project-owned tick continuation (example; game repos replace this file). Compiled only with the
//! `project-tick` feature. The vendor tool copies `core/` only, so a project declares and enables the
//! feature and owns this module itself.
use crate::core::tables::TickSchedule;
use spacetimedb::ReducerContext;

/// Called by `core::movement::tick` after its scheduler-only guard. Apply project policy here, then
/// continue into `tick_body`. Never call `tick` from here (recursion).
pub fn dispatch(ctx: &ReducerContext, row: TickSchedule) -> Result<(), String> {
    crate::core::movement::tick_body(ctx, row)
}
