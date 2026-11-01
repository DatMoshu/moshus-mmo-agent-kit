//! NPC wandering. Dialogue is NOT here: the server only stores each NPC's dialogue index
//! (`npc_meta.talk`); clients resolve it against their own copy of the game's dialogue data.

use spacetimedb::ReducerContext;

use super::maps::*;
use super::rules::*;
use super::tables::*;

/// One step for some wandering NPCs on maps with players. Bounded: <= 256 NPCs per active map.
pub fn wander_pass(ctx: &ReducerContext, occ: &mut Occupancy, seeded: bool) {
    let maps: Vec<u8> = occ.active_maps.iter().copied().collect();
    for m in maps {
        let metas: Vec<NpcMeta> = ctx.db.npc_meta().map_id().filter(m).collect();
        for meta in metas {
            let Some(n) = ctx.db.npc().id().find(meta.id) else { continue };
            if !n.wander || n.tile == 0 {
                continue;
            }
            let r: u32 = ctx.random();
            if r % 3 != 0 {
                continue; // ~1 step every 1.5 s on average: town folk amble
            }
            let (dx, dy) = DIRS8[((r >> 8) % 4) as usize]; // orthogonal steps only
            let cur = tile_of(n.x, n.y);
            let to = (cur.0 + dx, cur.1 + dy);
            if tile_dist(to, (meta.home_x as i32, meta.home_y as i32)) > NPC_LEASH
                || !walkable(ctx, m, to.0, to.1, seeded)
                || occ.has(m, to)
                || portal_at(ctx, m, to.0, to.1).is_some()
            {
                continue;
            }
            occ.moved(m, cur, to);
            let (x, y) = (to.0 as f32 + 0.5, to.1 as f32 + 0.5);
            ctx.db.npc().id().update(Npc { x, y, cell_x: cell_of(x), cell_y: cell_of(y), ..n });
        }
    }
}
