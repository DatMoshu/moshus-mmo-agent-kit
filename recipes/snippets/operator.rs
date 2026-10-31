// Recipe: operator role. Lets a sidecar, a GM tool or a second admin act without the publisher's token.
// Append to rust-single/src/lib.rs, then use require_operator(ctx)? in reducers operators may call.

/// Private: identities with an operational role. The admin (publisher) is always allowed.
#[table(accessor = operator)]
pub struct Operator {
    #[primary_key]
    pub identity: Identity,
    pub role: String, // "ops", "gm", "sidecar" ... check it where roles differ
    pub granted_at: Timestamp,
}

fn require_operator(ctx: &ReducerContext) -> Result<(), String> {
    if is_admin(ctx) || ctx.db.operator().identity().find(ctx.sender()).is_some() {
        Ok(())
    } else {
        Err("operator only".into())
    }
}

/// Admin only: operators cannot mint operators.
#[reducer]
pub fn grant_operator(ctx: &ReducerContext, identity: Identity, role: String) -> Result<(), String> {
    require_admin(ctx)?;
    if role.is_empty() || role.len() > 16 { return Err("bad role".into()); }
    let row = Operator { identity, role, granted_at: ctx.timestamp };
    if ctx.db.operator().identity().find(identity).is_some() {
        ctx.db.operator().identity().update(row);
    } else {
        ctx.db.operator().insert(row);
    }
    log::info!("operator granted: {}", identity.to_hex());
    Ok(())
}

#[reducer]
pub fn revoke_operator(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    ctx.db.operator().identity().delete(identity);
    Ok(())
}
