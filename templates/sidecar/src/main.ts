/**
 * ops sidecar: a long-running helper process with its OWN SpacetimeDB identity.
 *
 * What it does
 *   - subscribes to the public tables tick_health, world_config and player
 *   - prints one status line every --every seconds
 *   - serves GET /health on 127.0.0.1:<--http-port> (JSON) for uptime checks / dashboards
 *   - with --guard: when tick_health.level stays at --red-level (default 3 = red) for --red-ticks status lines,
 *     calls set_admission_open(false). That reducer is admin-only, so the module must
 *     recognise this sidecar's identity (see README "Giving the sidecar a role").
 *
 * Works against templates/server/rust-single and templates/server/ts-single (same schema).
 * Bindings: `python tools/kit.py bindings` writes src/module_bindings.
 */
import { createServer } from 'node:http';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { DbConnection } from './module_bindings/index.ts';

type Args = { uri: string; db: string; every: number; httpPort: number; guard: boolean; redTicks: number; redLevel: number; tokenFile: string; once: boolean };

function parseArgs(argv: string[]): Args {
  const a: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith('--')) continue;
    const next = argv[i + 1];
    a[argv[i].slice(2)] = next === undefined || next.startsWith('--') ? 'true' : next;
  }
  return {
    uri: a.uri ?? 'ws://127.0.0.1:3000',
    db: a.db ?? 'mmo-dev',
    every: Number(a.every ?? 5),
    httpPort: Number(a['http-port'] ?? 0), // 0 = no HTTP server
    guard: a.guard === 'true',
    redTicks: Number(a['red-ticks'] ?? 3),
    redLevel: Number(a['red-level'] ?? 3), // tick_health.level that counts as red (0..3)
    tokenFile: a['token-file'] ?? '', // empty = fresh anonymous identity each run
    once: a.once === 'true', // print one status line and exit 0 (CI / smoke)
  };
}

const args = parseArgs(process.argv.slice(2));

function loadToken(): string | undefined {
  if (!args.tokenFile || !existsSync(args.tokenFile)) return undefined;
  return readFileSync(args.tokenFile, 'utf8').trim() || undefined;
}

function saveToken(token: string) {
  if (!args.tokenFile) return;
  mkdirSync(dirname(args.tokenFile), { recursive: true });
  writeFileSync(args.tokenFile, token, { mode: 0o600 });
}

type Status = {
  connected: boolean;
  identity: string;
  is_admin: boolean;
  tick_count: number;
  level: number;
  avg_lateness_us: number;
  max_lateness_us: number;
  online_players: number;
  players_total: number;
  admission_open: boolean | null;
  tick_age_ms: number | null;
  guard_actions: number;
  last_error: string;
};

const status: Status = {
  connected: false, identity: '', is_admin: false, tick_count: 0, level: 0, avg_lateness_us: 0,
  max_lateness_us: 0, online_players: 0, players_total: 0, admission_open: null, tick_age_ms: null,
  guard_actions: 0, last_error: '',
};

let conn: DbConnection;
let redStreak = 0;

function refresh() {
  const h = [...conn.db.tickHealth.iter()][0];
  const cfg = [...conn.db.worldConfig.iter()][0];
  if (h) {
    status.tick_count = Number(h.tickCount);
    status.level = h.level;
    status.avg_lateness_us = Number(h.avgLatenessUs);
    status.max_lateness_us = Number(h.maxLatenessUs);
    status.online_players = h.onlinePlayers;
    // Timestamp -> ms since epoch
    const ms = Number(h.lastTickAt.microsSinceUnixEpoch / 1000n);
    status.tick_age_ms = Date.now() - ms;
  }
  if (cfg) {
    status.admission_open = cfg.admissionOpen;
    status.is_admin = cfg.admin.toHexString() === status.identity;
  }
  status.players_total = Number(conn.db.player.count());
}

async function guardStep() {
  if (!args.guard) return;
  redStreak = status.level >= args.redLevel ? redStreak + 1 : 0;
  if (redStreak < args.redTicks || status.admission_open === false) return;
  try {
    await conn.reducers.setAdmissionOpen({ open: false });
    status.guard_actions++;
    console.log(`guard: tick red for ${redStreak} checks; admission closed`);
  } catch (e) {
    status.last_error = `set_admission_open failed: ${String(e)}`;
    console.error(`guard: ${status.last_error}`);
  }
  redStreak = 0;
}

function line(): string {
  return `tick=${status.tick_count} level=${status.level} avg_late=${status.avg_lateness_us}us ` +
    `max_late=${status.max_lateness_us}us online=${status.online_players}/${status.players_total} ` +
    `admission=${status.admission_open} age=${status.tick_age_ms}ms admin=${status.is_admin}`;
}

conn = DbConnection.builder()
  .withUri(args.uri)
  .withDatabaseName(args.db)
  .withToken(loadToken())
  .onConnect((c, identity, token) => {
    status.connected = true;
    status.identity = identity.toHexString();
    saveToken(token);
    console.log(`sidecar connected as ${status.identity} to ${args.db}`);
    c.subscriptionBuilder()
      .onApplied(async () => {
        refresh();
        console.log(line());
        if (args.once) {
          const ok = status.tick_count > 0;
          console.log(ok ? 'SIDECAR PASS' : 'SIDECAR FAIL: no tick_health row');
          c.disconnect();
          process.exit(ok ? 0 : 1);
        }
        setInterval(async () => { refresh(); console.log(line()); await guardStep(); }, args.every * 1000);
      })
      .onError((ctx) => { status.last_error = `subscribe error ${String((ctx as any).event ?? '')}`; console.error(status.last_error); })
      .subscribe(['SELECT * FROM tick_health', 'SELECT * FROM world_config', 'SELECT * FROM player']);
  })
  .onDisconnect(() => {
    status.connected = false;
    console.error('sidecar disconnected; exiting so a supervisor (systemd, pm2, docker) restarts it');
    process.exit(2);
  })
  .onConnectError((_ctx, err) => { console.error(`connect error: ${String(err)}`); process.exit(2); })
  .build();

if (args.httpPort > 0) {
  createServer((req, res) => {
    if (req.url !== '/health') { res.writeHead(404).end(); return; }
    const healthy = status.connected && status.level < 3 && (status.tick_age_ms ?? 1e9) < 5000;
    res.writeHead(healthy ? 200 : 503, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ healthy, ...status }));
  }).listen(args.httpPort, '127.0.0.1', () => console.log(`health on http://127.0.0.1:${args.httpPort}/health`));
}
