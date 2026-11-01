//! Simple PvE: monsters spawn near players outside safe zones, chase and hit adjacent players;
//! players `attack` an adjacent monster. Death respawns you at the nearest respawn point.

use spacetimedb::{reducer, Identity, ReducerContext, Table};

use super::items::drop_item;
use super::maps::*;
use super::movement::place;
use super::rules::*;
use super::tables::*;
use super::world::{current_tick, require_admin, require_online};

pub const GOLD: u16 = 0;

pub fn ensure_stats(ctx: &ReducerContext, id: Identity) {
    if ctx.db.player_stats().identity().find(id).is_none() {
        let max_hp = max_hp_for_level(1);
        ctx.db.player_stats().insert(PlayerStats { identity: id, hp: max_hp, max_hp, xp: 0, level: 1, gold: 0, kills: 0, deaths: 0 });
    }
    if ctx.db.player_combat().identity().find(id).is_none() {
        ctx.db.player_combat().insert(PlayerCombat { identity: id, last_attack_tick: 0, last_hurt_tick: 0 });
    }
}

fn insert_monster(ctx: &ReducerContext, map_id: u8, tx: i32, ty: i32, k: &MonsterKind, tick: u64) -> u64 {
    let (x, y) = (tx as f32 + 0.5, ty as f32 + 0.5);
    let m = ctx.db.monster().insert(Monster {
        id: 0,
        map_id,
        kind: k.kind,
        tile: k.tile,
        x,
        y,
        cell_x: cell_of(x),
        cell_y: cell_of(y),
        hp: k.hp,
        max_hp: k.hp,
    });
    ctx.db.monster_brain().insert(MonsterBrain { id: m.id, home_x: tx, home_y: ty, next_act_tick: tick + k.step_ticks as u64 });
    m.id
}

fn remove_monster(ctx: &ReducerContext, id: u64) {
    ctx.db.monster().id().delete(id);
    ctx.db.monster_brain().id().delete(id);
}

/// Melee the monster `target_id` (must be on an adjacent tile). 0.5 s cooldown.
#[reducer]
pub fn attack(ctx: &ReducerContext, target_id: u64) -> Result<(), String> {
    let t = require_online(ctx)?;
    let me = ctx.sender();
    ensure_stats(ctx, me);
    let tick = current_tick(ctx);
    let cmb = ctx.db.player_combat().identity().find(me).ok_or("no combat row")?;
    if cmb.last_attack_tick != 0 && tick < cmb.last_attack_tick + ATTACK_COOLDOWN_TICKS {
        return Err("too soon".into());
    }
    let mon = ctx.db.monster().id().find(target_id).ok_or("no such monster")?;
    if mon.map_id != t.map_id || !in_melee(tile_of(t.x, t.y), tile_of(mon.x, mon.y)) {
        return Err("not adjacent".into());
    }
    let stats = ctx.db.player_stats().identity().find(me).ok_or("no stats")?;
    if stats.hp <= 0 {
        return Err("you are dead".into());
    }
    ctx.db.player_combat().identity().update(PlayerCombat { last_attack_tick: tick.max(1), ..cmb });
    let (lo, hi) = player_damage(stats.level);
    let dmg = roll(ctx.random(), lo, hi);
    if mon.hp > dmg {
        ctx.db.monster().id().update(Monster { hp: mon.hp - dmg, ..mon });
        return Ok(());
    }
    // Kill: XP, level, loot on the monster's tile.
    let kind = ctx.db.monster_kind().kind().find(mon.kind);
    let (xp_gain, gmin, gmax) = kind.as_ref().map(|k| (k.xp, k.gold_min, k.gold_max)).unwrap_or((5, 1, 5));
    let xp = stats.xp + xp_gain;
    let level = level_for_xp(xp);
    let max_hp = max_hp_for_level(level);
    let hp = if level > stats.level { max_hp } else { stats.hp };
    ctx.db.player_stats().identity().update(PlayerStats { xp, level, max_hp, hp, kills: stats.kills + 1, ..stats });
    let (mx, my) = tile_of(mon.x, mon.y);
    let gold = roll(ctx.random(), gmin as i32, gmax as i32).max(0) as u32;
    if gold > 0 {
        drop_item(ctx, mon.map_id, mx, my, GOLD, gold, tick);
    }
    // 1 in 4 kills also drops a usable item (the first healing kind the adapter seeded).
    if ctx.random::<u32>() % 4 == 0 {
        if let Some(k) = ctx.db.item_kind().iter().find(|k| k.heal > 0) {
            drop_item(ctx, mon.map_id, mx, my, k.kind, 1, tick);
        }
    }
    remove_monster(ctx, mon.id);
    Ok(())
}

fn hurt_player(ctx: &ReducerContext, who: Identity, dmg: i32, tick: u64) {
    let Some(s) = ctx.db.player_stats().identity().find(who) else { return };
    if let Some(c) = ctx.db.player_combat().identity().find(who) {
        ctx.db.player_combat().identity().update(PlayerCombat { last_hurt_tick: tick, ..c });
    }
    if s.hp > dmg {
        ctx.db.player_stats().identity().update(PlayerStats { hp: s.hp - dmg, ..s });
        return;
    }
    // Death: full heal, respawn at the nearest respawn point (same map first).
    ctx.db.player_stats().identity().update(PlayerStats { hp: s.max_hp, deaths: s.deaths + 1, ..s });
    if let Some(t) = ctx.db.entity_transform().identity().find(who) {
        let (m, x, y) = respawn_for(ctx, t.map_id, t.x, t.y);
        let seq = t.last_input_seq;
        place(ctx, t, m, x, y, seq);
    }
}

pub fn respawn_for(ctx: &ReducerContext, map_id: u8, x: f32, y: f32) -> (u8, f32, f32) {
    // (id, map, x, y); first = lowest id overall, best = nearest on this map.
    let mut best: Option<(f32, (u8, u16, u16))> = None;
    let mut first: Option<(u32, (u8, u16, u16))> = None;
    for r in ctx.db.respawn_point().iter() {
        let spot = (r.map_id, r.x, r.y);
        if first.map(|(id, _)| r.id < id).unwrap_or(true) {
            first = Some((r.id, spot));
        }
        if r.map_id == map_id {
            let d = (r.x as f32 - x).powi(2) + (r.y as f32 - y).powi(2);
            if best.map(|(bd, _)| d < bd).unwrap_or(true) {
                best = Some((d, spot));
            }
        }
    }
    match best.map(|(_, s)| s).or(first.map(|(_, s)| s)) {
        Some((m, rx, ry)) => (m, rx as f32 + 0.5, ry as f32 + 0.5),
        None => spawn_point(ctx),
    }
}

/// Monster AI: chase and hit the nearest player in aggro range, else drift home.
pub fn monster_pass(ctx: &ReducerContext, tick: u64, occ: &mut Occupancy, seeded: bool) {
    if occ.active_maps.is_empty() {
        return;
    }
    let players: Vec<EntityTransform> = ctx.db.entity_transform().iter().collect();
    let zones = SafeZones::load(ctx);
    let maps: Vec<u8> = occ.active_maps.iter().copied().collect();
    for m in maps {
        let mons: Vec<Monster> = ctx.db.monster().map_id().filter(m).collect();
        for mon in mons {
            let Some(brain) = ctx.db.monster_brain().id().find(mon.id) else { continue };
            if brain.next_act_tick > tick {
                continue;
            }
            let Some(kind) = ctx.db.monster_kind().kind().find(mon.kind) else { continue };
            let here = tile_of(mon.x, mon.y);
            // Nearest living player on this map within aggro range (not inside a safe zone).
            let target = players
                .iter()
                .filter(|p| p.map_id == m)
                .map(|p| (tile_dist(here, tile_of(p.x, p.y)), p))
                .filter(|(d, p)| {
                    let pt = tile_of(p.x, p.y);
                    *d <= kind.aggro as i32 && !zones.contains(m, pt.0, pt.1)
                })
                .min_by_key(|(d, _)| *d)
                .map(|(_, p)| (p.identity, tile_of(p.x, p.y)));
            let mut next = tick + kind.step_ticks.max(1) as u64;
            let goal = match target {
                Some((who, pt)) if in_melee(here, pt) => {
                    let dmg = roll(ctx.random(), kind.dmg_min, kind.dmg_max);
                    hurt_player(ctx, who, dmg, tick);
                    next = tick + kind.attack_ticks.max(1) as u64;
                    None
                }
                Some((_, pt)) => Some(pt),
                None if tile_dist(here, (brain.home_x, brain.home_y)) > 2 => Some((brain.home_x, brain.home_y)),
                None => {
                    let r: u32 = ctx.random();
                    if r % 4 == 0 {
                        let d = DIRS8[((r >> 8) % 8) as usize];
                        Some((here.0 + d.0, here.1 + d.1))
                    } else {
                        None
                    }
                }
            };
            if let Some(goal) = goal {
                for (dx, dy) in steps_toward(here, goal) {
                    let to = (here.0 + dx, here.1 + dy);
                    if walkable(ctx, m, to.0, to.1, seeded)
                        && !occ.has(m, to)
                        && !zones.contains(m, to.0, to.1)
                        && portal_at(ctx, m, to.0, to.1).is_none()
                        && tile_dist(to, (brain.home_x, brain.home_y)) <= MONSTER_LEASH
                    {
                        occ.moved(m, here, to);
                        let (x, y) = (to.0 as f32 + 0.5, to.1 as f32 + 0.5);
                        ctx.db.monster().id().update(Monster { x, y, cell_x: cell_of(x), cell_y: cell_of(y), ..mon });
                        break;
                    }
                }
            }
            ctx.db.monster_brain().id().update(MonsterBrain { next_act_tick: next, ..brain });
        }
    }
}

/// Natural spawning (one per rule per pass) and despawning monsters far from every player.
pub fn spawn_pass(ctx: &ReducerContext, tick: u64, occ: &Occupancy, seeded: bool) {
    let players: Vec<EntityTransform> = ctx.db.entity_transform().iter().collect();
    // Despawn: bounded by MAX_MONSTERS.
    let all: Vec<Monster> = ctx.db.monster().iter().collect();
    let mut alive = all.len();
    for mon in &all {
        let near = players
            .iter()
            .any(|p| p.map_id == mon.map_id && (p.x - mon.x).abs().max((p.y - mon.y).abs()) <= DESPAWN_DIST);
        if !near {
            remove_monster(ctx, mon.id);
            alive -= 1;
        }
    }
    if players.is_empty() {
        return;
    }
    let zones = SafeZones::load(ctx);
    let rules: Vec<SpawnRule> = ctx.db.spawn_rule().iter().collect();
    for rule in rules {
        if alive >= MAX_MONSTERS || !occ.active_maps.contains(&rule.map_id) || rule.kinds.is_empty() {
            continue;
        }
        let on_map = ctx.db.monster().map_id().filter(rule.map_id).count();
        if on_map >= rule.max_alive as usize {
            continue;
        }
        let here: Vec<&EntityTransform> = players.iter().filter(|p| p.map_id == rule.map_id).collect();
        let r: u32 = ctx.random();
        let anchor = here[(r as usize) % here.len()];
        let (px, py) = tile_of(anchor.x, anchor.y);
        // Up to 4 tries at a random ring position.
        for _ in 0..4 {
            let r: u32 = ctx.random();
            let dist = roll(r, rule.min_dist as i32, rule.max_dist.max(rule.min_dist) as i32);
            let side = (r >> 16) % 4;
            let off = roll(r >> 8, -dist, dist);
            let (tx, ty) = match side {
                0 => (px + off, py - dist),
                1 => (px + off, py + dist),
                2 => (px - dist, py + off),
                _ => (px + dist, py + off),
            };
            if walkable(ctx, rule.map_id, tx, ty, seeded)
                && !occ.has(rule.map_id, (tx, ty))
                && !zones.contains(rule.map_id, tx, ty)
                && portal_at(ctx, rule.map_id, tx, ty).is_none()
            {
                let k = rule.kinds[((r >> 24) as usize) % rule.kinds.len()];
                if let Some(kind) = ctx.db.monster_kind().kind().find(k) {
                    insert_monster(ctx, rule.map_id, tx, ty, &kind, tick);
                    alive += 1;
                }
                break;
            }
        }
    }
}

/// Out-of-combat regeneration for online players.
pub fn regen_pass(ctx: &ReducerContext, tick: u64) {
    let online: Vec<Identity> = ctx.db.entity_transform().iter().map(|t| t.identity).collect();
    for id in online {
        let Some(s) = ctx.db.player_stats().identity().find(id) else { continue };
        if s.hp >= s.max_hp {
            continue;
        }
        let hurt = ctx.db.player_combat().identity().find(id).map(|c| c.last_hurt_tick).unwrap_or(0);
        if tick.saturating_sub(hurt) >= REGEN_AFTER_TICKS {
            let hp = (s.hp + 1 + s.max_hp / 20).min(s.max_hp);
            ctx.db.player_stats().identity().update(PlayerStats { hp, ..s });
        }
    }
}

/// Admin/test: put a monster of `kind` on (map, x, y). Used by the playtest harness to make
/// fights and deaths deterministic.
#[reducer]
pub fn op_spawn_monster(ctx: &ReducerContext, map_id: u8, x: u16, y: u16, kind: u8) -> Result<(), String> {
    require_admin(ctx)?;
    let k = ctx.db.monster_kind().kind().find(kind).ok_or("unknown monster kind")?;
    if map_dims(ctx, map_id).is_none() {
        return Err("unknown map".into());
    }
    if ctx.db.monster().count() as usize >= MAX_MONSTERS {
        return Err("monster cap".into());
    }
    insert_monster(ctx, map_id, x as i32, y as i32, &k, current_tick(ctx));
    Ok(())
}

/// Admin/test: remove every live monster.
#[reducer]
pub fn op_clear_monsters(ctx: &ReducerContext) -> Result<(), String> {
    require_admin(ctx)?;
    let ids: Vec<u64> = ctx.db.monster().iter().map(|m| m.id).collect();
    for id in ids {
        remove_monster(ctx, id);
    }
    Ok(())
}
