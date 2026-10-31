// Recipe: idempotent requests for callers that retry (HTTP callers, sidecars, IDC, payment webhooks).
// Since 2.13 an HTTP reducer call that times out (504) has an UNKNOWN outcome, so the caller retries.

/// Private: one row per request already applied.
#[table(accessor = applied_request)]
pub struct AppliedRequest {
    #[primary_key]
    pub request_id: String, // chosen by the caller, e.g. a UUID or "<order-id>:<line>"
    pub caller: Identity,
    pub applied_at: Timestamp,
}

/// Returns Ok(false) if this request was already applied, so the caller can treat a retry as success.
fn first_time(ctx: &ReducerContext, request_id: &str) -> Result<bool, String> {
    if request_id.is_empty() || request_id.len() > 64 { return Err("bad request id".into()); }
    if ctx.db.applied_request().request_id().find(request_id.to_string()).is_some() { return Ok(false); }
    ctx.db.applied_request().insert(AppliedRequest { request_id: request_id.to_string(), caller: ctx.sender(), applied_at: ctx.timestamp });
    Ok(true)
}

#[reducer]
pub fn grant_purchase(ctx: &ReducerContext, request_id: String, to: Identity, item_id: u32, qty: u32) -> Result<(), String> {
    require_admin(ctx)?; // or check an operator/service identity, see recipes/operator-role.md
    if !first_time(ctx, &request_id)? { return Ok(()); } // retry: already done
    add_items(ctx, to, item_id, qty) // an Err here also rolls back the applied_request row
}
