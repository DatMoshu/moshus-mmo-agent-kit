//! Monster decision rules, kept pure (no database) so they can be unit-tested. `combat::monster_pass`
//! gathers the facts, asks `decide`, then carries the act out. Behaviour is data: the adapter seeds a
//! `monster_ai` row per kind (flee threshold, ranged reach, distance kept, pack radius, flags) and games
//! put timed statuses on single monsters (sleep, confusion, silence, fear) through `combat::set_status`.

use super::rules::{in_melee, tile_dist, DIRS8};

/// `monster_ai.flags` bits the core understands. Bits 16..31 are free for games (e.g. "undead").
pub const AI_STATIONARY: u32 = 1; // never steps (turrets, plants, gate guards)
pub const AI_NO_HOME: u32 = 2; // no leash and no drifting home (roamers)
pub const AI_GAME_FLAGS: u32 = 0xFFFF_0000;

/// Statuses a game can put on one monster for a number of ticks.
pub const STATUS_SLEEP: u8 = 0; // skips its turns; any damage wakes it
pub const STATUS_CONFUSE: u8 = 1; // fights the nearest other monster instead of players
pub const STATUS_SILENCE: u8 = 2; // no ranged attacks
pub const STATUS_FEAR: u8 = 3; // runs from its target whatever its HP

/// Per-kind behaviour (a copy of the `monster_ai` row, or the default melee brute).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Behaviour {
    /// Flee when HP is at or below this percentage of max HP (0 = fights to the death).
    pub flee_hp_pct: u8,
    /// Ranged attack reach in tiles (0 or 1 = melee only).
    pub range: u8,
    /// Ranged attackers back off when the target is closer than this (0 = never).
    pub keep_dist: u8,
    /// Pack radius: kin within it join the fight when one of them engages or is hit (0 = loner).
    pub pack: u8,
    pub flags: u32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Act {
    Melee,
    Ranged,
    Approach,
    Retreat,
}

pub fn flees(b: &Behaviour, hp: i32, max_hp: i32, feared: bool) -> bool {
    feared || (b.flee_hp_pct > 0 && max_hp > 0 && hp as i64 * 100 <= b.flee_hp_pct as i64 * max_hp as i64)
}

/// What a monster at `here` with a target at `there` wants to do this turn.
pub fn decide(b: &Behaviour, here: (i32, i32), there: (i32, i32), hp: i32, max_hp: i32, silenced: bool, feared: bool) -> Act {
    if flees(b, hp, max_hp, feared) {
        return Act::Retreat;
    }
    let d = tile_dist(here, there);
    if b.range > 1 && !silenced && d <= b.range as i32 {
        if b.keep_dist > 0 && d < b.keep_dist as i32 {
            return Act::Retreat;
        }
        // Adjacent ranged attackers that do not mind company just shoot point blank.
        return Act::Ranged;
    }
    if in_melee(here, there) {
        Act::Melee
    } else {
        Act::Approach
    }
}

/// Steps from `from` that strictly increase the distance to `threat`, best first.
pub fn steps_away(from: (i32, i32), threat: (i32, i32)) -> Vec<(i32, i32)> {
    let d0 = tile_dist(from, threat);
    let mut v: Vec<((i32, i32), i32, i32)> = DIRS8
        .iter()
        .map(|&(dx, dy)| {
            let to = (from.0 + dx, from.1 + dy);
            // Prefer the larger Chebyshev gain, then the larger straight-line gain.
            let e = (to.0 - threat.0).pow(2) + (to.1 - threat.1).pow(2);
            ((dx, dy), tile_dist(to, threat), e)
        })
        .filter(|(_, d, _)| *d > d0)
        .collect();
    v.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));
    v.into_iter().map(|(s, _, _)| s).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const BRUTE: Behaviour = Behaviour { flee_hp_pct: 0, range: 0, keep_dist: 0, pack: 0, flags: 0 };
    const ARCHER: Behaviour = Behaviour { flee_hp_pct: 0, range: 5, keep_dist: 3, pack: 0, flags: 0 };
    const COWARD: Behaviour = Behaviour { flee_hp_pct: 25, range: 0, keep_dist: 0, pack: 0, flags: 0 };

    #[test]
    fn brute_closes_then_hits() {
        assert_eq!(decide(&BRUTE, (0, 0), (5, 0), 10, 10, false, false), Act::Approach);
        assert_eq!(decide(&BRUTE, (0, 0), (1, 1), 1, 10, false, false), Act::Melee);
    }

    #[test]
    fn archer_keeps_distance_and_shoots() {
        assert_eq!(decide(&ARCHER, (0, 0), (8, 0), 10, 10, false, false), Act::Approach);
        assert_eq!(decide(&ARCHER, (0, 0), (4, 0), 10, 10, false, false), Act::Ranged);
        assert_eq!(decide(&ARCHER, (0, 0), (2, 0), 10, 10, false, false), Act::Retreat);
        // Silenced: falls back to melee rules.
        assert_eq!(decide(&ARCHER, (0, 0), (4, 0), 10, 10, true, false), Act::Approach);
        assert_eq!(decide(&ARCHER, (0, 0), (1, 0), 10, 10, true, false), Act::Melee);
    }

    #[test]
    fn coward_flees_at_threshold_and_fear_overrides() {
        assert_eq!(decide(&COWARD, (0, 0), (1, 0), 3, 10, false, false), Act::Melee);
        assert_eq!(decide(&COWARD, (0, 0), (1, 0), 2, 10, false, false), Act::Retreat);
        assert_eq!(decide(&BRUTE, (0, 0), (1, 0), 10, 10, false, true), Act::Retreat);
    }

    #[test]
    fn steps_away_increase_distance() {
        let s = steps_away((0, 0), (1, 0));
        assert!(!s.is_empty());
        assert_eq!(s[0].0, -1);
        for (dx, dy) in s {
            assert!(tile_dist((dx, dy), (1, 0)) > 1);
        }
    }
}
