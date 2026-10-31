/**
 * Headless bot clients for the kit's starter module (templates/server/rust-single and
 * templates/server/ts-single expose the same reducers: join, set_input).
 *
 *   --mode smoke : two bots join, each moves, each must SEE the other move. Exit 0 = PASS.
 *   --mode swarm : N bots join (ramped), wander with random intents, subscribe by AOI cell,
 *                  and report reducer latency + received row updates as JSON on stdout.
 *
 * Bindings are generated into src/module_bindings by tools/bindings/run.py (or loadtest/run.py).
 */
import { DbConnection } from './module_bindings/index.ts';

type Args = { uri: string; db: string; mode: string; bots: number; duration: number; rampMs: number; cell: number; inputMs: number };

function parseArgs(argv: string[]): Args {
  const a: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) a[argv[i].slice(2)] = argv[i + 1] ?? '';
  }
  return {
    uri: a.uri ?? 'ws://127.0.0.1:3000',
    db: a.db ?? 'mmo-dev',
    mode: a.mode ?? 'smoke',
    bots: Number(a.bots ?? 2),
    duration: Number(a.duration ?? 20),
    rampMs: Number(a['ramp-ms'] ?? 50),
    cell: Number(a['cell-size'] ?? 50),
    inputMs: Number(a['input-ms'] ?? 250),
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function pct(xs: number[], p: number): number {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((x, y) => x - y);
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))];
}

class Bot {
  conn!: DbConnection;
  hex = '';
  ready = false;
  updates = 0;
  latencies: number[] = [];
  errors = 0;
  seq = 0;
  cellKey = '';
  cellSub: { unsubscribe(): void }[] = [];

  constructor(public args: Args, public name: string) {}

  connect(fullWorld: boolean): Promise<void> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`${this.name}: connect timeout`)), 15000);
      this.conn = DbConnection.builder()
        .withUri(this.args.uri)
        .withDatabaseName(this.args.db)
        .onConnect((conn, identity) => {
          this.hex = identity.toHexString();
          conn.db.entityTransform.onUpdate(() => { this.updates++; });
          conn.db.entityTransform.onInsert(() => { this.updates++; });
          const queries = fullWorld
            ? ['SELECT * FROM player', 'SELECT * FROM entity_transform', 'SELECT * FROM tick_health']
            : ['SELECT * FROM tick_health', `SELECT * FROM entity_transform WHERE identity = 0x${this.hex}`];
          conn.subscriptionBuilder()
            .onApplied(() => { this.ready = true; clearTimeout(timer); resolve(); })
            .onError((ctx) => { clearTimeout(timer); reject(new Error(`${this.name}: subscribe error ${String((ctx as any).event ?? '')}`)); })
            .subscribe(queries);
        })
        .onConnectError((_ctx, err) => { clearTimeout(timer); reject(err); })
        .build();
    });
  }

  async call<T>(fn: () => Promise<T>): Promise<void> {
    const t0 = performance.now();
    try {
      await fn();
      this.latencies.push(performance.now() - t0);
    } catch (e) {
      this.errors++;
      if (this.errors <= 3) console.error(`${this.name}: reducer error: ${String(e)}`);
    }
  }

  join() { return this.call(() => this.conn.reducers.join({ name: this.name })); }

  move(dx: number, dy: number) {
    this.seq++;
    return this.call(() => this.conn.reducers.setInput({ dirX: dx, dirY: dy, seq: this.seq }));
  }

  myTransform() {
    for (const t of this.conn.db.entityTransform.iter()) if (t.identity.toHexString() === this.hex) return t;
    return undefined;
  }

  /** AOI: subscribe to the 3x3 cells around me; resubscribe only when my cell changes. */
  updateAoi() {
    const me = this.myTransform();
    if (!me) return;
    const key = `${me.cellX},${me.cellY}`;
    if (key === this.cellKey) return;
    this.cellKey = key;
    const old = this.cellSub;
    const q = `SELECT * FROM entity_transform WHERE cell_x >= ${me.cellX - 1} AND cell_x <= ${me.cellX + 1} AND cell_y >= ${me.cellY - 1} AND cell_y <= ${me.cellY + 1}`;
    this.cellSub = [this.conn.subscriptionBuilder().subscribe(q)];
    for (const s of old) s.unsubscribe(); // new set first, then drop the old one: no flicker
  }

  close() { try { this.conn.disconnect(); } catch { /* ignore */ } }
}

async function smoke(args: Args): Promise<number> {
  const tag = Math.floor(Math.random() * 1e6).toString(36);
  const a = new Bot(args, `smokeA-${tag}`);
  const b = new Bot(args, `smokeB-${tag}`);
  await Promise.all([a.connect(true), b.connect(true)]);
  await a.join(); await b.join();
  await sleep(500);
  const seen = (viewer: Bot, target: Bot) =>
    [...viewer.conn.db.entityTransform.iter()].find((t) => t.identity.toHexString() === target.hex);
  const b0 = seen(a, b), a0 = seen(b, a);
  if (!a0 || !b0) { console.log(JSON.stringify({ verdict: 'FAIL', reason: 'players cannot see each other' })); return 1; }
  await a.move(1, 0); await b.move(0, -1);
  await sleep(1500);
  await a.move(0, 0); await b.move(0, 0);
  await sleep(300);
  const a1 = seen(b, a)!, b1 = seen(a, b)!;
  const result = {
    verdict: a1.x > a0.x + 1 && b1.y < b0.y - 1 ? 'PASS' : 'FAIL',
    a_seen_by_b: { from: [a0.x, a0.y], to: [a1.x, a1.y] },
    b_seen_by_a: { from: [b0.x, b0.y], to: [b1.x, b1.y] },
    reducer_p95_ms: pct([...a.latencies, ...b.latencies], 95),
  };
  console.log(JSON.stringify(result));
  a.close(); b.close();
  return result.verdict === 'PASS' ? 0 : 1;
}

async function swarm(args: Args): Promise<number> {
  const tag = Math.floor(Math.random() * 1e6).toString(36);
  const bots: Bot[] = [];
  let connectFailures = 0;
  const t0 = performance.now();
  for (let i = 0; i < args.bots; i++) {
    const bot = new Bot(args, `bot${i}-${tag}`);
    bots.push(bot);
    bot.connect(false).then(() => bot.join()).then(() => bot.updateAoi()).catch((e) => { connectFailures++; console.error(String(e)); });
    await sleep(args.rampMs);
  }
  const rampSeconds = (performance.now() - t0) / 1000;
  const end = performance.now() + args.duration * 1000;
  while (performance.now() < end) {
    for (const bot of bots) {
      if (!bot.ready) continue;
      if (Math.random() < 0.3) {
        const dx = Math.floor(Math.random() * 3) - 1, dy = Math.floor(Math.random() * 3) - 1;
        void bot.move(dx, dy);
      }
      bot.updateAoi();
    }
    await sleep(args.inputMs);
  }
  const lat = bots.flatMap((b) => b.latencies);
  const health = bots.find((b) => b.ready)?.conn.db.tickHealth.id.find(0);
  const report = {
    mode: 'swarm',
    bots_requested: args.bots,
    bots_ready: bots.filter((b) => b.ready).length,
    connect_failures: connectFailures,
    ramp_seconds: rampSeconds,
    duration_seconds: args.duration,
    reducer_calls: lat.length,
    reducer_errors: bots.reduce((s, b) => s + b.errors, 0),
    reducer_p50_ms: pct(lat, 50),
    reducer_p95_ms: pct(lat, 95),
    reducer_p99_ms: pct(lat, 99),
    row_updates_received: bots.reduce((s, b) => s + b.updates, 0),
    tick_health: health ? {
      tick_count: Number(health.tickCount), avg_lateness_us: Number(health.avgLatenessUs),
      max_lateness_us: Number(health.maxLatenessUs), level: health.level, moved_last_tick: health.movedLastTick,
    } : null,
  };
  console.log(JSON.stringify(report));
  for (const b of bots) b.close();
  return 0;
}

const args = parseArgs(process.argv.slice(2));
const code = await (args.mode === 'smoke' ? smoke(args) : swarm(args));
setTimeout(() => process.exit(code), 200);
