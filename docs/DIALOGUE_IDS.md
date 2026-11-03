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
