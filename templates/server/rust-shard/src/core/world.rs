//! Lifecycle, admission, admin, join and movement intent.

use spacetimedb::{reducer, Identity, ReducerContext, ScheduleAt, Table, TimeDuration};

use super::combat::ensure_stats;
use super::maps::{spawn_point, walkable, is_seeded};
use super::rules::*;
use super::tables::*;

pub fn config(ctx: &ReducerContext) -> Result<WorldConfig, String> {
    ctx.db.world_config().id().find(0).ok_or_else(|| "world not initialised".to_string())
}

pub fn is_admin(ctx: &ReducerContext) -> bool {
    config(ctx).map(|c| c.admin == ctx.sender()).unwrap_or(false)
}

pub fn require_admin(ctx: &ReducerContext) -> Result<(), String> {
    if is_admin(ctx) { Ok(()) } else { Err("admin only".into()) }
}

/// Admission is enforced on connect AND in every reducer: revoking a row does not close a socket.
pub fn require_admitted(ctx: &ReducerContext) -> Result<(), String> {
    let cfg = config(ctx)?;
    if cfg.admission_open
        || cfg.admin == ctx.sender()
        || ctx.db.allowlist().identity().find(ctx.sender()).is_some()
    {
        Ok(())
    } else {
        Err("not admitted".into())
    }
}

/// The caller's live transform (they must have joined and be online).
pub fn require_online(ctx: &ReducerContext) -> Result<EntityTransform, String> {
    require_admitted(ctx)?;
    ctx.db.entity_transform().identity().find(ctx.sender()).ok_or_else(|| "call join first".to_string())
}

pub fn current_tick(ctx: &ReducerContext) -> u64 {
    ctx.db.tick_health().id().find(0).map(|h| h.tick_count).unwrap_or(0)
}

#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ensure_world_inner(ctx, ctx.sender());
}

#[reducer(client_connected)]
pub fn on_connect(ctx: &ReducerContext) -> Result<(), String> {
    require_admitted(ctx)?;
    ensure_level_table(ctx); // worlds published before `level_xp` existed
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        ctx.db.player().identity().update(Player { online: true, last_seen: ctx.timestamp, ..p });
    }
    Ok(())
}

#[reducer(client_disconnected)]
pub fn on_disconnect(ctx: &ReducerContext) {
    // Only online players have a transform row, so subscribers never see offline "ghosts".
    // Position is saved here; stats and inventory live in their own rows and persist as-is.
    let pos = ctx.db.entity_transform().identity().find(ctx.sender());
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        let (last_map, last_x, last_y) =
            pos.as_ref().map(|t| (t.map_id, t.x, t.y)).unwrap_or((p.last_map, p.last_x, p.last_y));
        ctx.db.player().identity().update(Player { online: false, last_seen: ctx.timestamp, last_map, last_x, last_y, ..p });
    }
    ctx.db.entity_transform().identity().delete(ctx.sender());
    if let Some(i) = ctx.db.player_input().identity().find(ctx.sender()) {
        ctx.db.player_input().identity().update(PlayerInput { dir_x: 0, dir_y: 0, ..i });
    }
}

/// Create (or rename) the caller's player; a returning player resumes where they logged out.
#[reducer]
pub fn join(ctx: &ReducerContext, name: String) -> Result<(), String> {
    require_admitted(ctx)?;
    if !valid_name(&name) {
        return Err(format!("name must be 1-{NAME_MAX_CHARS} letters, digits, space, _ or -"));
    }
    if let Some(other) = ctx.db.player().name().find(&name) {
        if other.identity != ctx.sender() {
            return Err("name taken".into());
        }
    }
    let me = ctx.sender();
    let seeded = is_seeded(ctx);
    let (map_id, x, y) = match ctx.db.player().identity().find(me) {
        Some(p) => {
            let spot = if walkable(ctx, p.last_map, p.last_x.floor() as i32, p.last_y.floor() as i32, seeded) {
                (p.last_map, p.last_x, p.last_y)
            } else {
                spawn_point(ctx)
            };
            ctx.db.player().identity().update(Player { name, online: true, last_seen: ctx.timestamp, ..p });
            spot
        }
        None => {
            // New players start on the seeded spawn tile. Placement may overlap; body blocking
            // only stops you from WALKING into an occupied tile, so a crowd can always disperse.
            let (m, x, y) = spawn_point(ctx);
            ctx.db.player().try_insert(Player {
                identity: me,
                name,
                online: true,
                created_at: ctx.timestamp,
                last_seen: ctx.timestamp,
                last_x: x,
                last_y: y,
                last_map: m,
            })?;
            (m, x, y)
        }
    };
    if ctx.db.entity_transform().identity().find(me).is_none() {
        ctx.db.entity_transform().insert(EntityTransform {
            identity: me,
            map_id,
            x,
            y,
            cell_x: cell_of(x),
            cell_y: cell_of(y),
            moving: false,
            last_input_seq: 0,
        });
    }
    // A new session restarts its intent counter at 1, so a returning player's old seq must not make
    // set_input ignore every move of the new session as stale.
    if let Some(i) = ctx.db.player_input().identity().find(me) {
        ctx.db.player_input().identity().update(PlayerInput { dir_x: 0, dir_y: 0, seq: 0, ..i });
    } else {
        ctx.db.player_input().insert(PlayerInput { identity: me, dir_x: 0, dir_y: 0, seq: 0 });
    }
    ensure_stats(ctx, me);
    Ok(())
}

/// Movement intent. Each axis is -1, 0 or 1; the tick applies speed, collision and bounds.
#[reducer]
pub fn set_input(ctx: &ReducerContext, dir_x: i8, dir_y: i8, seq: u32) -> Result<(), String> {
    require_admitted(ctx)?;
    let me = ctx.sender();
    let Some(input) = ctx.db.player_input().identity().find(me) else {
        return Err("call join first".into());
    };
    if seq != 0 && seq < input.seq {
        return Ok(()); // stale/out-of-order intent: ignore, do not error
    }
    ctx.db.player_input().identity().update(PlayerInput {
        dir_x: dir_x.clamp(-1, 1),
        dir_y: dir_y.clamp(-1, 1),
        seq,
        ..input
    });
    Ok(())
}

/// Idempotent: safe to call after every publish. Creates missing singletons and the schedule.
#[reducer]
pub fn ensure_world(ctx: &ReducerContext) -> Result<(), String> {
    require_admin(ctx)?;
    let admin = config(ctx)?.admin;
    ensure_world_inner(ctx, admin);
    Ok(())
}

pub fn ensure_world_inner(ctx: &ReducerContext, admin: Identity) {
    match ctx.db.world_config().id().find(0) {
        None => {
            ctx.db.world_config().insert(WorldConfig {
                id: 0,
                admin,
                admission_open: true,
                tick_hz: TICK_HZ,
                max_speed: speed_or_default(Some(MAX_SPEED)), // the stored value is the one the tick uses
                cell_size: CELL_SIZE,
                world_half: WORLD_HALF,
                schema_version: SCHEMA_VERSION,
            });
        }
        Some(c) if c.schema_version < SCHEMA_VERSION => {
            // v2: stats rows for players created before combat existed (bounded by player count,
            // admin-triggered, runs once).
            let ids: Vec<Identity> = ctx.db.player().iter().map(|p| p.identity).collect();
            for id in ids {
                ensure_stats(ctx, id);
            }
            ctx.db.world_config().id().update(WorldConfig { schema_version: SCHEMA_VERSION, ..c });
        }
        Some(_) => {}
    }
    if ctx.db.tick_health().id().find(0).is_none() {
        ctx.db.tick_health().insert(TickHealth {
            id: 0,
            tick_count: 0,
            last_tick_at: ctx.timestamp,
            last_lateness_us: 0,
            avg_lateness_us: 0,
            max_lateness_us: 0,
            moved_last_tick: 0,
            online_players: 0,
            level: 0,
        });
    }
    ensure_level_table(ctx);
    if ctx.db.tick_schedule().count() == 0 {
        ctx.db.tick_schedule().insert(TickSchedule {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Interval(TimeDuration::from_micros(tick_interval_us())),
        });
    }
}

#[reducer]
pub fn set_admission_open(ctx: &ReducerContext, open: bool) -> Result<(), String> {
    require_admin(ctx)?;
    let c = config(ctx)?;
    ctx.db.world_config().id().update(WorldConfig { admission_open: open, ..c });
    Ok(())
}

#[reducer]
pub fn allow_identity(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.allowlist().identity().find(identity).is_none() {
        ctx.db.allowlist().insert(Allowlist { identity, granted_at: ctx.timestamp });
    }
    Ok(())
}

#[reducer]
pub fn revoke_identity(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    ctx.db.allowlist().identity().delete(identity);
    if let Some(i) = ctx.db.player_input().identity().find(identity) {
        ctx.db.player_input().identity().update(PlayerInput { dir_x: 0, dir_y: 0, ..i });
    }
    Ok(())
}

/// Fill the public `level_xp` table from the core rules (once; cheap check afterwards).
pub fn ensure_level_table(ctx: &ReducerContext) {
    if ctx.db.level_xp().level().find(LEVEL_TABLE_MAX).is_some() {
        return;
    }
    for level in 1..=LEVEL_TABLE_MAX {
        if ctx.db.level_xp().level().find(level).is_none() {
            let xp = (level - 1) * XP_PER_LEVEL;
            ctx.db.level_xp().insert(LevelXp { level, xp, max_hp: max_hp_for_level(level) });
        }
    }
}
