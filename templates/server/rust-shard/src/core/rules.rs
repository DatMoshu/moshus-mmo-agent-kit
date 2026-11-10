//! Pure game rules (R27): values in, values out, unit-tested natively with `cargo test`.
//! Nothing here touches the database.

pub const SCHEMA_VERSION: u32 = 2;
pub const TICK_HZ: u32 = 20;
/// Positions are in TILE units (tile (3,4) spans x in [3,4), y in [4,5)).
pub const WORLD_HALF: f32 = 128.0;
pub const CELL_SIZE: f32 = 32.0; // AOI cell = one 32x32 map chunk
pub const MAX_SPEED: f32 = 4.0; // tiles per second: the default; a database may set world_config.max_speed
/// Highest movement speed a database may configure (tiles per second); higher values are clamped to it.
pub const MAX_SPEED_CAP: f32 = 16.0;
/// Longest move of one tick on each axis (tiles). Under one tile, so a step ends on the current tile or a neighbour
/// and the one-tile collision check below can never be jumped, even on a late tick (dt up to 3 intervals).
pub const MAX_STEP: f32 = 0.95;
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

/// The movement speed the tick uses (tiles per second) for a stored `world_config.max_speed`: a finite value above
/// zero, clamped to MAX_SPEED_CAP; anything else (no config row, NaN, infinity, zero, negative) is MAX_SPEED. Writers
/// store `speed_or_default(Some(v))` so the row always holds the value the tick will use.
pub fn speed_or_default(v: Option<f32>) -> f32 {
    match v {
        Some(s) if s.is_finite() && s > 0.0 => s.min(MAX_SPEED_CAP),
        _ => MAX_SPEED,
    }
}

/// One tick's displacement for a normalised direction (dx, dy) at `speed` over `dt` seconds, each axis clamped to
/// MAX_STEP. Below the clamp the result is exactly `dx * speed * dt` (the arithmetic of the original tick).
pub fn step_delta(dx: f32, dy: f32, speed: f32, dt: f32) -> (f32, f32) {
    ((dx * speed * dt).clamp(-MAX_STEP, MAX_STEP), (dy * speed * dt).clamp(-MAX_STEP, MAX_STEP))
}

/// Tile collision for one step from (x, y) to (nx, ny), per-axis sliding: the full step, else x only, else y only,
/// else stay. `ok(tx, ty)` says whether a tile may be entered (the caller treats the current tile as always ok). A
/// diagonal step needs both orthogonal neighbours open (no squeezing between two walls).
pub fn slide(x: f32, y: f32, nx: f32, ny: f32, ok: impl Fn(i32, i32) -> bool) -> (f32, f32) {
    let (cur_tx, cur_ty) = tile_of(x, y);
    let (ntx, nty) = tile_of(nx, ny);
    let diag_ok = ntx == cur_tx || nty == cur_ty || (ok(ntx, cur_ty) && ok(cur_tx, nty));
    if ok(ntx, nty) && diag_ok {
        (nx, ny)
    } else if ok(ntx, cur_ty) {
        (nx, y)
    } else if ok(cur_tx, nty) {
        (x, ny)
    } else {
        (x, y)
    }
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

    // --- movement speed (task 1449): world_config.max_speed, step cap, collision at 20 Hz ---
    const DT: f32 = 1.0 / TICK_HZ as f32; // one on-time tick
    const LATE: f32 = 3.0 * DT; // the tick's dt clamp

    /// Walk `ticks` ticks of `dt` from (x, y) in direction (dx, dy) at `speed` over `ok` (as the tick does).
    fn walk(mut x: f32, mut y: f32, dx: f32, dy: f32, speed: f32, dt: f32, ticks: u32, ok: &dyn Fn(i32, i32) -> bool)
        -> (f32, f32) {
        let (dx, dy) = if dx != 0.0 && dy != 0.0 {
            (dx * std::f32::consts::FRAC_1_SQRT_2, dy * std::f32::consts::FRAC_1_SQRT_2)
        } else {
            (dx, dy)
        };
        for _ in 0..ticks {
            let (sx, sy) = step_delta(dx, dy, speed, dt);
            let cur = tile_of(x, y);
            (x, y) = slide(x, y, x + sx, y + sy, |tx, ty| (tx, ty) == cur || ok(tx, ty));
        }
        (x, y)
    }

    #[test]
    fn speed_config_fallback_and_bounds() {
        assert_eq!(speed_or_default(None), MAX_SPEED); // no world_config row: prior behaviour
        assert_eq!(speed_or_default(Some(4.0)), 4.0);
        assert_eq!(speed_or_default(Some(8.0)), 8.0);
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 0.0, -0.0, -4.0, f32::MIN] {
            assert_eq!(speed_or_default(Some(bad)), MAX_SPEED, "{bad}");
        }
        assert_eq!(speed_or_default(Some(100.0)), MAX_SPEED_CAP);
        assert_eq!(speed_or_default(Some(f32::MAX)), MAX_SPEED_CAP);
        assert_eq!(speed_or_default(Some(f32::MIN_POSITIVE)), f32::MIN_POSITIVE);
    }

    #[test]
    fn default_speed_step_is_the_original_arithmetic() {
        // explicit 4.0 = the old constant: the step is bit-for-bit dx * MAX_SPEED * dt, on time and late
        for dt in [DT, 2.0 * DT, LATE, 0.0] {
            for (dx, dy) in [(1.0f32, 0.0f32), (-1.0, 0.0), (0.0, 1.0), (std::f32::consts::FRAC_1_SQRT_2, -std::f32::consts::FRAC_1_SQRT_2)] {
                let (sx, sy) = step_delta(dx, dy, speed_or_default(Some(4.0)), dt);
                assert_eq!((sx.to_bits(), sy.to_bits()), ((dx * MAX_SPEED * dt).to_bits(), (dy * MAX_SPEED * dt).to_bits()));
            }
        }
        assert!(MAX_SPEED * LATE < MAX_STEP); // the cap never binds at the default speed
    }

    #[test]
    fn eight_tiles_per_second_is_twice_the_default() {
        let open = |_: i32, _: i32| true;
        let (x4, _) = walk(10.5, 10.5, 1.0, 0.0, 4.0, DT, 20, &open); // one second at 20 Hz
        let (x8, _) = walk(10.5, 10.5, 1.0, 0.0, 8.0, DT, 20, &open);
        assert!((x4 - 14.5).abs() < 1e-3, "{x4}");
        assert!((x8 - 18.5).abs() < 1e-3, "{x8}");
        let (dx8, dy8) = step_delta(std::f32::consts::FRAC_1_SQRT_2, std::f32::consts::FRAC_1_SQRT_2, 8.0, DT);
        assert!(((dx8 * dx8 + dy8 * dy8).sqrt() - 0.4).abs() < 1e-6); // diagonal: same speed, not faster
    }

    #[test]
    fn late_ticks_cannot_jump_a_wall() {
        // a one-tile wall at x = 12; walking +x from 10.5 at the fastest allowed speed with every tick late
        let wall = |tx: i32, _: i32| tx != 12;
        for speed in [4.0, 8.0, MAX_SPEED_CAP, speed_or_default(Some(1000.0))] {
            let (x, y) = walk(10.5, 10.5, 1.0, 0.0, speed, LATE, 50, &wall);
            assert!(x < 12.0 && x >= 11.0, "speed {speed}: x {x}"); // stopped in front of the wall
            assert_eq!(y, 10.5);
            let (sx, _) = step_delta(1.0, 0.0, speed, LATE);
            assert!(sx <= MAX_STEP && sx < 1.0);
        }
        // without the cap the same late tick at 16 tiles/s would move 2.4 tiles, past the wall
        assert!(MAX_SPEED_CAP * LATE > 2.0);
    }

    #[test]
    fn corners_and_sliding_at_double_speed() {
        // walls: column x = 12 and row y = 12; the corner tile (12, 12) is wall too
        let walls = |tx: i32, ty: i32| tx != 12 && ty != 12;
        // diagonal into the corner: slides along both walls and stops in tile (11, 11)
        let (x, y) = walk(9.5, 9.5, 1.0, 1.0, 8.0, DT, 40, &walls);
        assert_eq!(tile_of(x, y), (11, 11), "{x} {y}");
        // diagonal along a wall: blocked on x, keeps moving on y
        let col = |tx: i32, _: i32| tx != 12;
        let (x, y) = walk(11.5, 5.5, 1.0, 1.0, 8.0, DT, 20, &col);
        assert_eq!(tile_of(x, y).0, 11);
        assert!(y > 9.0, "{y}");
        // no squeezing between two diagonal walls: (11, 10) and (10, 11) closed, (11, 11) open
        let pinch = |tx: i32, ty: i32| !((tx, ty) == (11, 10) || (tx, ty) == (10, 11));
        let (x, y) = walk(10.9, 10.9, 1.0, 1.0, 8.0, DT, 10, &pinch);
        assert_eq!(tile_of(x, y), (10, 10), "{x} {y}");
    }

    #[test]
    fn blocked_move_is_rejected_at_both_speeds() {
        // every neighbour closed: no speed moves the player out of its tile
        let boxed = |_: i32, _: i32| false;
        for speed in [4.0, 8.0] {
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let (x, y) = walk(5.5, 5.5, dx, dy, speed, DT, 30, &boxed);
                assert_eq!(tile_of(x, y), (5, 5), "speed {speed} dir {dx},{dy}");
            }
        }
    }

    #[test]
    fn walk_bits_packs() {
        let rule: Vec<u8> = (0..=255).map(|t| if t == 4 { 1 } else { 0 }).collect();
        let bits = walk_bits(&[4, 0, 4, 0, 0, 0, 0, 0, 4], &rule);
        assert_eq!(bits, vec![0b0000_0101, 0b0000_0001]);
    }
}
