# Module change (AI-assisted or not)

1. Read `AGENTS.md`, `rules/rust-module.md` (or `typescript-module.md`) and the reference template.
2. Plan: list the tables, indexes and reducers you will add or change, who may call each reducer, and whether the
   schema change is additive. Destructive? Stop and follow `skills/stdb-migration`.
3. Write the code. Game rules go in plain functions.
4. `python tools/kit.py check`: fix every finding.
5. Build (`cargo build --target wasm32-unknown-unknown --release` or `npm run build`) and run unit tests.
6. `python tools/kit.py publish` to a local server.
7. `python tools/kit.py bindings`, then commit the regenerated bindings.
8. `python tools/kit.py smoke`. For tick/AOI changes also `python tools/kit.py loadtest`.
9. Open the change for review with the evidence from steps 4-8 (`rules/review-gates.md`).
