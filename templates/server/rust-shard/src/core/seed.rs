//! Staging: operator-gated seed reducers, called by an adapter's seeder (tools/shard/seeder.py).
//! All are admin-only and idempotent (upserts keyed by stable ids), so a failed seed can simply
//! be re-run. Order: seed_begin (clears per-seed content), seed_tile_rules, seed_map +
//! seed_chunk..., seed_map_exit, seed_portal, seed_npcs, seed_monster_kind, seed_spawn_rule,
//! seed_safe_zone, seed_respawn, seed_item_kind, seed_commit. Collision is on only after
//! seed_commit validates. Players, stats and inventories are never touched by a reseed.

use spacetimedb::{reducer, ReducerContext, Table};

use super::maps::walkable;
use super::rules::*;
use super::tables::*;
use super::world::require_admin;

fn upsert_seed(ctx: &ReducerContext, f: impl FnOnce(&mut WorldSeed)) {
    let mut s = ctx.db.world_seed().id().find(0).unwrap_or(WorldSeed {
        id: 0,
        state: "empty".into(),
        kind: String::new(),
        tag: String::new(),
        spawn_map: MAP_SURFACE,
        spawn_x: 128,
        spawn_y: 128,
        chunks: 0,
        updated_at: ctx.timestamp,
    });
    f(&mut s);
    s.updated_at = ctx.timestamp;
    if ctx.db.world_seed().id().find(0).is_some() {
        ctx.db.world_seed().id().update(s);
    } else {
        ctx.db.world_seed().insert(s);
    }
}

fn valid_kind(kind: &str) -> Result<(), String> {
    if kind == "install" || kind == "fixture" { Ok(()) } else { Err("kind must be install or fixture".into()) }
}

/// Starts a seed and clears the content a seed owns (portals, exits, NPCs, monsters, kinds,
/// rules, zones, respawns, ground items). Maps/chunks are upserted, so they are kept.
/// Admin-only (R31: destructive).
#[reducer]
pub fn seed_begin(ctx: &ReducerContext, kind: String, tag: String) -> Result<(), String> {
    require_admin(ctx)?;
    valid_kind(&kind)?;
    if tag.len() > 64 {
        return Err("tag too long".into());
    }
    macro_rules! clear {
        ($t:ident, $pk:ident) => {{
            let ids: Vec<_> = ctx.db.$t().iter().map(|r| r.$pk).collect();
            for id in ids {
                ctx.db.$t().$pk().delete(id);
            }
        }};
    }
    clear!(portal, id);
    clear!(map_exit, map_id);
    clear!(npc, id);
    clear!(npc_meta, id);
    clear!(monster, id);
    clear!(monster_brain, id);
    clear!(monster_kind, kind);
    clear!(monster_ai, kind);
    clear!(monster_status, id);
    clear!(spawn_rule, id);
    clear!(safe_zone, id);
    clear!(respawn_point, id);
    clear!(ground_item, id);
    clear!(item_kind, kind);
    upsert_seed(ctx, |s| {
        s.state = "seeding".into();
        s.kind = kind;
        s.tag = tag;
    });
    Ok(())
}

#[reducer]
pub fn seed_tile_rules(ctx: &ReducerContext, walkable: Vec<u8>) -> Result<(), String> {
    require_admin(ctx)?;
    if walkable.len() != 256 {
        return Err("walkable must have 256 entries".into());
    }
    let row = TileRule { id: 0, walkable };
    if ctx.db.tile_rule().id().find(0).is_some() {
        ctx.db.tile_rule().id().update(row);
    } else {
        ctx.db.tile_rule().insert(row);
    }
    // Rules changed: recompute every seeded chunk's walk bits.
    let rule = ctx.db.tile_rule().id().find(0).map(|r| r.walkable).unwrap_or_default();
    let chunks: Vec<MapChunk> = ctx.db.map_chunk().iter().collect();
    for c in chunks {
        let bits = walk_bits(&c.tiles, &rule);
        ctx.db.walk_chunk().id().update(WalkChunk { id: c.id, bits });
    }
    Ok(())
}

#[reducer]
pub fn seed_map(ctx: &ReducerContext, map_id: u8, key: String, width: u16, height: u16, exit_at_edge: bool) -> Result<(), String> {
    require_admin(ctx)?;
    if width == 0 || height == 0 || width % CHUNK as u16 != 0 || height % CHUNK as u16 != 0 || width > 8192 || height > 8192 {
        return Err("map size must be a non-zero multiple of 32 (max 8192)".into());
    }
    if key.is_empty() || key.len() > 32 {
        return Err("key must be 1-32 bytes".into());
    }
    let row = MapInfo { map_id, key, width, height, exit_at_edge };
    if ctx.db.map_info().map_id().find(map_id).is_some() {
        ctx.db.map_info().map_id().update(row);
    } else {
        ctx.db.map_info().insert(row);
    }
    Ok(())
}

#[reducer]
pub fn seed_chunk(ctx: &ReducerContext, map_id: u8, cx: u8, cy: u8, tiles: Vec<u8>) -> Result<(), String> {
    require_admin(ctx)?;
    let Some(m) = ctx.db.map_info().map_id().find(map_id) else { return Err("seed_map first".into()) };
    if (cx as u32) * CHUNK >= m.width as u32 || (cy as u32) * CHUNK >= m.height as u32 {
        return Err("chunk outside map".into());
    }
    if tiles.len() != (CHUNK * CHUNK) as usize {
        return Err("a chunk is 1024 tiles".into());
    }
    let Some(rule) = ctx.db.tile_rule().id().find(0) else { return Err("seed_tile_rules first".into()) };
    let id = chunk_id(map_id, cx as u32, cy as u32);
    let bits = walk_bits(&tiles, &rule.walkable);
    let row = MapChunk { id, map_id, cx, cy, tiles };
    if ctx.db.map_chunk().id().find(id).is_some() {
        ctx.db.map_chunk().id().update(row);
        ctx.db.walk_chunk().id().update(WalkChunk { id, bits });
    } else {
        ctx.db.map_chunk().insert(row);
        ctx.db.walk_chunk().insert(WalkChunk { id, bits });
    }
    Ok(())
}

fn upsert_portal(ctx: &ReducerContext, row: Portal) {
    if ctx.db.portal().id().find(row.id).is_some() {
        ctx.db.portal().id().update(row);
    } else {
        ctx.db.portal().insert(row);
    }
}

/// Map transition. Same-map portals are allowed (teleports such as moongates) as long as the
/// target tile differs from the source tile.
#[reducer]
pub fn seed_portal(ctx: &ReducerContext, id: u32, from_map: u8, x: u16, y: u16, to_map: u8, to_x: u16, to_y: u16) -> Result<(), String> {
    require_admin(ctx)?;
    if from_map == to_map && x == to_x && y == to_y {
        return Err("portal must lead somewhere else".into());
    }
    upsert_portal(ctx, Portal { id, from_map, x, y, to_map, to_x, to_y });
    Ok(())
}

/// Where walking off the edge of `map_id` lands you.
#[reducer]
pub fn seed_map_exit(ctx: &ReducerContext, map_id: u8, to_map: u8, x: u16, y: u16) -> Result<(), String> {
    require_admin(ctx)?;
    let row = MapExit { map_id, to_map, x, y };
    if ctx.db.map_exit().map_id().find(map_id).is_some() {
        ctx.db.map_exit().map_id().update(row);
    } else {
        ctx.db.map_exit().insert(row);
    }
    Ok(())
}

/// Replaces every NPC slot on `map_id`. Parallel arrays (one entry per slot). `talk` is the
/// adapter's dialogue index per slot (0 = none); it may be empty (= all 0).
#[reducer]
pub fn seed_npcs(
    ctx: &ReducerContext,
    map_id: u8,
    slots: Vec<u8>,
    tiles: Vec<u8>,
    xs: Vec<u8>,
    ys: Vec<u8>,
    wander: Vec<u8>,
    talk: Vec<u8>,
) -> Result<(), String> {
    require_admin(ctx)?;
    let n = slots.len();
    if n > 256 || tiles.len() != n || xs.len() != n || ys.len() != n || wander.len() != n || (!talk.is_empty() && talk.len() != n) {
        return Err("npc arrays must have equal length (max 256)".into());
    }
    let old: Vec<u32> = ctx.db.npc_meta().map_id().filter(map_id).map(|r| r.id).collect();
    for id in old {
        ctx.db.npc().id().delete(id);
        ctx.db.npc_meta().id().delete(id);
    }
    // Rows from before npc_meta existed (no side row): bounded scan of the npc table.
    let stale: Vec<u32> = ctx.db.npc().iter().filter(|r| r.map_id == map_id).map(|r| r.id).collect();
    for id in stale {
        ctx.db.npc().id().delete(id);
    }
    for i in 0..n {
        let (x, y) = (xs[i] as f32 + 0.5, ys[i] as f32 + 0.5);
        let id = ((map_id as u32) << 8) | slots[i] as u32;
        ctx.db.npc().insert(Npc {
            id,
            map_id,
            slot: slots[i],
            tile: tiles[i],
            x,
            y,
            cell_x: cell_of(x),
            cell_y: cell_of(y),
            wander: wander[i] != 0,
        });
        ctx.db.npc_meta().insert(NpcMeta {
            id,
            map_id,
            talk: talk.get(i).copied().unwrap_or(0),
            home_x: xs[i],
            home_y: ys[i],
        });
    }
    Ok(())
}

#[reducer]
#[allow(clippy::too_many_arguments)]
pub fn seed_monster_kind(
    ctx: &ReducerContext,
    kind: u8,
    name: String,
    tile: u8,
    hp: i32,
    dmg_min: i32,
    dmg_max: i32,
    step_ticks: u16,
    attack_ticks: u16,
    aggro: u8,
    xp: u32,
    gold_min: u32,
    gold_max: u32,
) -> Result<(), String> {
    require_admin(ctx)?;
    if name.is_empty() || name.len() > 32 || hp <= 0 || dmg_min < 0 || dmg_max < dmg_min || gold_max < gold_min {
        return Err("bad monster kind".into());
    }
    let row = MonsterKind { kind, name, tile, hp, dmg_min, dmg_max, step_ticks, attack_ticks, aggro, xp, gold_min, gold_max };
    if ctx.db.monster_kind().kind().find(kind).is_some() {
        ctx.db.monster_kind().kind().update(row);
    } else {
        ctx.db.monster_kind().insert(row);
    }
    Ok(())
}

/// Behaviour for monster `kind` (see core/ai.rs): flee threshold in %, ranged reach and kept
/// distance in tiles, pack radius, flags (low 16 bits core, high 16 bits game-defined).
#[reducer]
pub fn seed_monster_ai(ctx: &ReducerContext, kind: u8, flee_hp_pct: u8, range: u8, keep_dist: u8, pack: u8, flags: u32) -> Result<(), String> {
    require_admin(ctx)?;
    if flee_hp_pct > 100 || range > 16 || keep_dist > range.max(1) || pack > 16 {
        return Err("bad monster ai".into());
    }
    let row = MonsterAi { kind, flee_hp_pct, range, keep_dist, pack, flags };
    if ctx.db.monster_ai().kind().find(kind).is_some() {
        ctx.db.monster_ai().kind().update(row);
    } else {
        ctx.db.monster_ai().insert(row);
    }
    Ok(())
}

#[reducer]
pub fn seed_spawn_rule(ctx: &ReducerContext, id: u32, map_id: u8, max_alive: u16, kinds: Vec<u8>, min_dist: u8, max_dist: u8) -> Result<(), String> {
    require_admin(ctx)?;
    if kinds.is_empty() || kinds.len() > 64 || max_dist < min_dist || max_alive as usize > MAX_MONSTERS {
        return Err("bad spawn rule".into());
    }
    let row = SpawnRule { id, map_id, max_alive, kinds, min_dist, max_dist };
    if ctx.db.spawn_rule().id().find(id).is_some() {
        ctx.db.spawn_rule().id().update(row);
    } else {
        ctx.db.spawn_rule().insert(row);
    }
    Ok(())
}

#[reducer]
pub fn seed_safe_zone(ctx: &ReducerContext, id: u32, map_id: u8, x: u16, y: u16, r: u16) -> Result<(), String> {
    require_admin(ctx)?;
    let row = SafeZone { id, map_id, x, y, r };
    if ctx.db.safe_zone().id().find(id).is_some() {
        ctx.db.safe_zone().id().update(row);
    } else {
        ctx.db.safe_zone().insert(row);
    }
    Ok(())
}

#[reducer]
pub fn seed_respawn(ctx: &ReducerContext, id: u32, map_id: u8, x: u16, y: u16) -> Result<(), String> {
    require_admin(ctx)?;
    let row = RespawnPoint { id, map_id, x, y };
    if ctx.db.respawn_point().id().find(id).is_some() {
        ctx.db.respawn_point().id().update(row);
    } else {
        ctx.db.respawn_point().insert(row);
    }
    Ok(())
}

#[reducer]
pub fn seed_item_kind(ctx: &ReducerContext, kind: u16, name: String, tile: u8, heal: i32) -> Result<(), String> {
    require_admin(ctx)?;
    if name.is_empty() || name.len() > 32 {
        return Err("bad item kind".into());
    }
    let row = ItemKind { kind, name, tile, heal };
    if ctx.db.item_kind().kind().find(kind).is_some() {
        ctx.db.item_kind().kind().update(row);
    } else {
        ctx.db.item_kind().insert(row);
    }
    Ok(())
}

/// Validates the seed (every map fully chunked, spawn and respawns walkable) and switches
/// collision on.
#[reducer]
pub fn seed_commit(ctx: &ReducerContext, kind: String, tag: String, spawn_map: u8, spawn_x: u16, spawn_y: u16) -> Result<(), String> {
    require_admin(ctx)?;
    valid_kind(&kind)?;
    let seed = ctx.db.world_seed().id().find(0).ok_or("seed_begin first")?;
    if seed.tag != tag || seed.kind != kind {
        return Err(format!("seed_commit for {kind}/{tag} but seeding {}/{}", seed.kind, seed.tag));
    }
    let mut chunks = 0u32;
    for m in ctx.db.map_info().iter() {
        let want = (m.width as u32 / CHUNK) * (m.height as u32 / CHUNK);
        let have = ctx.db.map_chunk().iter().filter(|c| c.map_id == m.map_id).count() as u32;
        if have != want {
            return Err(format!("map {} has {have}/{want} chunks", m.key));
        }
        chunks += have;
    }
    if !walkable(ctx, spawn_map, spawn_x as i32, spawn_y as i32, true) {
        return Err("spawn tile is not walkable".into());
    }
    for r in ctx.db.respawn_point().iter() {
        if !walkable(ctx, r.map_id, r.x as i32, r.y as i32, true) {
            return Err(format!("respawn {} is not walkable", r.id));
        }
    }
    upsert_seed(ctx, |s| {
        s.state = "ready".into();
        s.spawn_map = spawn_map;
        s.spawn_x = spawn_x;
        s.spawn_y = spawn_y;
        s.chunks = chunks;
    });
    Ok(())
}
