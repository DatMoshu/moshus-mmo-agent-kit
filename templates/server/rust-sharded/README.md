# rust-sharded: global database + region databases with cross-database handoff

**Status: VERIFIED** on SpacetimeDB 2.14.0 with Rust 1.97.1 / wasm32 on a local server
(publish, wiring, border handoff in both directions, spoofed IDC calls rejected; see `docs/VERIFICATION.md`).

Use this when one database is not enough (see `docs/scale-ladder.md` and `skills/stdb-sharding-plan`).
Start with `rust-single` unless you already know you need shards: sharding adds operations work.

```
             +-------------------------+
             |  global  (mmo-global)   |  region registry (IDC allow-list), player_home,
             +-----------^-------------+  heartbeats. Clients read `region` to find a shard.
      heartbeat /        | player_entered
                /        |
 +-------------+--+   IDC handoff   +----------------+
 | region 1        | <------------> | region 2        |   same module, different x strip
 | x in [-500, 0)  |                | x in [0, 500)   |
 +-----------------+                +-----------------+
```

## Layout

| Path | What |
|---|---|
| `global/` | `mmo_global`: `region` (public registry), `player_home` (private, view `my_home`), `register_region`, `region_heartbeat`, `player_entered` |
| `region/` | `mmo_region`: movement tick, AOI cells, the handoff protocol, IDC outboxes |
| `region/src/remote_bindings/` | **Generated** receiver bindings for `global` and `region` (from `spacetime.json`). Never edit. |
| `spacetime.json` | Databases and the region module's IDC dependencies |
| `scripts/dev_up.py` | Build, publish and wire a local world with N regions |

## The handoff protocol (lock, offer, accept, delete, activate)

1. **lock**: the region tick sees a player cross `x_max`/`x_min`, marks them `Leaving` and freezes input.
2. **offer**: a row in `offer_handoff_outbox` calls `accept_handoff` on the peer after commit.
3. **accept** (peer): checks the caller is in `peer`, validates the position, stores the player as `Arriving`.
4. **delete**: `on_offer_result` gets `Ok`: delete the local player, write `departure`, send `activate_handoff`.
   On `Err` the player is unlocked locally instead.
5. **activate** (peer): the player becomes `Active`, gets a transform, and the global database hears `player_entered`.

Why this is safe: IDC delivery is exactly-once and in order per outbox and target; every IDC reducer is
idempotent on `handoff_key`; the player is never `Active` in two regions. Arriving players cannot act
until activation.

**Client flow:** subscribe to `my_player` and `my_departure` in the current region. When `my_departure`
gets a row, look up `to_region` in global `region.database_name`, connect there with the same token,
and wait until `my_player.state == 0` (Active). Working client: `client-example/src/hop.ts` (walkthrough in `recipes/region-handoff-client.md`).

## IDC rules this template follows

* Every IDC-called reducer checks `ctx.sender()` against an allow-list (`peer` in regions, `region` in global).
* `client_connected` never rejects: the server runs it around each delivered IDC call, and a rejected
  call is retried forever.
* Every outbox has an `on_result` reducer (rows are deleted after it runs).
* Player reducers refuse callers that are databases (`require_player_caller`).
* Identity columns in outboxes use the generated `remote_bindings::*::Identity` wrapper.

## Build

```bash
cargo build --target wasm32-unknown-unknown --release
```

### Regenerating the IDC bindings

The region module calls itself (peer regions) and the global module. After you change the parameters of
`accept_handoff`, `activate_handoff`, `region_heartbeat` or `player_entered`:

```bash
spacetime generate mmo-region-1 -y      # reads spacetime.json, writes region/src/remote_bindings/
cargo build --target wasm32-unknown-unknown --release
spacetime generate mmo-region-1 -y      # second pass: picks up region's own new signatures
```

Then republish the receiver **before** the senders. A missing `rustfmt` only prints a warning.
If you rename a reducer that the region calls on itself and the build breaks, temporarily stub the old
call sites, generate, then restore them (the bindings are produced from the built wasm).

## Run locally

```bash
spacetime start                                  # local server on :3000
python scripts/dev_up.py --regions 2             # build + publish + wire mmo-global, mmo-region-1..2
python scripts/dev_up.py --regions 4 --wipe      # start over with 4 strips (dev only)
```

Manual runbook (what `dev_up.py` does), with `S=http://127.0.0.1:3000`:

```bash
spacetime publish -s $S --bin-path target/wasm32-unknown-unknown/release/mmo_global.wasm --no-config -y mmo-global
spacetime publish -s $S --bin-path target/wasm32-unknown-unknown/release/mmo_region.wasm --no-config -y mmo-region-1
spacetime publish -s $S --bin-path target/wasm32-unknown-unknown/release/mmo_region.wasm --no-config -y mmo-region-2
# note each identity printed above (G, R1, R2), then:
spacetime call --no-config -s $S mmo-global register_region -- 1 '"R1"' '"mmo-region-1"' -500 0
spacetime call --no-config -s $S mmo-global register_region -- 2 '"R2"' '"mmo-region-2"' 0 500
spacetime call --no-config -s $S mmo-region-1 configure_region -- 1 -500 0 '"G"'
spacetime call --no-config -s $S mmo-region-2 configure_region -- 2 0 500 '"G"'
spacetime call --no-config -s $S mmo-region-1 add_peer -- 2 '"R2"' 0 500
spacetime call --no-config -s $S mmo-region-2 add_peer -- 1 '"R1"' -500 0
```

Use `--` before arguments so negative numbers are not read as flags.

### Smoke test a handoff from the CLI

`spacetime call` disconnects after each call and a disconnect clears movement input, so use the admin
`gm_teleport` reducer to push a player over the border:

```bash
spacetime call --no-config -s $S mmo-region-1 join -- '"Tester"'
spacetime login show                       # your identity = the player
spacetime call --no-config -s $S mmo-region-1 gm_teleport -- '"0xYOUR_IDENTITY"' 10 5
spacetime sql  --no-config -s $S mmo-region-2 "SELECT * FROM entity_transform"   # player is here
spacetime sql  --no-config -s $S mmo-region-1 "SELECT * FROM departure"          # to_region = 2
spacetime sql  --no-config -s $S mmo-global   "SELECT * FROM player_home"        # region_id = 2
```

## Licensing note

SpacetimeDB 2.x is BSL 1.1: the Additional Use Grant covers **one** production SpacetimeDB instance.
Several databases on one instance are fine; several instances need a commercial license or Maincloud.
Read `docs/legal/LICENSING.md`.

## Limits and next steps

* Strips on one axis only. For a 2D grid, give `peer` y bounds and route on both axes.
* No interest across borders: players near an edge do not see the other side. Clients can subscribe
  to the neighbour's `entity_transform` near the border (read-only).
* Inventory and other per-player data must move with the player: add columns to the offer outbox
  (and to `accept_handoff`), or keep it in global.
* `on_activate_result` only logs failures. A production game should alert and offer a GM repair reducer.
