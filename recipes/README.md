# Recipes

Short, copyable answers to "how do I add X to my world?". Each recipe builds on `templates/server/rust-single`.
It names the files it touches and says how it was checked.

| Recipe | What you get | Checked |
|---|---|---|
| [aoi-subscriptions.md](aoi-subscriptions.md) | Clients see only nearby cells; bandwidth stays flat as the world grows | Bots and Godot client (load-test gate) |
| [inventory-and-trades.md](inventory-and-trades.md) | Stacks, grants, player-to-player give with no duplication | Compiled + live run |
| [chat.md](chat.md) | Proximity chat with rate limit and retention | Compiled + live run (two clients) |
| [idempotent-requests.md](idempotent-requests.md) | Retry-safe reducers for HTTP callers, sidecars and webhooks | Compiled + live run |
| [operator-role.md](operator-role.md) | Sidecars and GM tools act with their own identity, not the publisher's token | Compiled + live run with `templates/sidecar --guard` |
| [region-handoff-client.md](region-handoff-client.md) | Client follows its player across region databases (sharded template) | Live run: 2 handoffs, same identity |
| [sidecar-npc-brain.md](sidecar-npc-brain.md) | Heavy NPC AI or pathfinding outside the tick | Pattern only; builds on the verified operator role |
| [invite-only-playtest.md](invite-only-playtest.md) | Closed world, allowlist, revoke, wind-down | Uses reducers verified in the starter |
| [add-a-feature.md](add-a-feature.md) | The end-to-end loop an agent should follow for any new feature | Process |

The Rust code lives in `snippets/*.rs`, so it can be compiled. To check it, append the snippets to a scratch
copy of the starter module (the `view, ViewContext` imports are needed) and run `cargo build --target wasm32-unknown-unknown`.
See `docs/VERIFICATION.md` (2026-10-31, recipes).
