# Version bump (adopting a new SpacetimeDB release)

Never float to "latest". A bump is a small project with its own evidence.

1. **Read** the release notes and the linked PRs for every version between the pinned one and the target. Classify
   each change: breaking, behavior change, performance, new feature, security. Note runtime-before-module ordering
   requirements (2.14 requires upgrading the server before publishing modules built with the new crate).
2. **Matrix.** Write down the target CLI, server, module crate, each client SDK (TS npm, C#, Unreal, Godot community
   SDK) and toolchain (Rust MSRV; for example 2.13 raised it to 1.97). Any SDK that has no matching release yet blocks
   the bump for that client.
3. **Install side by side.** Put the new CLI and server in a separate directory. Don't replace the working one.
4. **Copy the data.** Run the new server against a *copy* of the data directory on a different port.
5. **Update pins** in a branch: `stdb.lock`, `Cargo.toml` (`=x.y.z`), `package.json`, `rust-toolchain.toml`, and SDK
   versions. Run `python tools/kit.py doctor`.
6. **Rebuild and regenerate**: build modules, regenerate bindings for every client, run `python tools/kit.py check`.
   Update `rules/hallucinations.json` for any renamed or deprecated API, with a sample in `evals/`.
7. **Evidence**: smoke with two identities, persistence across a server restart, reconnect with saved tokens, a
   load gate at your current rung, and every client that ships.
8. **Rollback plan**: the old binaries and data copy stay in place until the new version has run in production for
   a week.
9. **Record**: a dated entry in `docs/VERIFICATION.md` and an ADR if behavior changed. Then merge.
10. **Production order**: back up, upgrade the server, verify the existing module still runs, then publish the
    rebuilt module, then ship clients.
