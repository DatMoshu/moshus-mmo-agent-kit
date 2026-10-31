# Adding a feature end to end (the loop agents follow)

1. **Design the data.** Hot vs cold tables, public vs private vs view, indexes for every filter you subscribe on.
   → `agents/stdb-architect.md`, `skills/stdb-schema-design`.
2. **Write reducers.** Sender from `ctx.sender()`, validate everything, return `Err` to roll back, no I/O, no clocks other
   than `ctx.timestamp`. → `skills/stdb-reducer-author`.
3. **Check the API is real.** `python tools/kit.py check` (the hallucination check flags SDK names that do not exist in the pinned version).
4. **Publish locally.** `python tools/kit.py publish` (`--wipe` deletes data; use it for dev only).
5. **Regenerate bindings** for every client. `python tools/kit.py bindings`.
6. **Client.** Subscribe narrowly (AOI), call reducers with typed args, render from the cache, never from reducer results.
7. **Prove it.** `python tools/kit.py smoke`, then `loadtest --bots 100` if the feature touches the tick or hot tables.
8. **Security pass.** → `skills/stdb-security-review`: who can call it, what it leaks through public tables, and whether it can be replayed.
9. **Migration plan** if live data exists. → `skills/stdb-migration` (add columns at the end with defaults; never reorder).
10. **Record it.** Add a row to `docs/VERIFICATION.md` saying what you ran and what passed.
