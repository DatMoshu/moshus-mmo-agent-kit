# KIT-006: Agent-runtime neutral

- Status: accepted
- Date: 2026-10-30

## Context
People use Claude Code, Codex, Cursor and other agent runtimes. The official SpacetimeDB skills are plain Markdown.

## Decision
Agents and skills are plain Markdown with YAML front matter. `AGENTS.md` is the entry point; `CLAUDE.md` points to it; `tools/kit.py install-claude` copies them into `.claude/`. Official skills are vendored unmodified, not forked.

## Consequences
No runtime-specific features are required. Runtime-specific conveniences are optional installers.
