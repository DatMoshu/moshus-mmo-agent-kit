# Server and client templates

Choose a schema before a renderer. Movement, global/region, and tile-world modules are distinct families. Generated bindings belong to a particular schema, not the kit as a whole.

| Server | Client/harness | Intended use |
|---|---|---|
| [rust-single](../../templates/server/rust-single) | godot, web-admin, bots; Unity/Unreal starters | Minimal authoritative movement |
| [ts-single](../../templates/server/ts-single) | Movement-schema clients | TypeScript server alternative |
| [rust-sharded](../../templates/server/rust-sharded) | Its client-example and region-hop recipe | Registry and regional ownership |
| [rust-shard](../../templates/server/rust-shard) | godot-shard and Meadowmere fixture | Tile world and game adapters |

## Evidence is scoped

The [verification log](../VERIFICATION.md) records dated local results for movement, TypeScript, handoff, sidecar census, web-admin, Godot, and the tile fixture. Unity session logic was checked headlessly with .NET; its editor was not exercised. Unreal bindings were generated/reviewed, but the starter was not compiled. Historical Linux proof is stronger than Windows source-build proof; macOS is unverified in that ledger. Modified templates need fresh evidence.

## Client boundaries

The [Godot movement client](../../templates/client/godot) wraps the community SDK behind a network seam. Import before codegen on a fresh clone so engine global-class caches exist. Run two instances to inspect manual movement, or use headless smoke for independent-observer proof.

The [web-admin](../../templates/client/web-admin) is an operations UI. A client label grants no authority: the server validates the operator identity. The [sidecar](../../templates/sidecar) moves I/O/heavy work outside deterministic reducers. Protect privileged sidecar identities as operator credentials.

The [Godot tile client](../../templates/client/godot-shard) separates TileSource, rendering, network, UI, and game hooks. A world document supplies server collision/entity data; adapters supply presentation. Follow [SHARD_CORE.md](../SHARD_CORE.md) instead of substituting movement bindings.

## Updating templates

Read local README/source, build the selected server, regenerate affected bindings, and exercise the actual changed client. Generic `kit.py bindings` targets configured movement clients; inspect `--help` and local codegen instructions for alternatives. Successful TypeScript smoke cannot validate Unity, Unreal, or tile UI behavior.
