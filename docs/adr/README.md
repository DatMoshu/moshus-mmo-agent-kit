# Architecture decision records

Record each significant choice: topology, auth, AOI scheme, sharding, client engine, hosting, licensing.
Copy `TEMPLATE.md` to `NNNN-short-title.md`. Status moves from proposed to accepted to superseded (link the
replacement). Never delete an ADR.

The `KIT-*` records below are the decisions behind this kit itself. Your game's ADRs start at `0001`.

| ADR | Title | Status |
|---|---|---|
| [KIT-001](KIT-001-single-module-default.md) | Default topology is a single module | accepted |
| [KIT-002](KIT-002-rust-reference-language.md) | Rust is the reference module language | accepted |
| [KIT-003](KIT-003-client-agnostic-godot-first.md) | Client-agnostic, Godot and web first | accepted |
| [KIT-004](KIT-004-licensing.md) | Kit licensing and what may be copied | accepted |
| [KIT-005](KIT-005-pinned-versions.md) | One pinned versions file | accepted |
| [KIT-006](KIT-006-agent-runtime-neutral.md) | Agent-runtime neutral | accepted |
