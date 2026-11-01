//! The game-agnostic MMO core. See docs/SHARD_CORE.md for the adapter contract: the core
//! never names a game; an adapter supplies maps, a walk table, portals, NPCs, monsters and items
//! through the `seed_*` reducers.
pub mod chat;
pub mod combat;
pub mod items;
pub mod maps;
pub mod movement;
pub mod npc;
pub mod rules;
pub mod seed;
pub mod tables;
pub mod world;
