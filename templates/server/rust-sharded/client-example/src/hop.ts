/**
 * Region-hop client for the sharded template: the reference for client code that follows a player across region databases.
 *
 *   npx tsx src/hop.ts --uri ws://127.0.0.1:3000 --global mmo-global --region mmo-region-1 --hops 2
 *
 * It connects to the global database to read the `region` directory, joins a region, and walks east. When
 * the server hands the player to the next region, `my_departure` gets a row. The client then reconnects to
 * that region's database **with the same token** (same identity) and waits until `my_player.state` is
 * Active (0). Exits 0 with HOP PASS after `--hops` successful handoffs.
 */
import { DbConnection as GlobalConn } from './global_bindings/index.ts';
import { DbConnection as RegionConn } from './region_bindings/index.ts';

const argv = process.argv.slice(2);
const arg = (k: string, d: string) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const URI = arg('uri', 'ws://127.0.0.1:3000');
const GLOBAL = arg('global', 'mmo-global');
const HOPS = Number(arg('hops', '1'));
const NAME = arg('name', `hopper${Math.floor(Math.random() * 1e4)}`);  // kit:allow (client code, not a module)
const TIMEOUT_S = Number(arg('timeout', '120'));

let token: string | undefined;          // the player's identity; keep it secret, reuse it everywhere
let hops = 0;
const regions = new Map<number, string>(); // region_id -> database_name, from global `region`
setTimeout(() => { console.error(`HOP FAIL: timeout after ${TIMEOUT_S}s (${hops}/${HOPS} hops)`); process.exit(1); }, TIMEOUT_S * 1000);

function connectGlobal(): Promise<void> {
  return new Promise((resolve, reject) => {
    GlobalConn.builder().withUri(URI).withDatabaseName(GLOBAL)
      .onConnect((c) => {
        c.subscriptionBuilder().onApplied(() => {
          for (const r of c.db.region.iter()) regions.set(r.regionId, r.databaseName);
          c.db.region.onInsert((_e, r) => regions.set(r.regionId, r.databaseName));
          resolve();
        }).subscribe(['SELECT * FROM region']);
      })
      .onConnectError((_c, e) => reject(e))
      .build();
  });
}

function enterRegion(dbName: string, firstJoin: boolean): void {
  console.log(`connecting to ${dbName}${firstJoin ? '' : ' (handoff)'}`);
  let leaving = false;
  RegionConn.builder().withUri(URI).withDatabaseName(dbName).withToken(token)
    .onConnect((c, identity, tok) => {
      token = tok;
      c.subscriptionBuilder().onApplied(async () => {
        if (firstJoin) await c.reducers.join({ name: NAME });
        // After a handoff the row may already be Active, or turn Active shortly (Arriving -> Active).
        const ready = () => {
          const me = [...c.db.myPlayer.iter()][0];
          if (me && me.state === 0) {
            if (!firstJoin) {
              hops += 1;
              console.log(`hop ${hops}: active in ${dbName} as ${identity.toHexString().slice(0, 12)}`);
              if (hops >= HOPS) { console.log('HOP PASS'); process.exit(0); }
            }
            void c.reducers.setInput({ dirX: 1, dirY: 0 }); // keep walking east
            return true;
          }
          return false;
        };
        if (!ready()) c.db.myPlayer.onInsert(() => { ready(); });
        c.db.myPlayer.onUpdate(() => { ready(); });
      }).subscribe(['SELECT * FROM my_player', 'SELECT * FROM my_departure']);

      c.db.myDeparture.onInsert((_e, d) => {
        if (leaving) return;
        leaving = true;
        const next = regions.get(d.toRegion);
        if (!next) { console.error(`HOP FAIL: region ${d.toRegion} not in the global directory`); process.exit(1); }
        c.disconnect();
        enterRegion(next, false);
      });
    })
    .onConnectError((_c, e) => { console.error(`HOP FAIL: connect ${dbName}: ${String(e)}`); process.exit(1); })
    .build();
}

await connectGlobal();
const startId = Number(arg('region-id', '0'));
const start = arg('region', startId ? (regions.get(startId) ?? '') : [...regions.entries()].sort((a, b) => a[0] - b[0])[0]?.[1] ?? '');
if (!start) { console.error('HOP FAIL: no regions registered in the global database'); process.exit(1); }
enterRegion(start, true);
