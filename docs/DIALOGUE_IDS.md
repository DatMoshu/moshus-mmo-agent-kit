# Native dialogue IDs in shard clients

`npc_meta.talk` is an opaque unsigned 16-bit native dialogue ID, and
`seed_npcs` takes a vector of those IDs. Zero means no conversation. Preserve
the number unchanged through JSON, seeding, the subscription and `start_talk`.
The width does not establish that a particular era has a live entry.

The Python seeder rejects booleans, floats, strings and values outside 0..65535
before `seed_begin`, plus more than 256 NPCs per map. The native reducer retains
its admin check, parallel-array validation, atomic failure and legacy empty-talk
array (all zeros). Map, slot and authoritative NPC identity are unchanged.

## Generate and verify

Use a disposable archived copy for generation/import so caches stay outside the
source worktree. With the candidate module published to a private test database,
and `KIT_WASM` pointing to its prebuilt wasm:

```
python tools/kit.py bindings --module templates/server/rust-shard --godot-client templates/client/godot-shard --url http://127.0.0.1:3468 --db width-shard
python -B -m unittest discover -s tools/shard -p test_seeder.py
godot --headless --path templates/client/godot-shard --script res://tests/dialogue_schema_check.gd
```

The optional `--godot-client` chooses the Godot output project. Without it the
existing default client remains unchanged. TS outputs follow the selected module;
generate in staging and keep stock single-module clients paired with rust-single.
Unity and Unreal also remain paired with rust-single; generate extra shard
language probes privately rather than replacing those stock schemas.

`tests/dialogue_live_check.gd` takes user arguments URL DB WORLD PROFILE and
checks subscription, exact IDs, synthetic dispatch and HUD. Its made-up world
uses slots 0..7 with talk [0,15,255,256,319,1025,1430,65535]. Optional
`--reconnect`, `--denied` and `--mismatch` exercise the corresponding gates.
`tests/dialogue_session_check.gd` takes URL DB PROFILE and optional `--move` for
persisted identity/position checks. No retail dialogue belongs in these fixtures.

`tests/dialogue_connect_check.gd` runs deterministic delayed/out-of-order HTTP
completion checks against NetSession. Each attempt binds its own endpoint,
profile and options to a monotonic generation; superseding calls, failures,
`Net.disconnect_from_server()` and teardown invalidate/dispose pending HTTP.
Use the Net cancellation method rather than disconnecting the SDK directly,
including before a socket exists. HTTP requests have a 10-second timeout and 4 MiB
body limit; transport/status failures are rejected before parsing JSON.

## Paired adoption and saves

NetSession checks the public version-10 schema before opening its BSATN socket.
Both `npc_meta.talk` and `seed_npcs.talk` must match the generated scalar/vector
width. A missing, malformed or incompatible schema prevents connection and shows
a HUD error. This is a width compatibility gate, not a complete schema fingerprint
or a replacement for admission/authentication. An old client without this gate
cannot be made safe retroactively: coordinated module/client replacement is
required, and a partially adopted build must not be offered as playable.

Installed SpacetimeDB 2.14.0 refuses this column type change in place and requires
manual migration. No migration is supplied here. Preserve existing saves and
restore only with their matching module/bindings into fresh targets. Existing
save-set module hashes must refuse incompatible loading (mixed-version exit 7).
Never bypass hashes, delete data, reseed restored worlds or overwrite an old save
to force adoption. Candidate kit review and subsequent consumer pin/revendor
review are separate; this change alone authorizes neither canonical adoption nor
story-completion claims.

Provenance: original task1578 implementation against accepted task1577 contract
DIALOGUE-ID-COMPAT (2325611); no reference engine implementation was consulted.

## SDK transport ownership (task1578 R3)

After a schema passes, a separate read-only owner binds the actual SDK transport
to its generation, endpoint, database and profile. A second connect request is
refused immediately while that owner exists, before HTTP or SDK endpoint/token
mutation. A matching queued schema response also rechecks ownership at the SDK
boundary. Refusing a second attempt does not transfer the first transport to it.

The pinned SDK public disconnect API only closes an established socket. It does
not cancel pending initialization. Net cancellation during that interval retains
the old owner, suppresses token writes/session authorization, and closes any late
connected event. Only observed disconnected plus a frame (after SDK flags reset)
releases ownership. An error or 10-second timeout alone never proves the SDK idle:
Net reports a failure/restart outcome and keeps overlap blocked. Teardown also
suppresses late persistence. No SDK internals are patched in the product.

Same endpoint/database/profile can reconnect after that terminal boundary. Because
the SDK retains identity and caches, changing endpoint, database or profile after
an SDK start requires a fresh client process; Net explicitly refuses that change.
This is a conservative integration constraint for consumers, not transparent
multi-shard handoff support. Consumers must review this policy during paired adoption.

`tests/dialogue_transport_check.gd` runs delayed initialization, overlap, token
persistence, cancellation, error/disconnect/timeout and teardown vectors. Its
synthetic client models SDK metadata mutation followed by the connecting guard;
it also invokes the actual unmodified pinned low-level connecting guard with a
fabricated pending flag, returning before any networking. All tokens are made up.
