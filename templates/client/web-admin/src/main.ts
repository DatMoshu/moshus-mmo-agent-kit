/**
 * Web admin for the kit's starter world (rust-single / ts-single share the schema).
 * Bindings: `python tools/kit.py bindings` writes src/module_bindings.
 *
 * Reads only PUBLIC tables. Admin buttons call admin-only reducers; the module decides who
 * may use them (identity check in the reducer), the page just shows the error if you are not admin.
 */
import { Identity } from 'spacetimedb';
import { DbConnection } from './module_bindings/index.ts';

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const params = new URLSearchParams(location.search);
if (params.get('uri')) $<HTMLInputElement>('uri').value = params.get('uri')!;
if (params.get('db')) $<HTMLInputElement>('db').value = params.get('db')!;

let conn: DbConnection | null = null;
let me = '';

function log(msg: string) {
  const el = $('log');
  el.textContent = `${new Date().toLocaleTimeString()} ${msg}\n` + (el.textContent ?? '').slice(0, 4000);
}

function esc(s: string) {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

function render() {
  if (!conn) return;
  const h = [...conn.db.tickHealth.iter()][0];
  const cfg = [...conn.db.worldConfig.iter()][0];
  const isAdmin = !!cfg && cfg.admin.toHexString() === me;
  $('admin').hidden = !isAdmin;
  const age = h ? Date.now() - Number(h.lastTickAt.microsSinceUnixEpoch / 1000n) : NaN;
  const cards: [string, string, string?][] = h
    ? [
        ['Tick level', String(h.level), `lvl${h.level}`],
        ['Ticks', String(h.tickCount)],
        ['Avg lateness', `${h.avgLatenessUs} µs`],
        ['Max lateness', `${h.maxLatenessUs} µs`],
        ['Moved last tick', String(h.movedLastTick)],
        ['Online', String(h.onlinePlayers)],
        ['Last tick age', `${age} ms`, age > 2000 ? 'lvl3' : ''],
        ['Admission', cfg ? (cfg.admissionOpen ? 'open' : 'closed') : '?'],
        ['You', isAdmin ? 'admin' : 'viewer'],
      ]
    : [['Tick', 'no tick_health row yet']];
  $('cards').innerHTML = cards
    .map(([k, v, cls]) => `<div class="card">${esc(k)}<b class="${cls ?? ''}">${esc(v)}</b></div>`)
    .join('');
  const tf = new Map([...conn.db.entityTransform.iter()].map((t) => [t.identity.toHexString(), t]));
  const rows = [...conn.db.player.iter()]
    .sort((a, b) => Number(b.online) - Number(a.online) || a.name.localeCompare(b.name))
    .slice(0, 500)
    .map((p) => {
      const hex = p.identity.toHexString();
      const t = tf.get(hex);
      const pos = t ? `${t.x.toFixed(1)}, ${t.y.toFixed(1)}` : `${p.lastX.toFixed(1)}, ${p.lastY.toFixed(1)} (last)`;
      const cell = t ? `${t.cellX}, ${t.cellY}` : '';
      return `<tr><td>${esc(p.name)}</td><td>${p.online ? 'yes' : ''}</td><td>${pos}</td><td>${cell}</td><td><code>${hex.slice(0, 16)}…</code></td></tr>`;
    });
  $('players').innerHTML = rows.join('');
}

let scheduled = false;
function scheduleRender() {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => { scheduled = false; render(); });
}

async function act(label: string, fn: () => Promise<unknown>) {
  try { await fn(); log(`${label}: ok`); } catch (e) { log(`${label}: ${String(e)}`); }
}

function connect(uri: string, db: string) {
  conn?.disconnect();
  const tokenKey = `mmo-admin-token:${uri}:${db}`;
  conn = DbConnection.builder()
    .withUri(uri)
    .withDatabaseName(db)
    // The token is this browser's identity for this database. localStorage is the SDK's usual
    // place for it; clear it to become a new viewer. Never paste it anywhere.
    .withToken(localStorage.getItem(tokenKey) ?? undefined)
    .onConnect((c, identity: Identity, token: string) => {
      localStorage.setItem(tokenKey, token);
      me = identity.toHexString();
      $('who').textContent = `connected as ${me.slice(0, 16)}…`;
      for (const t of [c.db.tickHealth, c.db.worldConfig, c.db.player, c.db.entityTransform]) {
        t.onInsert(scheduleRender); t.onDelete(scheduleRender);
      }
      c.db.tickHealth.onUpdate(scheduleRender);
      c.db.worldConfig.onUpdate(scheduleRender);
      c.db.player.onUpdate(scheduleRender);
      c.db.entityTransform.onUpdate(scheduleRender);
      c.subscriptionBuilder()
        .onApplied(() => { log('subscribed'); render(); })
        .onError(() => log('subscription error'))
        .subscribe(['SELECT * FROM tick_health', 'SELECT * FROM world_config', 'SELECT * FROM player', 'SELECT * FROM entity_transform']);
    })
    .onDisconnect(() => { $('who').textContent = 'disconnected'; log('disconnected'); })
    .onConnectError((_c, err) => log(`connect error: ${String(err)}`))
    .build();
}

$('connect').addEventListener('submit', (e) => {
  e.preventDefault();
  connect($<HTMLInputElement>('uri').value.trim(), $<HTMLInputElement>('db').value.trim());
});
$('open').onclick = () => act('open admission', () => conn!.reducers.setAdmissionOpen({ open: true }));
$('close').onclick = () => act('close admission', () => conn!.reducers.setAdmissionOpen({ open: false }));
function identArg() {
  const v = $<HTMLInputElement>('ident').value.trim().replace(/^0x/, '');
  return { identity: Identity.fromString(v) };
}
$('allow').onclick = () => act('allow', () => conn!.reducers.allowIdentity(identArg()));
$('revoke').onclick = () => act('revoke', () => conn!.reducers.revokeIdentity(identArg()));

connect($<HTMLInputElement>('uri').value, $<HTMLInputElement>('db').value);
