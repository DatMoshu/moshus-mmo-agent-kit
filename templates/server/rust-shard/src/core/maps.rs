//! Map queries shared by movement, NPCs and monsters: bounds, tile collision, portals, exits,
//! safe zones and the per-tick body-occupancy set.

use std::collections::{BTreeMap, BTreeSet};

use spacetimedb::{ReducerContext, Table};

use super::rules::*;
use super::tables::*;

pub fn map_dims(ctx: &ReducerContext, map_id: u8) -> Option<(u16, u16, bool)> {
    match ctx.db.map_info().map_id().find(map_id) {
        Some(m) => Some((m.width, m.height, m.exit_at_edge)),
        None if map_id == MAP_SURFACE => Some((DEFAULT_SIDE, DEFAULT_SIDE, false)),
        None => None,
    }
}

/// Tile collision from the adapter's walk table (tile_rule -> walk_chunk bits). Unseeded maps are
/// open fields so the kit smoke runs on an empty database; once seeded, a missing chunk is solid.
pub fn walkable(ctx: &ReducerContext, map_id: u8, tx: i32, ty: i32, seeded: bool) -> bool {
    let Some((w, h, _)) = map_dims(ctx, map_id) else { return false };
    if tx < 0 || ty < 0 || tx >= w as i32 || ty >= h as i32 {
        return false;
    }
    let (tx, ty) = (tx as u32, ty as u32);
    match ctx.db.walk_chunk().id().find(chunk_id(map_id, tx / CHUNK, ty / CHUNK)) {
        Some(c) => {
            let i = ((ty % CHUNK) * CHUNK + (tx % CHUNK)) as usize;
            c.bits.get(i / 8).map(|b| b & (1 << (i % 8)) != 0).unwrap_or(false)
        }
        None => !seeded,
    }
}

pub fn is_seeded(ctx: &ReducerContext) -> bool {
    ctx.db.world_seed().id().find(0).map(|s| s.state == "ready").unwrap_or(false)
}

pub fn spawn_point(ctx: &ReducerContext) -> (u8, f32, f32) {
    match ctx.db.world_seed().id().find(0) {
        Some(s) if s.state == "ready" => (s.spawn_map, s.spawn_x as f32 + 0.5, s.spawn_y as f32 + 0.5),
        _ => (MAP_SURFACE, 128.5, 128.5),
    }
}

/// The portal on (map, tile), via the composite index (no table scan in the tick).
pub fn portal_at(ctx: &ReducerContext, map_id: u8, tx: i32, ty: i32) -> Option<Portal> {
    if tx < 0 || ty < 0 || tx > u16::MAX as i32 || ty > u16::MAX as i32 {
        return None;
    }
    ctx.db.portal().portal_by_tile().filter((map_id, tx as u16, ty as u16)).next()
}

/// Where you land when you walk off the edge of `from_map`: the seeded `map_exit` tile if any,
/// else next to the first portal that leads into the map, preferring the side you walked out of.
pub fn exit_target(ctx: &ReducerContext, from_map: u8, dir: (i32, i32), seeded: bool) -> Option<(u8, f32, f32)> {
    let (to_map, px, py) = match ctx.db.map_exit().map_id().find(from_map) {
        Some(e) => (e.to_map, e.x as i32, e.y as i32),
        None => {
            // Rare path (only when the adapter seeds no map_exit); the portal table is small.
            let p = ctx.db.portal().iter().find(|p| p.to_map == from_map && p.from_map != from_map)?;
            (p.from_map, p.x as i32, p.y as i32)
        }
    };
    let mut cands: Vec<(i32, i32)> = vec![(px + dir.0, py + dir.1)];
    for r in 1i32..=3 {
        for dy in -r..=r {
            for dx in -r..=r {
                if dx.abs().max(dy.abs()) == r {
                    cands.push((px + dx, py + dy));
                }
            }
        }
    }
    cands
        .into_iter()
        .find(|&(x, y)| walkable(ctx, to_map, x, y, seeded) && portal_at(ctx, to_map, x, y).is_none())
        .map(|(x, y)| (to_map, x as f32 + 0.5, y as f32 + 0.5))
}

/// Safe zones of each map, loaded once per tick pass.
pub struct SafeZones(BTreeMap<u8, Vec<(i32, i32, i32)>>);

impl SafeZones {
    pub fn load(ctx: &ReducerContext) -> Self {
        let mut m: BTreeMap<u8, Vec<(i32, i32, i32)>> = BTreeMap::new();
        for z in ctx.db.safe_zone().iter() {
            m.entry(z.map_id).or_default().push((z.x as i32, z.y as i32, z.r as i32));
        }
        SafeZones(m)
    }
    pub fn contains(&self, map_id: u8, x: i32, y: i32) -> bool {
        self.0.get(&map_id).map(|v| v.iter().any(|&(cx, cy, r)| in_circle(x, y, cx, cy, r))).unwrap_or(false)
    }
}

/// Bodies per tile for this tick (players, NPCs, monsters). Counts, not a set, because several
/// players may legitimately share a tile after placement (spawn, portal arrival).
#[derive(Default)]
pub struct Occupancy {
    m: BTreeMap<(u8, i32, i32), u16>,
    pub active_maps: BTreeSet<u8>,
}

impl Occupancy {
    pub fn add(&mut self, map: u8, t: (i32, i32)) {
        *self.m.entry((map, t.0, t.1)).or_insert(0) += 1;
    }
    pub fn remove(&mut self, map: u8, t: (i32, i32)) {
        if let Some(c) = self.m.get_mut(&(map, t.0, t.1)) {
            *c = c.saturating_sub(1);
            if *c == 0 {
                self.m.remove(&(map, t.0, t.1));
            }
        }
    }
    pub fn has(&self, map: u8, t: (i32, i32)) -> bool {
        self.m.contains_key(&(map, t.0, t.1))
    }
    pub fn moved(&mut self, map: u8, from: (i32, i32), to: (i32, i32)) {
        if from != to {
            self.remove(map, from);
            self.add(map, to);
        }
    }
}
