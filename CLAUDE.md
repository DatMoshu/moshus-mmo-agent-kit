# CLAUDE.md

Read **`AGENTS.md`** first. It is the contract for this repo: version lock, hard rules,
definition of done, and routing.

## Claude Code specifics

* Subagents: `python tools/kit.py install-claude` copies `agents/*.md` into `.claude/agents/`
  and the kit skills into `.claude/skills/`. Both are regenerated, so edit the originals.
* Model hints: roles marked `model: opus` (stdb-architect, security-auditor,
  sharding-specialist) do the deep reasoning. Delegate routine module, client, and test work to
  the others.
* Before editing module code, open the matching skill (`skills/<name>/SKILL.md`) and the
  relevant rules file. Before trusting a remembered API, check `skills/vendor/official/`.
* Run the definition-of-done commands yourself. If a command is unavailable (no Godot, no
  server running), say so instead of assuming it passed.
* Never commit secrets, server addresses, or tokens. Never paste licensed game content or
  GPL code.
