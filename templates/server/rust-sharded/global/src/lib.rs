//! Moshu's MMO Agent Kit: sharded world, GLOBAL database (SpacetimeDB 2.14).
//!
//! The global database is the directory of the world. It knows which region databases exist, which
//! part of the map each one owns, how many players each has, and which region each player is in.
//! Players connect here first to find their region, then connect to that region to play.
//!
//! Regions talk to this database through 2.14 inter-database communication (IDC): they insert rows
//! into outbox tables, and the rows arrive here as ordinary reducer calls. In those calls
//! `ctx.sender()` is the *sending database's identity*, so every region-only reducer checks it
//! against the `region` table (the allow-list). See `rules/rust-module.md` R8.

use spacetimedb::{reducer, table, view, Identity, ReducerContext, Table, Timestamp, ViewContext};

// ---------------------------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------------------------

/// Singleton (id = 0): who may administer the world.
#[table(accessor = global_config)]
pub struct GlobalConfig {
    #[primary_key]
    pub id: u8,
    pub admin: Identity,
}

/// One row per region database. Public: clients use it to pick a region and show populations.
/// It is also the allow-list for IDC calls from regions.
#[table(accessor = region, public)]
pub struct Region {
    #[primary_key]
    pub region_id: u32,
    #[unique]
    pub db_identity: Identity,
    /// The name clients connect to (the database name the region was published under).
    pub database_name: String,
    /// The region owns world x in [x_min, x_max). Regions split the map into vertical strips.
    pub x_min: f32,
    pub x_max: f32,
    pub population: u32,
    pub last_heartbeat: Timestamp,
}

/// Which region each player is in. Private: exposed per player through the `my_home` view.
#[table(accessor = player_home)]
pub struct PlayerHome {
    #[primary_key]
    pub player: Identity,
    #[index(btree)]
    pub region_id: u32,
    pub updated: Timestamp,
    /// Increases with every move, so a late, out-of-order report can never move a player back.
    pub seq: u64,
}

// ---------------------------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------------------------

/// The caller's current region. A client subscribes to this, and when it changes, it reconnects to
/// the region database named in `region.database_name`.
#[view(accessor = my_home, public)]
fn my_home(ctx: &ViewContext) -> Option<PlayerHome> {
    ctx.db.player_home().player().find(ctx.sender())
}

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

fn require_admin(ctx: &ReducerContext) -> Result<(), String> {
    match ctx.db.global_config().id().find(0) {
        Some(c) if c.admin == ctx.sender() => Ok(()),
        _ => Err("admin only".into()),
    }
}

/// IDC allow-list check: the caller must be a registered region database.
fn require_region(ctx: &ReducerContext, region_id: u32) -> Result<Region, String> {
    let r = ctx.db.region().db_identity().find(ctx.sender()).ok_or("caller is not a registered region")?;
    if r.region_id != region_id {
        return Err("region id does not match the caller".into());
    }
    Ok(r)
}

// ---------------------------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------------------------

#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    if ctx.db.global_config().id().find(0).is_none() {
        ctx.db.global_config().insert(GlobalConfig { id: 0, admin: ctx.sender() });
    }
}

/// Never reject here based on "is this a player?". The server runs `client_connected` around every
/// IDC call a region delivers, and a rejected IDC call is retried forever. Player admission rules
/// belong in player reducers (this database has none that write player data).
#[reducer(client_connected)]
pub fn on_connect(_ctx: &ReducerContext) -> Result<(), String> {
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// Admin reducers (called by the operator with `spacetime call`)
// ---------------------------------------------------------------------------------------------

/// Register or update a region. Run after publishing the region and reading its identity with
/// `spacetime list` / `spacetime sql <region> "SELECT * FROM region_config"`.
#[reducer]
pub fn register_region(
    ctx: &ReducerContext,
    region_id: u32,
    db_identity: Identity,
    database_name: String,
    x_min: f32,
    x_max: f32,
) -> Result<(), String> {
    require_admin(ctx)?;
    if !(x_min.is_finite() && x_max.is_finite() && x_min < x_max) {
        return Err("bad bounds".into());
    }
    if database_name.is_empty() || database_name.len() > 64 {
        return Err("bad database name".into());
    }
    let row = Region { region_id, db_identity, database_name, x_min, x_max, population: 0, last_heartbeat: ctx.timestamp };
    if ctx.db.region().region_id().find(region_id).is_some() {
        ctx.db.region().region_id().update(row);
    } else {
        ctx.db.region().insert(row);
    }
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// IDC reducers (called by region databases through their outbox tables)
// ---------------------------------------------------------------------------------------------

/// Population report, sent by each region every few seconds.
#[reducer]
pub fn region_heartbeat(ctx: &ReducerContext, region_id: u32, population: u32) -> Result<(), String> {
    let r = require_region(ctx, region_id)?;
    ctx.db.region().region_id().update(Region { population, last_heartbeat: ctx.timestamp, ..r });
    Ok(())
}

/// A player is now active in `region_id` (after joining, or after a completed handoff).
/// Idempotent and ordered by `seq`: a stale report is ignored, not an error, so it is not retried.
#[reducer]
pub fn player_entered(ctx: &ReducerContext, region_id: u32, player: Identity, seq: u64) -> Result<(), String> {
    require_region(ctx, region_id)?;
    match ctx.db.player_home().player().find(player) {
        Some(h) if h.seq >= seq => {}
        Some(h) => {
            ctx.db.player_home().player().update(PlayerHome { region_id, updated: ctx.timestamp, seq, ..h });
        }
        None => {
            ctx.db.player_home().insert(PlayerHome { player, region_id, updated: ctx.timestamp, seq });
        }
    }
    Ok(())
}
