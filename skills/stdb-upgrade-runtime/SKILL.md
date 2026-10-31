---
name: stdb-upgrade-runtime
description: Upgrade the pinned SpacetimeDB version (CLI, server, crate, SDKs) with a side-by-side rehearsal and a rollback. Use when a new SpacetimeDB release lands or a bug fix is needed.
---

# Upgrading SpacetimeDB

Follow `docs/processes/version-bump.md` for the kit itself. For a live world:

1. **Read the release notes** and merged PRs for every version you skip. Sort the changes into breaking, behaviour,
   performance and features. Recent examples:
   - 2.12 rejects HS256 JWTs.
   - 2.13 makes HTTP reducer calls wait for durability, so a 504 is an unknown outcome. It also raises Rust MSRV to 1.97.
   - 2.14 adds async inter-database calls and changes `is_internal` semantics: **upgrade the server before the
     modules**. It also deprecates `ctx.identity()`.
2. **Install side by side.** Install the new version without replacing the old one. With the installer, use
   `spacetime version install X` / `spacetime version use X`. Or unpack the release archive into its own folder and
   point `SPACETIME` at it. Never float "latest".
3. **Copy the data.** Stop or snapshot the server and copy its data dir. Never open the only copy with a newer
   binary: on-disk upgrades are one-way.
4. **Rehearse.** Start the candidate on another port against the copy. Bump `stdb.lock`, `Cargo.toml` (`=X`) and
   `package.json`. Build, publish, regenerate bindings, run smoke, run two-identity tests, run a short load test.
5. **Cut over** in a window. Use the same steps against the real data, server first, then modules, then clients.
6. **Keep the rollback.** Keep the old binary and the pre-upgrade data copy until the new version has run cleanly for
   a week.
7. Record the upgrade in `docs/VERIFICATION.md` and the changelog.

## Pins that move together

| Item | Where |
|---|---|
| CLI and server | `stdb.lock [spacetimedb] version` |
| Rust crate | `server/Cargo.toml` `spacetimedb = "=X"` |
| TS SDK | `package.json` `"spacetimedb": "X"` |
| C#/Unity/Unreal SDK | their package manifests |
| Rust toolchain | `rust-toolchain.toml` |
| Godot SDK | `stdb.lock [godot_sdk]` and the vendored addon |
