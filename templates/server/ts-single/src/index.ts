// Moshu's MMO Agent Kit: single-database world module in TypeScript (SpacetimeDB 2.14).
//
// The same game as templates/server/rust-single, with the same table, column and reducer names, so
// the kit's bots, Godot client and web admin work against either module. Rules this file follows
// are in rules/typescript-module.md at the kit root.
//
// What it shows:
// - server-authoritative movement: clients send intent (a direction), the tick moves them
// - a fixed-rate scheduled tick that rejects client calls
// - a self-measuring tick_health row (scheduler lateness = load signal)
// - a narrow public hot table (entity_transform) with a cell index for AOI subscriptions
// - private tables for inputs and admission, an admin identity, an idempotent ensure_world

import { schema, table, t, SenderError, type InferSchema, type ReducerCtx } from 'spacetimedb/server';
import { ScheduleAt, type Identity } from 'spacetimedb';

const SCHEMA_VERSION = 1;
const TICK_HZ = 20;
const WORLD_HALF = 500; // world is the square [-WORLD_HALF, WORLD_HALF]^2
const CELL_SIZE = 50; // AOI cell edge, roughly view radius / 1.5
const MAX_SPEED = 8; // world units per second
const NAME_MAX_CHARS = 24;
const HOUSEKEEPING_EVERY = 40n; // ticks between optional housekeeping passes
const TICK_INTERVAL_US = BigInt(1_000_000 / TICK_HZ);

// ---------------------------------------------------------------------------------------------
// Tables (column keys are snake_case on purpose: wire-compatible with rust-single)
// ---------------------------------------------------------------------------------------------

/** Singleton (id = 0). Public so clients can read world bounds and tick rate. */
const world_config = table(
  { name: 'world_config', public: true },
  {
    id: t.u8().primaryKey(),
    admin: t.identity(),
    admission_open: t.bool(),
    tick_hz: t.u32(),
    max_speed: t.f32(),
    cell_size: t.f32(),
    world_half: t.f32(),
    schema_version: t.u32(),
  }
);

/** Private: who may connect while admission is closed. */
const allowlist = table(
  { name: 'allowlist' },
  {
    identity: t.identity().primaryKey(),
    granted_at: t.timestamp(),
  }
);

/** Cold row: join, rename, online flag, logout position. */
const player = table(
  { name: 'player', public: true },
  {
    identity: t.identity().primaryKey(),
    name: t.string().unique(),
    online: t.bool(),
    created_at: t.timestamp(),
    last_seen: t.timestamp(),
    last_x: t.f32(),
    last_y: t.f32(),
  }
);

/** Private: latest movement intent per player. Never broadcast. */
const player_input = table(
  { name: 'player_input' },
  {
    identity: t.identity().primaryKey(),
    dir_x: t.i8(),
    dir_y: t.i8(),
    seq: t.u32(),
  }
);

/** Hot, narrow row: the only thing that changes every tick. Exists only while online. */
const entity_transform = table(
  {
    name: 'entity_transform',
    public: true,
    indexes: [{ accessor: 'by_cell', algorithm: 'btree', columns: ['cell_x', 'cell_y'] }],
  },
  {
    identity: t.identity().primaryKey(),
    x: t.f32(),
    y: t.f32(),
    cell_x: t.i32(),
    cell_y: t.i32(),
    moving: t.bool(),
    last_input_seq: t.u32(),
  }
);

/** Scheduler row for the fixed-rate tick (bound to `tick` below with onSchedule). */
const tick_schedule = table(
  { name: 'tick_schedule' },
  {
    scheduled_id: t.u64().primaryKey().autoInc(),
    scheduled_at: t.scheduleAt(),
  }
);

/** Singleton (id = 0). level: 0 green, 1 yellow, 2 orange (optional work shed), 3 red. */
const tick_health = table(
  { name: 'tick_health', public: true },
  {
    id: t.u8().primaryKey(),
    tick_count: t.u64(),
    last_tick_at: t.timestamp(),
    last_lateness_us: t.i64(),
    avg_lateness_us: t.i64(),
    max_lateness_us: t.i64(),
    moved_last_tick: t.u32(),
    online_players: t.u32(),
    level: t.u8(),
  }
);

const spacetimedb = schema({
  world_config,
  allowlist,
  player,
  player_input,
  entity_transform,
  tick_schedule,
  tick_health,
});
export default spacetimedb;

type Ctx = ReducerCtx<InferSchema<typeof spacetimedb>>;

// ---------------------------------------------------------------------------------------------
// Helpers (not exported: named exports are reserved for reducers, views and hooks)
// ---------------------------------------------------------------------------------------------

function config(ctx: Ctx) {
  const c = ctx.db.world_config.id.find(0);
  if (!c) throw new SenderError('world not initialised');
  return c;
}

function requireAdmin(ctx: Ctx) {
  if (!config(ctx).admin.isEqual(ctx.sender)) throw new SenderError('admin only');
}

/** Admission is checked on connect AND in every reducer: revoking a row does not close a socket. */
function requireAdmitted(ctx: Ctx) {
  const c = config(ctx);
  if (c.admission_open || c.admin.isEqual(ctx.sender) || ctx.db.allowlist.identity.find(ctx.sender)) return;
  throw new SenderError('not admitted');
}

function cellOf(v: number): number {
  return Math.floor(v / CELL_SIZE);
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

function validName(name: string): boolean {
  const chars = [...name];
  return (
    chars.length >= 1 &&
    chars.length <= NAME_MAX_CHARS &&
    /^[\p{L}\p{N} _-]+$/u.test(name) &&
    name.trim() === name
  );
}

function ensureWorldInner(ctx: Ctx, admin: Identity) {
  const c = ctx.db.world_config.id.find(0);
  if (!c) {
    ctx.db.world_config.insert({
      id: 0,
      admin,
      admission_open: true,
      tick_hz: TICK_HZ,
      max_speed: MAX_SPEED,
      cell_size: CELL_SIZE,
      world_half: WORLD_HALF,
      schema_version: SCHEMA_VERSION,
    });
  } else if (c.schema_version < SCHEMA_VERSION) {
    // Backfills for new schema versions go here, then bump the stored version.
    ctx.db.world_config.id.update({ ...c, schema_version: SCHEMA_VERSION });
  }
  if (!ctx.db.tick_health.id.find(0)) {
    ctx.db.tick_health.insert({
      id: 0,
      tick_count: 0n,
      last_tick_at: ctx.timestamp,
      last_lateness_us: 0n,
      avg_lateness_us: 0n,
      max_lateness_us: 0n,
      moved_last_tick: 0,
      online_players: 0,
      level: 0,
    });
  }
  if (ctx.db.tick_schedule.count() === 0n) {
    ctx.db.tick_schedule.insert({ scheduled_id: 0n, scheduled_at: ScheduleAt.interval(TICK_INTERVAL_US) });
  }
}

// ---------------------------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------------------------

/** Runs once on first publish. Everything here is also in ensure_world (additive publishes skip init). */
export const init = spacetimedb.init((ctx) => {
  ensureWorldInner(ctx, ctx.sender);
});

export const on_connect = spacetimedb.clientConnected((ctx) => {
  requireAdmitted(ctx);
  const p = ctx.db.player.identity.find(ctx.sender);
  if (p) ctx.db.player.identity.update({ ...p, online: true, last_seen: ctx.timestamp });
});

export const on_disconnect = spacetimedb.clientDisconnected((ctx) => {
  // Only online players have a transform row, so subscribers never see offline "ghosts".
  const pos = ctx.db.entity_transform.identity.find(ctx.sender);
  const p = ctx.db.player.identity.find(ctx.sender);
  if (p) {
    ctx.db.player.identity.update({
      ...p,
      online: false,
      last_seen: ctx.timestamp,
      last_x: pos ? pos.x : p.last_x,
      last_y: pos ? pos.y : p.last_y,
    });
  }
  ctx.db.entity_transform.identity.delete(ctx.sender);
  const input = ctx.db.player_input.identity.find(ctx.sender);
  if (input) ctx.db.player_input.identity.update({ ...input, dir_x: 0, dir_y: 0 });
});

// ---------------------------------------------------------------------------------------------
// Player reducers
// ---------------------------------------------------------------------------------------------

/** Create (or rename) the caller's player and spawn them. */
export const join = spacetimedb.reducer({ name: t.string() }, (ctx, { name }) => {
  requireAdmitted(ctx);
  if (!validName(name)) throw new SenderError(`name must be 1-${NAME_MAX_CHARS} letters, digits, space, _ or -`);
  const other = ctx.db.player.name.find(name);
  if (other && !other.identity.isEqual(ctx.sender)) throw new SenderError('name taken');
  const me = ctx.sender;
  let x: number;
  let y: number;
  const existing = ctx.db.player.identity.find(me);
  if (existing) {
    x = existing.last_x; // returning player resumes where they logged out
    y = existing.last_y;
    ctx.db.player.identity.update({ ...existing, name, online: true, last_seen: ctx.timestamp });
  } else {
    // ctx.random is the module's deterministic RNG; Math.random is not available.
    x = ctx.random.integerInRange(-20, 20);
    y = ctx.random.integerInRange(-20, 20);
    ctx.db.player.insert({
      identity: me,
      name,
      online: true,
      created_at: ctx.timestamp,
      last_seen: ctx.timestamp,
      last_x: x,
      last_y: y,
    });
  }
  if (!ctx.db.entity_transform.identity.find(me)) {
    ctx.db.entity_transform.insert({
      identity: me,
      x,
      y,
      cell_x: cellOf(x),
      cell_y: cellOf(y),
      moving: false,
      last_input_seq: 0,
    });
  }
  if (!ctx.db.player_input.identity.find(me)) {
    ctx.db.player_input.insert({ identity: me, dir_x: 0, dir_y: 0, seq: 0 });
  }
});

/** Movement intent: each axis -1, 0 or 1. `seq` lets the client reconcile its prediction. */
export const set_input = spacetimedb.reducer(
  { dir_x: t.i8(), dir_y: t.i8(), seq: t.u32() },
  (ctx, { dir_x, dir_y, seq }) => {
    requireAdmitted(ctx);
    const input = ctx.db.player_input.identity.find(ctx.sender);
    if (!input) throw new SenderError('call join first');
    if (seq !== 0 && seq < input.seq) return; // stale or out-of-order intent: ignore, do not error
    ctx.db.player_input.identity.update({
      ...input,
      dir_x: clamp(dir_x, -1, 1),
      dir_y: clamp(dir_y, -1, 1),
      seq,
    });
  }
);

// ---------------------------------------------------------------------------------------------
// Tick
// ---------------------------------------------------------------------------------------------

export const tick = spacetimedb.reducer(
  { onSchedule: tick_schedule },
  { _row: tick_schedule.rowType },
  (ctx) => {
    // Scheduled reducers are ordinary reducers: without this guard any client could call tick.
    if (!ctx.sender.isEqual(ctx.identity)) throw new SenderError('tick is scheduler-only');
    const health = ctx.db.tick_health.id.find(0);
    if (!health) throw new SenderError('tick_health missing; run ensure_world');

    const interval = TICK_INTERVAL_US;
    let elapsed = ctx.timestamp.microsSinceUnixEpoch - health.last_tick_at.microsSinceUnixEpoch;
    if (elapsed < 0n) elapsed = interval;
    const lateness = elapsed > interval ? elapsed - interval : 0n;
    // Clamp dt so a stalled world does not teleport everyone on the next tick.
    const dt = Number(elapsed > interval * 3n ? interval * 3n : elapsed) / 1_000_000;

    // --- required work: integrate movement intents of online entities ---
    let moved = 0;
    for (const tr of [...ctx.db.entity_transform.iter()]) {
      const input = ctx.db.player_input.identity.find(tr.identity);
      if (!input) continue;
      if (input.dir_x === 0 && input.dir_y === 0) {
        if (tr.moving || tr.last_input_seq !== input.seq) {
          ctx.db.entity_transform.identity.update({ ...tr, moving: false, last_input_seq: input.seq });
        }
        continue;
      }
      let dx = input.dir_x;
      let dy = input.dir_y;
      if (dx !== 0 && dy !== 0) {
        dx *= Math.SQRT1_2;
        dy *= Math.SQRT1_2;
      }
      const x = clamp(tr.x + dx * MAX_SPEED * dt, -WORLD_HALF, WORLD_HALF);
      const y = clamp(tr.y + dy * MAX_SPEED * dt, -WORLD_HALF, WORLD_HALF);
      ctx.db.entity_transform.identity.update({
        ...tr,
        x,
        y,
        cell_x: cellOf(x),
        cell_y: cellOf(y),
        moving: true,
        last_input_seq: input.seq,
      });
      moved++;
    }

    // --- health: scheduler lateness is the cheapest honest load signal inside a module ---
    const avg = (health.avg_lateness_us * 7n + lateness) / 8n;
    const level = avg < interval / 4n ? 0 : avg < interval / 2n ? 1 : avg < interval ? 2 : 3;
    const tick_count = health.tick_count + 1n;

    // --- optional work: shed it first when the world is hot (level >= 2) ---
    let online = health.online_players;
    if (level < 2 && tick_count % HOUSEKEEPING_EVERY === 0n) {
      online = [...ctx.db.player.iter()].filter((p) => p.online).length;
      // Put regeneration, ambient AI, decay, etc. here, batched and bounded.
    }

    ctx.db.tick_health.id.update({
      ...health,
      tick_count,
      last_tick_at: ctx.timestamp,
      last_lateness_us: lateness,
      avg_lateness_us: avg,
      max_lateness_us: health.max_lateness_us > lateness ? health.max_lateness_us : lateness,
      moved_last_tick: moved,
      online_players: online,
      level,
    });
  }
);

// ---------------------------------------------------------------------------------------------
// Admin / ops
// ---------------------------------------------------------------------------------------------

/** Idempotent: safe to call after every publish. Creates missing singletons and the schedule. */
export const ensure_world = spacetimedb.reducer((ctx) => {
  requireAdmin(ctx);
  ensureWorldInner(ctx, config(ctx).admin);
});

/** Close or open the world. Closed = only admin + allowlisted identities may connect or act. */
export const set_admission_open = spacetimedb.reducer({ open: t.bool() }, (ctx, { open }) => {
  requireAdmin(ctx);
  ctx.db.world_config.id.update({ ...config(ctx), admission_open: open });
});

/** Idempotent grant. */
export const allow_identity = spacetimedb.reducer({ identity: t.identity() }, (ctx, { identity }) => {
  requireAdmin(ctx);
  if (!ctx.db.allowlist.identity.find(identity)) {
    ctx.db.allowlist.insert({ identity, granted_at: ctx.timestamp });
  }
});

/** Idempotent revoke. The socket stays open, but every reducer now fails requireAdmitted. */
export const revoke_identity = spacetimedb.reducer({ identity: t.identity() }, (ctx, { identity }) => {
  requireAdmin(ctx);
  ctx.db.allowlist.identity.delete(identity);
  const input = ctx.db.player_input.identity.find(identity);
  if (input) ctx.db.player_input.identity.update({ ...input, dir_x: 0, dir_y: 0 });
});
