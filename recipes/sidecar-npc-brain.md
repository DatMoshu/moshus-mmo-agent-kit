# NPC brains in a sidecar

**When to use it:** NPC logic too heavy for the tick budget, such as pathfinding on big maps, planners, or LLM-driven dialogue.
Reducers must be deterministic and fast, and they cannot do network I/O (procedures can make HTTP calls, but they still
run inside the database). A sidecar is an ordinary SpacetimeDB client process that does the thinking and writes
**decisions** back through reducers.

```
module (authority)                       sidecar (operator identity)
  npc table (public or view)   ──subscribe──▶  plan(path / dialogue)
  npc_intent  ◀──────── set_npc_intent(npc_id, target, seq) ──┘
  tick: moves NPCs toward intent, validates everything
```

Rules:

* The sidecar **proposes**; the tick **disposes**. `set_npc_intent` checks `require_operator` (see `operator-role.md`), bounds,
  and that the NPC exists. The tick still enforces speed and collision. A buggy or compromised sidecar can make NPCs
  dumb but never teleport them.
* Make intents idempotent and ordered: add a `seq` and ignore stale ones (`idempotent-requests.md`).
* If the sidecar dies, NPCs keep their last intent or fall back to idle wandering in the tick, so the world keeps running.
* Use the `templates/sidecar` skeleton: connection, reconnect, token file and the guard loop are already there.
  Add your planner next to `guardStep`.

**Status:** pattern only. The operator role and the sidecar loop it relies on are verified, but `set_npc_intent` is not shipped as code.
Skill: `skills/stdb-sidecar`.
