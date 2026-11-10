# Version upgrades

Follow the detailed [version-bump process](../processes/version-bump.md). [stdb.lock](../../stdb.lock) coordinates CLI/server/module/SDK versions. Rust and Godot are pinned separately in applicable files. Do not float one SDK and assume protocol compatibility.

## Prepare and change together

Record the passing revision/tool versions and read the target release's primary migration notes. Search module/npm manifests and lockfiles, SDK references, bindings, examples, and CI for old pins. Keep rollback tooling and identify consumers that must deliberately adopt the change.

Update the central lock and dependent manifests/lockfiles together. Refresh official skills at an explicit upstream revision and inspect every diff: the vendor command can fetch moving content. Preserve source/license records. Documentation refresh alone cannot validate a runtime.

Regenerate all affected client/receiver bindings, including cross-database bindings. Build and publish receivers before senders where required. Follow sharded-template instructions for self-call codegen passes.

## Prove compatibility

Run doctor, scans/evals, Wasm builds, publish, binding checks, two-client smoke, and relevant load gates. Exercise reconnect with existing identities, additive initialization, and migrations. Test actual engine clients when SDK/bindings change; report editor and runtime coverage separately.

Additive publish does not rerun init. The reference uses idempotent ensure_world for singleton/schedule creation and versioned backfill hooks. A schema constant is not a migration by itself. Follow the [migration skill](../../skills/stdb-migration/SKILL.md). Wiping dev data is not a production migration strategy.

Record date, platform, versions, commands, results, and gaps. Recheck the target license and production topology. A prior-pin PASS cannot validate the upgrade.

## Vendored core and local overlays

Use [vendor_core.py](../../tools/shard/vendor_core.py) and its manifest/hash model when copying the tile core into a game. Record the exact kit revision and copied-file hashes. Keep local overlay files or patches explicitly listed, with their purpose and base revision; compare normalized hashes to detect unexpected edits rather than trusting a package-version label. Reapply/review overlays after an upstream update and test the composed result. A clean upstream manifest does not validate a locally patched consumer, and a consumer's acceptance does not qualify a new kit extraction.
