//! Every table of the shared MMO core. Game-agnostic: an adapter (tools/<game>/) fills the
//! seeded ones (maps, tile rules, portals, NPCs, monster/item kinds, spawn rules) through the
//! operator-gated `seed_*` reducers in `seed.rs`. Nothing here knows which game it is running.
//!
//! Schema policy (rules/rust-module.md R18/R29): tables that shipped in the first release keep their exact
//! column layout; everything new is a NEW table (side tables keyed by the same id where needed),
//! so a publish over an existing world is additive and does not disconnect clients.

use spacetimedb::{table, Identity, ScheduleAt, Timestamp};

// ---------------------------------------------------------------------------------------------
// World / admission / players (first-release shapes, unchanged)
// ---------------------------------------------------------------------------------------------

/// Singleton (id = 0). Public so clients can read world bounds and tick rate.
#[table(accessor = world_config, public)]
pub struct WorldConfig {
    #[primary_key]
    pub id: u8,
    pub admin: Identity,
    pub admission_open: bool,
    pub tick_hz: u32,
    pub max_speed: f32,
    pub cell_size: f32,
    pub world_half: f32,
    pub schema_version: u32,
}

/// Private: who may connect while admission is closed.
#[table(accessor = allowlist)]
pub struct Allowlist {
    #[primary_key]
    pub identity: Identity,
    pub granted_at: Timestamp,
}

/// Cold, wide-ish row: changes rarely (join, rename, online flag, logout position).
#[table(accessor = player, public)]
pub struct Player {
    #[primary_key]
    pub identity: Identity,
    #[unique]
    pub name: String,
    pub online: bool,
    pub created_at: Timestamp,
    pub last_seen: Timestamp,
    /// Where the player logged out; the transform row only exists while online.
    pub last_x: f32,
    pub last_y: f32,
    pub last_map: u8,
}

/// Private: latest movement intent per player. Never broadcast.
#[table(accessor = player_input)]
pub struct PlayerInput {
    #[primary_key]
    pub identity: Identity,
    pub dir_x: i8,
    pub dir_y: i8,
    pub seq: u32,
}

/// Hot, narrow row: the only player row that changes every tick. Subscribe to it by cell.
#[table(
    accessor = entity_transform,
    public,
    index(accessor = by_cell, btree(columns = [map_id, cell_x, cell_y]))
)]
pub struct EntityTransform {
    #[primary_key]
    pub identity: Identity,
    pub map_id: u8,
    pub x: f32,
    pub y: f32,
    pub cell_x: i32,
    pub cell_y: i32,
    pub moving: bool,
    pub last_input_seq: u32,
}

/// Scheduler row for the fixed-rate tick.
#[table(accessor = tick_schedule, scheduled(crate::core::movement::tick))]
pub struct TickSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

/// Singleton (id = 0). level: 0 green, 1 yellow, 2 orange (optional work shed), 3 red.
#[table(accessor = tick_health, public)]
pub struct TickHealth {
    #[primary_key]
    pub id: u8,
    pub tick_count: u64,
    pub last_tick_at: Timestamp,
    pub last_lateness_us: i64,
    pub avg_lateness_us: i64,
    pub max_lateness_us: i64,
    pub moved_last_tick: u32,
    pub online_players: u32,
    pub level: u8,
}

// ---------------------------------------------------------------------------------------------
// Maps (seeded by the adapter)
// ---------------------------------------------------------------------------------------------

/// Public, one row per map. Dimensions only; tiles are private (see `map_chunk`).
#[table(accessor = map_info, public)]
pub struct MapInfo {
    #[primary_key]
    pub map_id: u8,
    pub key: String,
    pub width: u16,
    pub height: u16,
    /// Town-style map: walking off any edge leaves the map (see `map_exit`).
    pub exit_at_edge: bool,
}

/// Public: where walking off the edge of an `exit_at_edge` map puts you (the parent map tile
/// next to the entrance). Without a row the first portal leading into the map is used.
#[table(accessor = map_exit, public)]
pub struct MapExit {
    #[primary_key]
    pub map_id: u8,
    pub to_map: u8,
    pub x: u16,
    pub y: u16,
}

/// Private: raw tile indices of one 32x32 chunk (id = map_id<<16 | cy<<8 | cx).
#[table(accessor = map_chunk)]
pub struct MapChunk {
    #[primary_key]
    pub id: u32,
    pub map_id: u8,
    pub cx: u8,
    pub cy: u8,
    pub tiles: Vec<u8>,
}

/// Private: walkability bitset of one chunk (128 bytes, bit i = tile i in row-major order).
#[table(accessor = walk_chunk)]
pub struct WalkChunk {
    #[primary_key]
    pub id: u32,
    pub bits: Vec<u8>,
}

/// Private singleton (id 0): walkable flag per tile index (256 entries, 0/1).
#[table(accessor = tile_rule)]
pub struct TileRule {
    #[primary_key]
    pub id: u8,
    pub walkable: Vec<u8>,
}

/// Public: map transitions (town entrances, ladders, moongates). Stepping onto
/// (from_map, x, y) moves you to (to_map, to_x, to_y). `from_map == to_map` is allowed
/// (moongates teleport within the surface).
#[table(
    accessor = portal,
    public,
    index(accessor = portal_by_tile, btree(columns = [from_map, x, y]))
)]
pub struct Portal {
    #[primary_key]
    pub id: u32,
    pub from_map: u8,
    pub x: u16,
    pub y: u16,
    pub to_map: u8,
    pub to_x: u16,
    pub to_y: u16,
}

/// Public singleton (id 0): what is seeded. state: "empty" | "seeding" | "ready".
#[table(accessor = world_seed, public)]
pub struct WorldSeed {
    #[primary_key]
    pub id: u8,
    pub state: String,
    pub kind: String,
    pub tag: String,
    pub spawn_map: u8,
    pub spawn_x: u16,
    pub spawn_y: u16,
    pub chunks: u32,
    pub updated_at: Timestamp,
}

// ---------------------------------------------------------------------------------------------
// NPCs
// ---------------------------------------------------------------------------------------------

/// Public: town NPC position (hot while it wanders). id = map_id<<8 | slot.
#[table(
    accessor = npc,
    public,
    index(accessor = npc_by_cell, btree(columns = [map_id, cell_x, cell_y]))
)]
pub struct Npc {
    #[primary_key]
    pub id: u32,
    pub map_id: u8,
    pub slot: u8,
    /// Sprite tile index; 0 = empty slot in the source data.
    pub tile: u8,
    pub x: f32,
    pub y: f32,
    pub cell_x: i32,
    pub cell_y: i32,
    pub wander: bool,
}

/// Public side table of `npc` (cold): dialogue index into the adapter's dialogue source
/// (0 = nobody to talk to) and the home tile the wander leash is measured from.
/// The dialogue TEXT never touches the server: clients read it from their own install.
#[table(accessor = npc_meta, public)]
pub struct NpcMeta {
    #[primary_key]
    pub id: u32,
    #[index(btree)]
    pub map_id: u8,
    pub talk: u8,
    pub home_x: u8,
    pub home_y: u8,
}

// ---------------------------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------------------------

/// Public: shared chat (last CHAT_KEEP lines are kept).
#[table(accessor = chat_message, public)]
pub struct ChatMessage {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub sender: Identity,
    pub name: String,
    pub map_id: u8,
    pub text: String,
    pub sent_at: Timestamp,
}

/// Public side table of `chat_message`: the line's channel (`CH_LOCAL` or `CH_WORLD`, rules.rs).
/// No row = `CH_WORLD` (lines from before channels existed and the plain `say` reducer).
#[table(accessor = chat_channel, public)]
pub struct ChatChannel {
    #[primary_key]
    pub id: u64,
    pub channel: u8,
}

/// Private: chat lines for some readers only (whispers, a game's party chat, system notices), one row
/// per reader; each player reads their own through the `my_chat` view. The last CHAT_DIRECT_KEEP per
/// reader are kept. `target_name` is who a whisper went to (so the sender's copy can show it).
#[table(accessor = chat_direct)]
pub struct ChatDirect {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub to: Identity,
    pub sender: Identity,
    pub name: String,
    pub channel: u8,
    pub target_name: String,
    pub text: String,
    pub sent_at: Timestamp,
}

/// Private: per-identity chat rate window.
#[table(accessor = chat_rate)]
pub struct ChatRate {
    #[primary_key]
    pub identity: Identity,
    pub window_start: Timestamp,
    pub count: u32,
}

// ---------------------------------------------------------------------------------------------
// Combat
// ---------------------------------------------------------------------------------------------

/// Public: per-player stats (cold-ish: changes on hits, kills, loot). Persisted across logins.
#[table(accessor = player_stats, public)]
pub struct PlayerStats {
    #[primary_key]
    pub identity: Identity,
    pub hp: i32,
    pub max_hp: i32,
    pub xp: u32,
    pub level: u32,
    pub gold: u32,
    pub kills: u32,
    pub deaths: u32,
}

/// Public: XP and max HP per level (core rules, written on init and on connect), so clients can draw an
/// XP bar: the next level needs `level_xp[level + 1].xp`. A game's `player_mods.level_cap` still applies.
#[table(accessor = level_xp, public)]
pub struct LevelXp {
    #[primary_key]
    pub level: u32,
    pub xp: u32,
    pub max_hp: i32,
}

/// Public, short-lived: one row per hit, heal or kill for floating combat numbers (the last COMBAT_KEEP
/// are kept). Subscribe by map. `src_*` / `dst_*`: a player identity or a monster id (0 = none);
/// `kind` is COMBAT_* and `flags` COMBAT_F_* (rules.rs); `amount` is what was actually dealt.
#[table(accessor = combat_event, public)]
pub struct CombatEvent {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub map_id: u8,
    pub x: f32,
    pub y: f32,
    pub src_player: Option<Identity>,
    pub src_monster: u64,
    pub dst_player: Option<Identity>,
    pub dst_monster: u64,
    pub amount: i32,
    pub kind: u8,
    pub flags: u8,
    pub tick: u64,
}

/// Private: combat timers per player (cooldowns), kept out of the public stats row.
#[table(accessor = player_combat)]
pub struct PlayerCombat {
    #[primary_key]
    pub identity: Identity,
    pub last_attack_tick: u64,
    pub last_hurt_tick: u64,
}

/// Public: monster templates, seeded by the adapter (tile = sprite).
#[table(accessor = monster_kind, public)]
pub struct MonsterKind {
    #[primary_key]
    pub kind: u8,
    pub name: String,
    pub tile: u8,
    pub hp: i32,
    pub dmg_min: i32,
    pub dmg_max: i32,
    /// Ticks between steps (speed) and attacks.
    pub step_ticks: u16,
    pub attack_ticks: u16,
    pub aggro: u8,
    pub xp: u32,
    pub gold_min: u32,
    pub gold_max: u32,
}

/// Public, hot: live monsters. Subscribe by (map, cell) like transforms.
#[table(
    accessor = monster,
    public,
    index(accessor = monster_by_cell, btree(columns = [map_id, cell_x, cell_y]))
)]
pub struct Monster {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub map_id: u8,
    pub kind: u8,
    pub tile: u8,
    pub x: f32,
    pub y: f32,
    pub cell_x: i32,
    pub cell_y: i32,
    pub hp: i32,
    pub max_hp: i32,
}

/// Private side table of `monster`: AI state.
#[table(accessor = monster_brain)]
pub struct MonsterBrain {
    #[primary_key]
    pub id: u64,
    pub home_x: i32,
    pub home_y: i32,
    pub next_act_tick: u64,
}

/// Private: per-kind behaviour (adapter-seeded with `seed_monster_ai`; no row = melee brute).
/// See core/ai.rs for the meaning of each field and the core `flags` bits.
#[table(accessor = monster_ai)]
pub struct MonsterAi {
    #[primary_key]
    pub kind: u8,
    pub flee_hp_pct: u8,
    pub range: u8,
    pub keep_dist: u8,
    pub pack: u8,
    pub flags: u32,
}

/// Public: timed statuses on one live monster (games set them, e.g. sleep or confusion spells),
/// plus the pack alert (who its kin called it to fight). Ticks are `world_clock` ticks; 0 = off.
#[table(accessor = monster_status, public)]
pub struct MonsterStatus {
    #[primary_key]
    pub id: u64,
    pub sleep_until: u64,
    pub confuse_until: u64,
    pub silence_until: u64,
    pub fear_until: u64,
    pub alert: Option<Identity>,
    pub alert_until: u64,
}

/// Private: natural spawning per map (adapter-seeded). Spawns happen near online players.
#[table(accessor = spawn_rule)]
pub struct SpawnRule {
    #[primary_key]
    pub id: u32,
    pub map_id: u8,
    pub max_alive: u16,
    pub kinds: Vec<u8>,
    pub min_dist: u8,
    pub max_dist: u8,
}

/// Private: no natural spawns and no monster steps inside these circles (spawn, entrances).
#[table(accessor = safe_zone)]
pub struct SafeZone {
    #[primary_key]
    pub id: u32,
    pub map_id: u8,
    pub x: u16,
    pub y: u16,
    pub r: u16,
}

/// Private: where dead players come back (nearest on their map, else the first one).
#[table(accessor = respawn_point)]
pub struct RespawnPoint {
    #[primary_key]
    pub id: u32,
    pub map_id: u8,
    pub x: u16,
    pub y: u16,
}

// ---------------------------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------------------------

/// Public: item templates (adapter-seeded). kind 0 is always gold (goes to player_stats.gold).
#[table(accessor = item_kind, public)]
pub struct ItemKind {
    #[primary_key]
    pub kind: u16,
    pub name: String,
    pub tile: u8,
    /// HP restored by `use_item` (0 = not usable).
    pub heal: i32,
}

/// Public: items lying on the ground. Subscribe by (map, cell).
#[table(
    accessor = ground_item,
    public,
    index(accessor = item_by_cell, btree(columns = [map_id, cell_x, cell_y]))
)]
pub struct GroundItem {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub map_id: u8,
    pub x: u16,
    pub y: u16,
    pub cell_x: i32,
    pub cell_y: i32,
    pub kind: u16,
    pub qty: u32,
    pub dropped_tick: u64,
}

/// Private: what each player carries. Exposed to its owner only through the `my_inventory` view.
#[table(accessor = inventory)]
pub struct InventoryItem {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub owner: Identity,
    pub kind: u16,
    pub qty: u32,
}

/// Public: optional per-player modifiers a game layer writes (equipment, buffs, a level cap).
/// No row = no modifiers. The core reads it in combat: `dmg_bonus` adds to melee damage, `armour`
/// is subtracted from damage taken (never below 1), and `level_cap` (0 = none) stops automatic
/// level-ups so a game can grant levels itself (e.g. a king who promotes you).
#[table(accessor = player_mods, public)]
pub struct PlayerMods {
    #[primary_key]
    pub identity: Identity,
    pub dmg_bonus: i32,
    pub armour: i32,
    pub level_cap: u32,
}
