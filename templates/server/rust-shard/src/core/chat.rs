//! Chat: public lines (`chat_message`, channel in the `chat_channel` side table: local or world; each
//! line carries the sender's map) and private lines (`chat_direct` via `my_chat`: whispers, and party
//! or system lines a game delivers with `deliver`).

use spacetimedb::{reducer, view, Identity, ReducerContext, Table, ViewContext};

use super::rules::*;
use super::tables::*;
use super::world::require_online;

#[reducer]
pub fn say(ctx: &ReducerContext, text: String) -> Result<(), String> {
    say_in(ctx, CH_WORLD, text)
}

/// Say on a public channel: CH_LOCAL (clients show it to players on the same map) or CH_WORLD.
#[reducer]
pub fn say_in(ctx: &ReducerContext, channel: u8, text: String) -> Result<(), String> {
    let t = require_online(ctx)?;
    if channel != CH_LOCAL && channel != CH_WORLD {
        return Err("say_in: channel 0 (local) or 1 (world); whisper with `whisper`".into());
    }
    let text = clean_chat(&text)?;
    let me = ctx.sender();
    rate(ctx, me)?;
    let name = ctx.db.player().identity().find(me).map(|p| p.name).unwrap_or_default();
    let row = ctx.db.chat_message().insert(ChatMessage {
        id: 0,
        sender: me,
        name,
        map_id: t.map_id,
        text,
        sent_at: ctx.timestamp,
    });
    if channel != CH_WORLD {
        ctx.db.chat_channel().insert(ChatChannel { id: row.id, channel });
    }
    // Keep the last CHAT_KEEP lines: at most one delete per insert (bounded).
    if row.id > CHAT_KEEP {
        ctx.db.chat_message().id().delete(row.id - CHAT_KEEP);
        ctx.db.chat_channel().id().delete(row.id - CHAT_KEEP);
    }
    Ok(())
}

/// Whisper to one player by name (online or not; they read it through `my_chat`). The sender gets a copy.
#[reducer]
pub fn whisper(ctx: &ReducerContext, to_name: String, text: String) -> Result<(), String> {
    require_online(ctx)?;
    let text = clean_chat(&text)?;
    let me = ctx.sender();
    let to = ctx.db.player().name().find(&to_name).ok_or("no player of that name")?;
    rate(ctx, me)?;
    deliver(ctx, Some(me), to.identity, CH_WHISPER, &to.name, &text);
    if to.identity != me {
        deliver(ctx, Some(me), me, CH_WHISPER, &to.name, &text);
    }
    Ok(())
}

/// Put one private chat line in `to`'s `my_chat` (games use it for party chat and system notices;
/// `from` None = the system). Keeps the reader's last CHAT_DIRECT_KEEP lines.
pub fn deliver(ctx: &ReducerContext, from: Option<Identity>, to: Identity, channel: u8, target_name: &str, text: &str) {
    let name = from.and_then(|f| ctx.db.player().identity().find(f)).map(|p| p.name).unwrap_or_default();
    ctx.db.chat_direct().insert(ChatDirect {
        id: 0,
        to,
        sender: from.unwrap_or(to),
        name,
        channel,
        target_name: target_name.to_string(),
        text: text.chars().take(CHAT_MAX_CHARS).collect(),
        sent_at: ctx.timestamp,
    });
    let ids: Vec<u64> = ctx.db.chat_direct().to().filter(to).map(|r| r.id).collect();
    if ids.len() > CHAT_DIRECT_KEEP {
        if let Some(oldest) = ids.iter().min() {
            ctx.db.chat_direct().id().delete(*oldest);
        }
    }
}

/// R21: CHAT_BURST lines per CHAT_WINDOW_US per identity.
pub fn rate(ctx: &ReducerContext, me: Identity) -> Result<(), String> {
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
    Ok(())
}

/// The caller's private chat lines (whispers to and from them, party and system lines).
#[view(accessor = my_chat, public)]
pub fn my_chat(ctx: &ViewContext) -> Vec<ChatDirect> {
    ctx.db.chat_direct().to().filter(ctx.sender()).collect()
}
