# Rules

Rules are non-negotiable. Skills explain how to do things; rules say what must always be true. Break one and the
change is rejected in review.

| File | Applies to |
|---|---|
| `rust-module.md` | Rust server modules (`templates/server/rust-single`, `templates/server/rust-sharded`, your `server/`) |
| `typescript-module.md` | TypeScript server modules (`templates/server/ts-single`) |
| `clients.md` | every client: Godot, Unity, Unreal, web, bots, sidecars |
| `ops-and-data.md` | publishing, migrations, upgrades, backups, secrets |
| `review-gates.md` | what a reviewer (human or agent) checks before merging |
| `hallucinations.json` | machine-checked catalog of wrong or outdated APIs (`python tools/kit.py check`) |

## The hallucination catalog

- Each rule has `id`, `pattern` (Python regex, multiline), `ext` (file suffixes), an optional `path` (regex on the
  repo-relative POSIX path, used to target server code only), `message` and `fix`.
- In `.md` files only fenced code blocks are scanned. Prose and tables can name wrong APIs to teach.
- To suppress a deliberate example in code, put `kit:allow` on the line, or wrap the block in `kit:allow-begin` and
  `kit:allow-end`.
- **Every rule needs a sample.** Add a failing snippet under `evals/hallucinations/samples/` and its id to
  `evals/hallucinations/expected.json`, then run `python evals/run_evals.py`. A rule without a sample is a rule nobody
  knows still works.
