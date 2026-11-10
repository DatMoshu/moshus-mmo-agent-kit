//! The fixed-rate tick: player movement (tile collision + body blocking + portals + town exits),
//! then the scheduled passes of the other systems, then the load-health signal.

use spacetimedb::{reducer, ReducerContext, Table};

use super::maps::*;
use super::rules::*;
use super::tables::*;
use super::{combat, items, npc as npc_sys};

pub fn place(ctx: &ReducerContext, t: EntityTransform, map_id: u8, x: f32, y: f32, seq: u32) {
    let id = t.identity;
    ctx.db.entity_transform().identity().update(EntityTransform {
        map_id,
        x,
        y,
        cell_x: cell_of(x),
        cell_y: cell_of(y),
        moving: false,
        last_input_seq: seq,
        ..t
    });
    if let Some(i) = ctx.db.player_input().identity().find(id) {
        ctx.db.player_input().identity().update(PlayerInput { dir_x: 0, dir_y: 0, ..i });
    }
}

/// Bodies on every map that has an online player (only those maps run NPC/monster AI).
pub fn build_occupancy(ctx: &ReducerContext, players: &[EntityTransform]) -> Occupancy {
    let mut occ = Occupancy::default();
    for t in players {
        occ.active_maps.insert(t.map_id);
        occ.add(t.map_id, tile_of(t.x, t.y));
    }
    let maps: Vec<u8> = occ.active_maps.iter().copied().collect();
    for m in maps {
        for meta in ctx.db.npc_meta().map_id().filter(m) {
            if let Some(n) = ctx.db.npc().id().find(meta.id) {
                if n.tile != 0 {
                    occ.add(m, tile_of(n.x, n.y));
                }
            }
        }
        for mon in ctx.db.monster().map_id().filter(m) {
            occ.add(m, tile_of(mon.x, mon.y));
        }
    }
    occ
}

#[reducer]
pub fn tick(ctx: &ReducerContext, _row: TickSchedule) -> Result<(), String> {
    // Entry guard dominates both branches: a project dispatcher can never skip it.
    if ctx.sender() != ctx.database_identity() {
        return Err("tick is scheduler-only".into());
    }
    // Optional project-owned dispatch (default off). The parameter stays named `_row`: the
    // reducer's exported argument names are part of the schema.
    #[cfg(feature = "project-tick")]
    {
        crate::project_tick::dispatch(ctx, _row)
    }
    #[cfg(not(feature = "project-tick"))]
    {
        tick_body(ctx, _row)
    }
}

/// The simulation body. Not a reducer; a project dispatcher continues into it (never into `tick`,
/// which would recurse). It keeps its own scheduler-only guard for internal callers.
pub fn tick_body(ctx: &ReducerContext, _row: TickSchedule) -> Result<(), String> {
    // Scheduled reducers are ordinary reducers: without this guard any client could call tick.
    if ctx.sender() != ctx.database_identity() {
        return Err("tick is scheduler-only".into());
    }
    let Some(health) = ctx.db.tick_health().id().find(0) else {
        return Err("tick_health missing; run ensure_world".into());
    };

    let interval = tick_interval_us();
    let elapsed = ctx
        .timestamp
        .time_duration_since(health.last_tick_at)
        .map(|d| d.to_micros())
        .unwrap_or(interval);
    let lateness = (elapsed - interval).max(0);
    // Clamp dt so a stalled world does not teleport everyone on the next tick.
    let dt = (elapsed.clamp(0, interval * 3) as f32) / 1_000_000.0;
    let tick_count = health.tick_count + 1;

    let seeded = is_seeded(ctx);
    // Movement speed of this database (task 1449): world_config.max_speed, MAX_SPEED when missing or invalid.
    let speed = speed_or_default(ctx.db.world_config().id().find(0).map(|c| c.max_speed));
    // Online entities only (transform rows exist only while online), not every player ever.
    let online_now: Vec<EntityTransform> = ctx.db.entity_transform().iter().collect();
    let mut occ = build_occupancy(ctx, &online_now);

    // --- required work: integrate movement intents ---
    let mut moved: u32 = 0;
    for t in online_now {
        let Some(input) = ctx.db.player_input().identity().find(t.identity) else { continue };
        let still = input.dir_x == 0 && input.dir_y == 0;
        if still {
            if t.moving || t.last_input_seq != input.seq {
                ctx.db.entity_transform().identity().update(EntityTransform { moving: false, last_input_seq: input.seq, ..t });
            }
            continue;
        }
        let (mut dx, mut dy) = (input.dir_x as f32, input.dir_y as f32);
        if dx != 0.0 && dy != 0.0 {
            dx *= std::f32::consts::FRAC_1_SQRT_2;
            dy *= std::f32::consts::FRAC_1_SQRT_2;
        }
        let Some((w, h, exit_at_edge)) = map_dims(ctx, t.map_id) else { continue };
        let (sx, sy) = step_delta(dx, dy, speed, dt); // under one tile per axis (MAX_STEP)
        let (nx, ny) = (t.x + sx, t.y + sy);
        let cur = tile_of(t.x, t.y);
        let (cur_tx, cur_ty) = cur;
        let (ntx, nty) = (nx.floor() as i32, ny.floor() as i32);

        // Town edge: leaving the map returns you to the parent map next to the entrance.
        let outside = ntx < 0 || nty < 0 || ntx >= w as i32 || nty >= h as i32;
        if outside && exit_at_edge {
            if let Some((m, ex, ey)) = exit_target(ctx, t.map_id, (input.dir_x as i32, input.dir_y as i32), seeded) {
                occ.remove(t.map_id, cur);
                place(ctx, t, m, ex, ey, input.seq);
                moved += 1;
                continue;
            }
        }
        // Collision with per-axis sliding (rules::slide): try the full step, then x only, then y only.
        // A different tile must be walkable terrain AND free of bodies (players, NPCs, monsters).
        let map_id = t.map_id;
        let ok = |x: i32, y: i32| {
            (x == cur_tx && y == cur_ty) || (walkable(ctx, map_id, x, y, seeded) && !occ.has(map_id, (x, y)))
        };
        let (x, y) = slide(t.x, t.y, nx, ny, ok);
        let x = x.clamp(0.0, w as f32 - 0.001);
        let y = y.clamp(0.0, h as f32 - 0.001);
        let new_tile = tile_of(x, y);
        // Portal: entering a new tile that is a portal moves you to its target.
        if new_tile != cur {
            if let Some(p) = portal_at(ctx, map_id, new_tile.0, new_tile.1) {
                occ.remove(map_id, cur);
                place(ctx, t, p.to_map, p.to_x as f32 + 0.5, p.to_y as f32 + 0.5, input.seq);
                moved += 1;
                continue;
            }
        }
        if x == t.x && y == t.y {
            if t.moving || t.last_input_seq != input.seq {
                ctx.db.entity_transform().identity().update(EntityTransform { moving: false, last_input_seq: input.seq, ..t });
            }
            continue; // blocked: no row update, no fan-out
        }
        occ.moved(map_id, cur, new_tile);
        ctx.db.entity_transform().identity().update(EntityTransform {
            x,
            y,
            cell_x: cell_of(x),
            cell_y: cell_of(y),
            moving: true,
            last_input_seq: input.seq,
            ..t
        });
        moved += 1;
    }

    // --- health: scheduler lateness is the cheapest honest load signal inside a module ---
    let avg = (health.avg_lateness_us * 7 + lateness) / 8;
    let level: u8 = match avg {
        a if a < interval / 4 => 0,
        a if a < interval / 2 => 1,
        a if a < interval => 2,
        _ => 3,
    };

    // --- world simulation. Monster attacks are core gameplay and keep running at level 2;
    // ambient work (NPC wander, natural spawns, regen, decay) is shed first (R25). ---
    if level < 3 && tick_count % MONSTER_EVERY == 0 {
        combat::monster_pass(ctx, tick_count, &mut occ, seeded);
    }
    if level < 2 && tick_count % NPC_EVERY == 0 {
        npc_sys::wander_pass(ctx, &mut occ, seeded);
    }
    let mut online = health.online_players;
    if level < 2 && tick_count % HOUSEKEEPING_EVERY == 0 {
        online = ctx.db.player().iter().filter(|p| p.online).count() as u32;
        combat::spawn_pass(ctx, tick_count, &occ, seeded);
        combat::regen_pass(ctx, tick_count);
        items::decay_pass(ctx, tick_count);
    }

    ctx.db.tick_health().id().update(TickHealth {
        tick_count,
        last_tick_at: ctx.timestamp,
        last_lateness_us: lateness,
        avg_lateness_us: avg,
        max_lateness_us: health.max_lateness_us.max(lateness),
        moved_last_tick: moved,
        online_players: online,
        level,
        ..health
    });
    Ok(())
}
