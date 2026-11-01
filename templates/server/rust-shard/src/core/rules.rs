//! Pure game rules (R27): values in, values out, unit-tested natively with `cargo test`.
//! Nothing here touches the database.

pub const SCHEMA_VERSION: u32 = 2;
pub const TICK_HZ: u32 = 20;
/// Positions are in TILE units (tile (3,4) spans x in [3,4), y in [4,5)).
pub const WORLD_HALF: f32 = 128.0;
pub const CELL_SIZE: f32 = 32.0; // AOI cell = one 32x32 map chunk
pub const MAX_SPEED: f32 = 4.0; // tiles per second
pub const CHUNK: u32 = 32;
pub const MAP_SURFACE: u8 = 0;
pub const DEFAULT_SIDE: u16 = 256;
pub const NAME_MAX_CHARS: usize = 24;
pub const HOUSEKEEPING_EVERY: u64 = 40;

pub const NPC_EVERY: u64 = 10; // NPC wander pass (0.5 s)
pub const NPC_LEASH: i32 = 3;
pub const MONSTER_EVERY: u64 = 5; // monster AI pass (0.25 s)
pub const SPAWN_EVERY: u64 = 40; // natural spawn pass (2 s)
pub const MAX_MONSTERS: usize = 256;
pub const MONSTER_LEASH: i32 = 10;
pub const DESPAWN_DIST: f32 = 48.0;
pub const ATTACK_COOLDOWN_TICKS: u64 = 10; // 0.5 s
pub const REGEN_AFTER_TICKS: u64 = 100; // 5 s without being hit
pub const ITEM_TTL_TICKS: u64 = 20 * 300; // ground items vanish after 5 min
pub const PICKUP_RANGE: f32 = 1.5;
pub const MELEE_RANGE: f32 = 1.5;
pub const CHAT_MAX_CHARS: usize = 200;
pub const CHAT_KEEP: u64 = 100;
pub const CHAT_BURST: u32 = 5; // messages per window
pub const CHAT_WINDOW_US: i64 = 5_000_000;
pub const BASE_HP: i32 = 30;
pub const HP_PER_LEVEL: i32 = 5;
pub const XP_PER_LEVEL: u32 = 100;
/// Levels written to the public `level_xp` table.
pub const LEVEL_TABLE_MAX: u32 = 100;
/// Chat channels: `chat_message` carries LOCAL / WORLD (side table `chat_channel`); `chat_direct` the rest.
pub const CH_LOCAL: u8 = 0;
pub const CH_WORLD: u8 = 1;
pub const CH_PARTY: u8 = 2;
pub const CH_SYSTEM: u8 = 3;
pub const CH_WHISPER: u8 = 4;
pub const CHAT_DIRECT_KEEP: usize = 50;
/// Combat events (`combat_event`): kinds and flags. Games may add kinds from 16 up.
pub const COMBAT_KEEP: u64 = 256;
pub const COMBAT_MELEE: u8 = 0;
pub const COMBAT_SPELL: u8 = 1;
pub const COMBAT_HEAL: u8 = 2;
pub const COMBAT_OTHER: u8 = 3;
pub const COMBAT_F_KILL: u8 = 1;
pub const COMBAT_F_DEATH: u8 = 2;

pub fn cell_of(v: f32) -> i32 {
    (v / CELL_SIZE).floor() as i32
}

pub fn chunk_id(map_id: u8, cx: u32, cy: u32) -> u32 {
    ((map_id as u32) << 16) | (cy << 8) | cx
}

pub fn tick_interval_us() -> i64 {
    1_000_000 / TICK_HZ as i64
}

pub fn walk_bits(tiles: &[u8], rule: &[u8]) -> Vec<u8> {
    let mut bits = vec![0u8; tiles.len().div_ceil(8)];
    for (i, t) in tiles.iter().enumerate() {
        if rule.get(*t as usize).copied().unwrap_or(0) != 0 {
            bits[i / 8] |= 1 << (i % 8);
        }
    }
    bits
}

pub fn valid_name(name: &str) -> bool {
    let n = name.chars().count();
    n >= 1
        && n <= NAME_MAX_CHARS
        && name.chars().all(|c| c.is_alphanumeric() || c == ' ' || c == '_' || c == '-')
        && name.trim() == name
}

/// Chat text after trimming, or why it is refused.
pub fn clean_chat(text: &str) -> Result<String, String> {
    let t = text.trim();
    let n = t.chars().count();
    if n == 0 || n > CHAT_MAX_CHARS {
        return Err(format!("chat must be 1-{CHAT_MAX_CHARS} characters"));
    }
    if t.chars().any(|c| c.is_control()) {
        return Err("chat may not contain control characters".into());
    }
    Ok(t.to_string())
}

/// Tile coordinate of a position.
pub fn tile_of(x: f32, y: f32) -> (i32, i32) {
    (x.floor() as i32, y.floor() as i32)
}

/// Chebyshev distance between two tiles (8-neighbour steps).
pub fn tile_dist(a: (i32, i32), b: (i32, i32)) -> i32 {
    (a.0 - b.0).abs().max((a.1 - b.1).abs())
}

/// Adjacent (or same tile): the 8 neighbours count.
pub fn in_melee(a: (i32, i32), b: (i32, i32)) -> bool {
    tile_dist(a, b) <= 1
}

/// One step toward a target, trying the long axis first; returns candidate steps in order.
pub fn steps_toward(from: (i32, i32), to: (i32, i32)) -> Vec<(i32, i32)> {
    let dx = (to.0 - from.0).signum();
    let dy = (to.1 - from.1).signum();
    let mut out = Vec::with_capacity(3);
    if dx != 0 && dy != 0 {
        out.push((dx, dy));
    }
    if (to.0 - from.0).abs() >= (to.1 - from.1).abs() {
        if dx != 0 { out.push((dx, 0)); }
        if dy != 0 { out.push((0, dy)); }
    } else {
        if dy != 0 { out.push((0, dy)); }
        if dx != 0 { out.push((dx, 0)); }
    }
    out
}

/// The 8 compass steps, indexed 0..8 (used with a random roll for wandering).
pub const DIRS8: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)];

/// Inclusive roll in [lo, hi] from a random u32.
pub fn roll(r: u32, lo: i32, hi: i32) -> i32 {
    if hi <= lo {
        return lo;
    }
    lo + (r % ((hi - lo + 1) as u32)) as i32
}

pub fn level_for_xp(xp: u32) -> u32 {
    1 + xp / XP_PER_LEVEL
}

pub fn max_hp_for_level(level: u32) -> i32 {
    BASE_HP + HP_PER_LEVEL * (level.saturating_sub(1) as i32)
}

/// Player melee damage range by level.
pub fn player_damage(level: u32) -> (i32, i32) {
    (2 + level as i32 / 2, 6 + level as i32)
}

pub fn in_circle(x: i32, y: i32, cx: i32, cy: i32, r: i32) -> bool {
    let (dx, dy) = (x - cx, y - cy);
    dx * dx + dy * dy <= r * r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chat_rules() {
        assert!(clean_chat("  hi  ").unwrap() == "hi");
        assert!(clean_chat("").is_err());
        assert!(clean_chat(&"x".repeat(201)).is_err());
        assert!(clean_chat("a\u{7}b").is_err());
    }

    #[test]
    fn melee_and_steps() {
        assert!(in_melee((5, 5), (6, 6)));
        assert!(!in_melee((5, 5), (7, 5)));
        assert_eq!(steps_toward((0, 0), (5, 0)), vec![(1, 0)]);
        assert_eq!(steps_toward((0, 0), (5, 2))[0], (1, 1));
        assert_eq!(steps_toward((0, 0), (1, 4))[1], (0, 1));
    }

    #[test]
    fn levels() {
        assert_eq!(level_for_xp(0), 1);
        assert_eq!(level_for_xp(250), 3);
        assert_eq!(max_hp_for_level(3), 40);
        for r in 0..50u32 {
            let v = roll(r, 2, 6);
            assert!((2..=6).contains(&v));
        }
    }

    #[test]
    fn walk_bits_packs() {
        let rule: Vec<u8> = (0..=255).map(|t| if t == 4 { 1 } else { 0 }).collect();
        let bits = walk_bits(&[4, 0, 4, 0, 0, 0, 0, 0, 4], &rule);
        assert_eq!(bits, vec![0b0000_0101, 0b0000_0001]);
    }
}
