// Recipe: inventory, pickups and trades (append to templates/server/rust-single/src/lib.rs).
// Every transfer is ONE reducer, so a failure rolls back every write: items cannot be duplicated.

#[table(accessor = item_def, public)]
pub struct ItemDef {
    #[primary_key]
    pub item_id: u32,
    pub name: String,
    pub max_stack: u32,
}

/// Private: each player reads their own stacks through `my_inventory`.
#[table(accessor = inventory, index(accessor = by_owner, btree(columns = [owner])))]
pub struct Inventory {
    #[primary_key]
    #[auto_inc]
    pub stack_id: u64,
    pub owner: Identity,
    pub item_id: u32,
    pub qty: u32,
}

#[view(accessor = my_inventory, public)]
fn my_inventory(ctx: &ViewContext) -> Vec<Inventory> {
    ctx.db.inventory().by_owner().filter(&ctx.sender()).collect()
}

fn add_items(ctx: &ReducerContext, owner: Identity, item_id: u32, mut qty: u32) -> Result<(), String> {
    let def = ctx.db.item_def().item_id().find(item_id).ok_or("unknown item")?;
    for s in ctx.db.inventory().by_owner().filter(&owner) {
        if qty == 0 { break; }
        if s.item_id == item_id && s.qty < def.max_stack {
            let add = qty.min(def.max_stack - s.qty);
            qty -= add;
            ctx.db.inventory().stack_id().update(Inventory { qty: s.qty + add, ..s });
        }
    }
    while qty > 0 {
        let add = qty.min(def.max_stack);
        qty -= add;
        ctx.db.inventory().insert(Inventory { stack_id: 0, owner, item_id, qty: add });
    }
    Ok(())
}

fn take_items(ctx: &ReducerContext, owner: Identity, item_id: u32, mut qty: u32) -> Result<(), String> {
    let stacks: Vec<Inventory> = ctx.db.inventory().by_owner().filter(&owner).filter(|s| s.item_id == item_id).collect();
    if stacks.iter().map(|s| s.qty as u64).sum::<u64>() < qty as u64 {
        return Err("not enough items".into());
    }
    for s in stacks {
        if qty == 0 { break; }
        let take = qty.min(s.qty);
        qty -= take;
        if take == s.qty {
            ctx.db.inventory().stack_id().delete(s.stack_id);
        } else {
            ctx.db.inventory().stack_id().update(Inventory { qty: s.qty - take, ..s });
        }
    }
    Ok(())
}

/// Give items to a nearby player. The caller is always ctx.sender(); never trust an id argument.
#[reducer]
pub fn give_item(ctx: &ReducerContext, to: Identity, item_id: u32, qty: u32) -> Result<(), String> {
    require_admitted(ctx)?;
    if qty == 0 || qty > 10_000 { return Err("bad qty".into()); }
    if to == ctx.sender() { return Err("cannot give to yourself".into()); }
    let me = ctx.db.entity_transform().identity().find(ctx.sender()).ok_or("not in world")?;
    let them = ctx.db.entity_transform().identity().find(to).ok_or("target not in world")?;
    if (me.x - them.x).hypot(me.y - them.y) > 5.0 { return Err("too far".into()); }
    take_items(ctx, ctx.sender(), item_id, qty)?; // Err here rolls back everything
    add_items(ctx, to, item_id, qty)
}

/// Admin grant, for testing. Idempotency for external callers: see recipes/idempotent-requests.md.
#[reducer]
pub fn gm_grant(ctx: &ReducerContext, to: Identity, item_id: u32, qty: u32) -> Result<(), String> {
    require_admin(ctx)?;
    add_items(ctx, to, item_id, qty)
}

#[reducer]
pub fn gm_define_item(ctx: &ReducerContext, item_id: u32, name: String, max_stack: u32) -> Result<(), String> {
    require_admin(ctx)?;
    if max_stack == 0 { return Err("max_stack must be > 0".into()); }
    let row = ItemDef { item_id, name, max_stack };
    if ctx.db.item_def().item_id().find(item_id).is_some() {
        ctx.db.item_def().item_id().update(row);
    } else {
        ctx.db.item_def().insert(row);
    }
    Ok(())
}
