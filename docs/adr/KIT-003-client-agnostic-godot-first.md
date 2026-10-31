# KIT-003: Client-agnostic, Godot and web first

- Status: accepted
- Date: 2026-10-30

## Context
Godot is open source and quick to iterate with. The web is the easiest way to try a game and to build admin tools. Unity and Unreal have official SDKs.

## Decision
Provide full Godot (community GDScript SDK, MIT, vendored and pinned) and web (official TS SDK) starters first. Unity and Unreal get thin starters that follow the official SDKs. Every client goes through one adapter (`rules/clients.md`).

## Consequences
Godot relies on a community SDK that may lag releases; `stdb.lock` pins it, and the version-bump process checks it.
