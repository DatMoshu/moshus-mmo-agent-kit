//! Shard server module from Moshu's MMO Agent Kit `rust-shard` template (SpacetimeDB 2.14): a
//! clean-room, game-agnostic tile-world MMO core in the classic top-down RPG style.
//!
//! Layout:
//! - `core/` — the reusable MMO core: tables, movement with tile collision and body blocking,
//!   maps/portals/exits, NPC wander, chat, PvE combat, items/inventory, persistence, and the
//!   operator-gated `seed_*` staging reducers. Change it in the kit, then re-vendor
//!   (`tools/shard/vendor_core.py`); a game repo never edits it in place.
//! - Your game's server rules go in sibling modules (e.g. `src/game/`), declared below.
//! - The world itself is DATA: a `mmo-core-world/1` document (docs/SHARD_CORE.md) that
//!   `tools/shard/seeder.py` turns into seed calls. `tools/shard/fixture_game.py` builds the
//!   Meadowmere test world from code, so the template ships no third-party game data.
//!
//! What the kit starter shows, kept here:
//! - server-authoritative movement: clients send *intent* (a direction), the tick moves them
//! - a fixed-rate scheduled tick that guards itself against client calls
//! - a self-measuring `tick_health` row (lateness of the scheduler = load signal)
//! - narrow, public "hot" tables with (map, cell) indexes for AOI subscriptions
//! - private tables for inputs and admission, an admin identity, idempotent `ensure_world`
//!
//! Rules this module follows are in `rules/rust-module.md` at the kit root.

pub mod core;

#[cfg(feature = "project-tick")]
pub mod project_tick;
