# rust-single: one-database world module (start here)

**Status: VERIFIED** on SpacetimeDB 2.14.0 with Rust 1.97.1 / wasm32 (see `docs/VERIFICATION.md`).

This is a complete, small MMO world module:

| Table | Visibility | Why |
|---|---|---|
| `world_config` | public | Admission flag, tick rate, world bounds. One row. |
| `allowlist` | private | Identities admitted while admission is closed. |
| `player` | public | Cold data: name, online flag, last position. |
| `player_input` | **private** | Latest movement intent. Never broadcast. |
| `entity_transform` | public, `by_cell` index | Hot data: position + AOI cell. Exists **only while the player is online**, so clients never see ghosts. |
| `tick_schedule` | private | Scheduled 20 Hz tick. |
| `tick_health` | public | Scheduler lateness (EMA/max), moved count, degradation level 0-3. |

The reducers are `join(name)`, `set_input(dir_x, dir_y, seq)`, the scheduler-only `tick`, and
these admin reducers (only the admin identity recorded at `init`, normally the publisher): `ensure_world`, `set_admission_open`,
`allow_identity`, and `revoke_identity`.

## Patterns worth copying

* **Intent, not position.** Clients send `-1..1` axes plus a sequence number. The tick
  integrates them with the max speed and the world bounds, and stale sequences are ignored.
* **The scheduler-only guard:** `ctx.sender() != ctx.database_identity()` -> `Err`.
* **Online-only hot rows.** `on_disconnect` copies the position into `player.last_x/last_y`
  and deletes the transform. `join` restores it.
* **Health as a load signal.** Scheduler lateness is the cheapest honest metric available
  inside a module. Optional work (housekeeping) is skipped at level >= 2.
* **Cells for AOI.** Each `cell_x/cell_y` is 50 world units (`CELL_SIZE`). Clients subscribe to a 3x3 block
  of cells.

## Build and publish

```bash
cargo build --target wasm32-unknown-unknown --release
spacetime publish mmo-dev --server http://127.0.0.1:3000 --module-path . --yes
# or from the repo root: python tools/kit.py publish
```

Changed a table? Use additive changes for live worlds (`skills/stdb-migration`). In dev,
`python tools/kit.py publish --wipe` deletes the data.
