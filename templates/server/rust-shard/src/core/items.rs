//! Ground items, pickup, a minimal inventory and using consumables. Gold (kind 0) goes straight
//! to `player_stats.gold`; everything else stacks in the private `inventory` table, which each
//! player reads through the `my_inventory` view.

use spacetimedb::{reducer, view, Identity, ReducerContext, Table, ViewContext};

use super::combat::{ensure_stats, GOLD};
use super::rules::*;
use super::tables::*;
use super::world::require_online;

pub fn drop_item(ctx: &ReducerContext, map_id: u8, x: i32, y: i32, kind: u16, qty: u32, tick: u64) {
    if x < 0 || y < 0 || qty == 0 {
        return;
    }
    let (cx, cy) = (cell_of(x as f32), cell_of(y as f32));
    // Stack onto an existing pile of the same kind on the same tile.
    if let Some(g) = ctx
        .db
        .ground_item()
        .item_by_cell()
        .filter((map_id, cx, cy))
        .find(|g| g.x as i32 == x && g.y as i32 == y && g.kind == kind)
    {
        ctx.db.ground_item().id().update(GroundItem { qty: g.qty.saturating_add(qty), dropped_tick: tick, ..g });
        return;
    }
    ctx.db.ground_item().insert(GroundItem {
        id: 0,
        map_id,
        x: x as u16,
        y: y as u16,
        cell_x: cx,
        cell_y: cy,
        kind,
        qty,
        dropped_tick: tick,
    });
}

pub fn give(ctx: &ReducerContext, who: Identity, kind: u16, qty: u32) {
    if kind == GOLD {
        ensure_stats(ctx, who);
        if let Some(s) = ctx.db.player_stats().identity().find(who) {
            ctx.db.player_stats().identity().update(PlayerStats { gold: s.gold.saturating_add(qty), ..s });
        }
        return;
    }
    if let Some(row) = ctx.db.inventory().owner().filter(who).find(|r| r.kind == kind) {
        ctx.db.inventory().id().update(InventoryItem { qty: row.qty.saturating_add(qty), ..row });
    } else {
        ctx.db.inventory().insert(InventoryItem { id: 0, owner: who, kind, qty });
    }
}

/// Pick up a ground item on your tile or an adjacent one.
#[reducer]
pub fn pick_up(ctx: &ReducerContext, item_id: u64) -> Result<(), String> {
    let t = require_online(ctx)?;
    let g = ctx.db.ground_item().id().find(item_id).ok_or("no such item")?;
    if g.map_id != t.map_id || !in_melee(tile_of(t.x, t.y), (g.x as i32, g.y as i32)) {
        return Err("too far".into());
    }
    ctx.db.ground_item().id().delete(g.id);
    give(ctx, ctx.sender(), g.kind, g.qty);
    Ok(())
}

/// Use one consumable of `kind` from your inventory (healing items).
#[reducer]
pub fn use_item(ctx: &ReducerContext, kind: u16) -> Result<(), String> {
    require_online(ctx)?;
    let me = ctx.sender();
    let k = ctx.db.item_kind().kind().find(kind).ok_or("unknown item")?;
    if k.heal <= 0 {
        return Err("cannot use that".into());
    }
    let row = ctx.db.inventory().owner().filter(me).find(|r| r.kind == kind).ok_or("you have none")?;
    if row.qty <= 1 {
        ctx.db.inventory().id().delete(row.id);
    } else {
        ctx.db.inventory().id().update(InventoryItem { qty: row.qty - 1, ..row });
    }
    ensure_stats(ctx, me);
    if let Some(s) = ctx.db.player_stats().identity().find(me) {
        ctx.db.player_stats().identity().update(PlayerStats { hp: (s.hp + k.heal).min(s.max_hp), ..s });
    }
    Ok(())
}

/// Ground items expire after ITEM_TTL_TICKS (bounded: one pass over the ground items).
pub fn decay_pass(ctx: &ReducerContext, tick: u64) {
    let old: Vec<u64> = ctx
        .db
        .ground_item()
        .iter()
        .filter(|g| tick.saturating_sub(g.dropped_tick) > ITEM_TTL_TICKS)
        .map(|g| g.id)
        .take(256)
        .collect();
    for id in old {
        ctx.db.ground_item().id().delete(id);
    }
    // Chat ids can jump (sequence pre-allocation), so also trim any stragglers past the window.
    if let Some(max) = ctx.db.chat_message().iter().map(|c| c.id).max() {
        let stale: Vec<u64> =
            ctx.db.chat_message().iter().filter(|c| c.id + CHAT_KEEP <= max).map(|c| c.id).take(256).collect();
        for id in stale {
            ctx.db.chat_message().id().delete(id);
        }
    }
}

/// The caller's own inventory (R14: private table, per-player view).
#[view(accessor = my_inventory, public)]
pub fn my_inventory(ctx: &ViewContext) -> Vec<InventoryItem> {
    ctx.db.inventory().owner().filter(ctx.sender()).collect()
}
