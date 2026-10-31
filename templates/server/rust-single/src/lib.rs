//! Moshu's MMO Agent Kit: single-module world starter (SpacetimeDB 2.14).
//!
//! What this module shows, in the smallest amount of code that still scales:
//! - server-authoritative movement: clients send *intent* (a direction), the tick moves them
//! - a fixed-rate scheduled tick that guards itself against client calls
//! - a self-measuring `tick_health` row (lateness of the scheduler = load signal)
//! - a narrow, public "hot" table (`entity_transform`) with a cell index for AOI subscriptions
//! - private tables for inputs and admission, an admin identity, idempotent `ensure_world`
//!
//! Rules this file follows are in `rules/rust-module.md` at the kit root.

use spacetimedb::{reducer, table, Identity, ReducerContext, ScheduleAt, Table, TimeDuration, Timestamp};

/// Bump when you add tables/columns that need a backfill in `ensure_world`.
pub const SCHEMA_VERSION: u32 = 1;
pub const TICK_HZ: u32 = 20;
pub const WORLD_HALF: f32 = 500.0; // world is the square [-WORLD_HALF, WORLD_HALF]^2
pub const CELL_SIZE: f32 = 50.0; // AOI cell edge, roughly view radius / 1.5
pub const MAX_SPEED: f32 = 8.0; // world units per second
pub const NAME_MAX_CHARS: usize = 24;
/// Every this many ticks the optional housekeeping pass runs (skipped when the world is hot).
pub const HOUSEKEEPING_EVERY: u64 = 40;

// ---------------------------------------------------------------------------------------------
// Tables
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

/// Cold, wide-ish row: changes rarely (join, rename, online flag).
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

/// Hot, narrow row: the only thing that changes every tick. Subscribe to it by cell.
#[table(
    accessor = entity_transform,
    public,
    index(accessor = by_cell, btree(columns = [cell_x, cell_y]))
)]
pub struct EntityTransform {
    #[primary_key]
    pub identity: Identity,
    pub x: f32,
    pub y: f32,
    pub cell_x: i32,
    pub cell_y: i32,
    pub moving: bool,
    pub last_input_seq: u32,
}

/// Scheduler row for the fixed-rate tick.
#[table(accessor = tick_schedule, scheduled(tick))]
pub struct TickSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

/// Singleton (id = 0). Public so dashboards, bots and the load-test gate can read it.
/// level: 0 = green, 1 = yellow, 2 = orange (optional work shed), 3 = red.
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
// Helpers
// ---------------------------------------------------------------------------------------------

fn config(ctx: &ReducerContext) -> Result<WorldConfig, String> {
    ctx.db.world_config().id().find(0).ok_or_else(|| "world not initialised".to_string())
}

fn is_admin(ctx: &ReducerContext) -> bool {
    config(ctx).map(|c| c.admin == ctx.sender()).unwrap_or(false)
}

fn require_admin(ctx: &ReducerContext) -> Result<(), String> {
    if is_admin(ctx) { Ok(()) } else { Err("admin only".into()) }
}

/// Admission is enforced on connect AND in every reducer: revoking a row does not close a socket.
fn require_admitted(ctx: &ReducerContext) -> Result<(), String> {
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

fn cell_of(v: f32) -> i32 {
    (v / CELL_SIZE).floor() as i32
}

fn tick_interval_us() -> i64 {
    1_000_000 / TICK_HZ as i64
}

fn valid_name(name: &str) -> bool {
    let n = name.chars().count();
    n >= 1
        && n <= NAME_MAX_CHARS
        && name.chars().all(|c| c.is_alphanumeric() || c == ' ' || c == '_' || c == '-')
        && name.trim() == name
}

// ---------------------------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------------------------

/// Runs once, on the first publish (or after --delete-data). Everything it does is also in
/// `ensure_world`, because additive publishes never re-run init.
#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ensure_world_inner(ctx, ctx.sender());
}

#[reducer(client_connected)]
pub fn on_connect(ctx: &ReducerContext) -> Result<(), String> {
    require_admitted(ctx)?;
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        ctx.db.player().identity().update(Player { online: true, last_seen: ctx.timestamp, ..p });
    }
    Ok(())
}

#[reducer(client_disconnected)]
pub fn on_disconnect(ctx: &ReducerContext) {
    // Only online players have a transform row, so subscribers never see offline "ghosts".
    let pos = ctx.db.entity_transform().identity().find(ctx.sender());
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        let (last_x, last_y) = pos.as_ref().map(|t| (t.x, t.y)).unwrap_or((p.last_x, p.last_y));
        ctx.db.player().identity().update(Player { online: false, last_seen: ctx.timestamp, last_x, last_y, ..p });
    }
    ctx.db.entity_transform().identity().delete(ctx.sender());
    if let Some(i) = ctx.db.player_input().identity().find(ctx.sender()) {
        ctx.db.player_input().identity().update(PlayerInput { dir_x: 0, dir_y: 0, ..i });
    }
}

// ---------------------------------------------------------------------------------------------
// Player reducers
// ---------------------------------------------------------------------------------------------

/// Create (or rename) the caller's player and spawn them near the origin.
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
    let (x, y) = match ctx.db.player().identity().find(me) {
        Some(p) => {
            let spawn = (p.last_x, p.last_y); // returning player resumes where they logged out
            ctx.db.player().identity().update(Player { name, online: true, last_seen: ctx.timestamp, ..p });
            spawn
        }
        None => {
            // ctx.random() is the module's deterministic RNG; never use std or thread RNGs.
            let x = (ctx.random::<u32>() % 41) as f32 - 20.0;
            let y = (ctx.random::<u32>() % 41) as f32 - 20.0;
            ctx.db.player().try_insert(Player {
                identity: me,
                name,
                online: true,
                created_at: ctx.timestamp,
                last_seen: ctx.timestamp,
                last_x: x,
                last_y: y,
            })?;
            (x, y)
        }
    };
    if ctx.db.entity_transform().identity().find(me).is_none() {
        ctx.db.entity_transform().insert(EntityTransform {
            identity: me,
            x,
            y,
            cell_x: cell_of(x),
            cell_y: cell_of(y),
            moving: false,
            last_input_seq: 0,
        });
    }
    if ctx.db.player_input().identity().find(me).is_none() {
        ctx.db.player_input().insert(PlayerInput { identity: me, dir_x: 0, dir_y: 0, seq: 0 });
    }
    Ok(())
}

/// Movement intent. Each axis is -1, 0 or 1; the tick applies speed and bounds.
/// `seq` lets the client match server state to its own prediction (reconciliation).
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

// ---------------------------------------------------------------------------------------------
// Tick
// ---------------------------------------------------------------------------------------------

#[reducer]
pub fn tick(ctx: &ReducerContext, _row: TickSchedule) -> Result<(), String> {
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

    // --- required work: integrate movement intents ---
    let mut moved: u32 = 0;
    // Iterate online entities (transform rows exist only while online), not every player ever.
    let online_now: Vec<EntityTransform> = ctx.db.entity_transform().iter().collect();
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
        let x = (t.x + dx * MAX_SPEED * dt).clamp(-WORLD_HALF, WORLD_HALF);
        let y = (t.y + dy * MAX_SPEED * dt).clamp(-WORLD_HALF, WORLD_HALF);
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
    let tick_count = health.tick_count + 1;

    // --- optional work: shed it first when the world is hot (level >= 2) ---
    let mut online = health.online_players;
    if level < 2 && tick_count % HOUSEKEEPING_EVERY == 0 {
        online = ctx.db.player().iter().filter(|p| p.online).count() as u32;
        // Put regeneration, ambient AI, decay, etc. here, batched and bounded.
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

// ---------------------------------------------------------------------------------------------
// Admin / ops
// ---------------------------------------------------------------------------------------------

/// Idempotent: safe to call after every publish. Creates missing singletons and the schedule.
#[reducer]
pub fn ensure_world(ctx: &ReducerContext) -> Result<(), String> {
    require_admin(ctx)?;
    let admin = config(ctx)?.admin;
    ensure_world_inner(ctx, admin);
    Ok(())
}

fn ensure_world_inner(ctx: &ReducerContext, admin: Identity) {
    match ctx.db.world_config().id().find(0) {
        None => {
            ctx.db.world_config().insert(WorldConfig {
                id: 0,
                admin,
                admission_open: true,
                tick_hz: TICK_HZ,
                max_speed: MAX_SPEED,
                cell_size: CELL_SIZE,
                world_half: WORLD_HALF,
                schema_version: SCHEMA_VERSION,
            });
        }
        Some(c) if c.schema_version < SCHEMA_VERSION => {
            // Backfills for new schema versions go here, then bump the stored version.
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
    if ctx.db.tick_schedule().count() == 0 {
        ctx.db.tick_schedule().insert(TickSchedule {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Interval(TimeDuration::from_micros(tick_interval_us())),
        });
    }
}

/// Close or open the world. Closed = only admin + allowlisted identities may connect or act.
#[reducer]
pub fn set_admission_open(ctx: &ReducerContext, open: bool) -> Result<(), String> {
    require_admin(ctx)?;
    let c = config(ctx)?;
    ctx.db.world_config().id().update(WorldConfig { admission_open: open, ..c });
    Ok(())
}

/// Idempotent grant.
#[reducer]
pub fn allow_identity(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.allowlist().identity().find(identity).is_none() {
        ctx.db.allowlist().insert(Allowlist { identity, granted_at: ctx.timestamp });
    }
    Ok(())
}

/// Idempotent revoke. The revoked client's socket stays open until it reconnects, but every
/// reducer it calls now fails `require_admitted`.
#[reducer]
pub fn revoke_identity(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    ctx.db.allowlist().identity().delete(identity);
    if let Some(i) = ctx.db.player_input().identity().find(identity) {
        ctx.db.player_input().identity().update(PlayerInput { dir_x: 0, dir_y: 0, ..i });
    }
    Ok(())
}
