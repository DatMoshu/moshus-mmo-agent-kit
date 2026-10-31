# web-admin: browser dashboard for your world

**Status: VERIFIED** on Linux: `npm run build` (tsc + Vite 8) is clean, and headless Chrome against
a live 2.14 database rendered tick health, admission state and all 56 player rows (see `docs/VERIFICATION.md`).

A small vanilla-TypeScript page (no framework) that subscribes to the starter world's public tables:

* tick health cards: level (green/yellow/orange/red), tick count, average and max lateness, last tick age
* player table: name, online, position, AOI cell
* admin controls (shown only when your browser identity is `world_config.admin`): open or close
  admission, allow or revoke an identity

```bash
npm install
python ../../../tools/kit.py bindings     # writes src/module_bindings from the module source
npm run dev                               # http://localhost:5173/?uri=ws://127.0.0.1:3000&db=mmo-dev
npm run build                             # static files in dist/
```

## Security model

* The page reads only **public** tables. Private tables (`allowlist`, `player_input`) never reach the browser.
* The admin buttons are a convenience. The module enforces `require_admin` in each reducer, so
  hiding or showing buttons is not security.
* The browser keeps its identity token in `localStorage` (the SDK's usual pattern). Anyone with that
  token *is* that identity. Do not host an admin page for your production admin identity on a
  shared machine. Prefer an operator role (see `templates/sidecar/README.md`) that you can revoke.
* The player table is capped at 500 rows. For a big world, subscribe to a filtered query
  (`WHERE online = true`) or add a paged admin view instead of subscribing to every player.

## Extending

* New table: add it to the module, run `kit.py bindings`, add `SELECT * FROM <table>` to the
  subscription list and an `onInsert`/`onUpdate`/`onDelete` → `scheduleRender` hook.
* Want React? The SDK ships React hooks (`spacetimedb/react`). See
  `skills/vendor/official/typescript-client`. The data flow stays the same.
