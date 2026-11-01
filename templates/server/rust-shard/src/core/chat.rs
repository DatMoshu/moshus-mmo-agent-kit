//! Shared chat: one global channel (each line carries the sender's map so clients can filter).

use spacetimedb::{reducer, ReducerContext, Table};

use super::rules::*;
use super::tables::*;
use super::world::require_online;

#[reducer]
pub fn say(ctx: &ReducerContext, text: String) -> Result<(), String> {
    let t = require_online(ctx)?;
    let text = clean_chat(&text)?;
    let me = ctx.sender();
    // R21: 5 lines per 5 s per identity.
    match ctx.db.chat_rate().identity().find(me) {
        Some(r) => {
            let age = ctx.timestamp.time_duration_since(r.window_start).map(|d| d.to_micros()).unwrap_or(0);
            if age > CHAT_WINDOW_US {
                ctx.db.chat_rate().identity().update(ChatRate { window_start: ctx.timestamp, count: 1, ..r });
            } else if r.count >= CHAT_BURST {
                return Err("slow down".into());
            } else {
                ctx.db.chat_rate().identity().update(ChatRate { count: r.count + 1, ..r });
            }
        }
        None => {
            ctx.db.chat_rate().insert(ChatRate { identity: me, window_start: ctx.timestamp, count: 1 });
        }
    }
    let name = ctx.db.player().identity().find(me).map(|p| p.name).unwrap_or_default();
    let row = ctx.db.chat_message().insert(ChatMessage {
        id: 0,
        sender: me,
        name,
        map_id: t.map_id,
        text,
        sent_at: ctx.timestamp,
    });
    // Keep the last CHAT_KEEP lines: at most one delete per insert (bounded).
    if row.id > CHAT_KEEP {
        ctx.db.chat_message().id().delete(row.id - CHAT_KEEP);
    }
    Ok(())
}
