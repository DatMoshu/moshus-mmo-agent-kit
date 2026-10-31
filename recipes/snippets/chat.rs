// Recipe: proximity chat with rate limiting and a retention cap (append to rust-single/src/lib.rs).

pub const CHAT_MAX_CHARS: usize = 200;
pub const CHAT_MIN_INTERVAL_US: i64 = 500_000; // 2 messages per second per player
pub const CHAT_KEEP: u64 = 500;                 // keep the newest N messages

/// Public, but clients subscribe by cell, like entity_transform: `WHERE cell_x = .. AND cell_y = ..`.
#[table(accessor = chat_message, public, index(accessor = by_cell, btree(columns = [cell_x, cell_y])))]
pub struct ChatMessage {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub sender: Identity,
    pub sender_name: String,
    pub text: String,
    pub cell_x: i32,
    pub cell_y: i32,
    pub sent_at: Timestamp,
}

/// Private: last send time per player, for the rate limit.
#[table(accessor = chat_rate)]
pub struct ChatRate {
    #[primary_key]
    pub identity: Identity,
    pub last_at: Timestamp,
}

#[reducer]
pub fn say(ctx: &ReducerContext, text: String) -> Result<(), String> {
    require_admitted(ctx)?;
    let text = text.trim().to_string();
    if text.is_empty() || text.chars().count() > CHAT_MAX_CHARS || text.chars().any(|c| c.is_control()) {
        return Err("bad message".into());
    }
    if let Some(r) = ctx.db.chat_rate().identity().find(ctx.sender()) {
        let since = ctx.timestamp.to_micros_since_unix_epoch() - r.last_at.to_micros_since_unix_epoch();
        if since < CHAT_MIN_INTERVAL_US { return Err("slow down".into()); }
        ctx.db.chat_rate().identity().update(ChatRate { last_at: ctx.timestamp, ..r });
    } else {
        ctx.db.chat_rate().insert(ChatRate { identity: ctx.sender(), last_at: ctx.timestamp });
    }
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("join first")?;
    let t = ctx.db.entity_transform().identity().find(ctx.sender()).ok_or("not in world")?;
    let row = ctx.db.chat_message().insert(ChatMessage {
        id: 0, sender: ctx.sender(), sender_name: p.name, text, cell_x: t.cell_x, cell_y: t.cell_y, sent_at: ctx.timestamp,
    });
    // Retention: ids are monotonic and each call inserts one row, so delete the one that fell off the end.
    if row.id > CHAT_KEEP {
        ctx.db.chat_message().id().delete(row.id - CHAT_KEEP);
    }
    Ok(())
}
