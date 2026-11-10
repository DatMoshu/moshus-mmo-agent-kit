# Contributing

Start with [AGENTS.md](AGENTS.md), [stdb.lock](stdb.lock), and the [architecture guide](docs/wiki/Architecture.md). Keep a change focused on a reproducible problem. Include the trigger, expected behavior, actual behavior, and the smallest sanitized reproduction in an issue or pull request. For vulnerabilities, follow [SECURITY.md](SECURITY.md).

## Make and validate a change

1. Work on a branch and preserve unrelated work. Use existing template shapes and pinned official API references before introducing another pattern.
2. Keep clients intent-only, authenticate with `ctx.sender()`, guard scheduled reducers, and review every public row for information exposure.
3. Run `python tools/kit.py check` and `python evals/run_evals.py`. These are static checks, not proof of authority or runtime correctness.
4. For a module change, build Wasm, publish locally, regenerate affected client bindings, and run the two-client smoke. For tick, AOI, or hot-table changes, also run the load gate. Follow [testing](docs/wiki/Testing.md) and the full definition of done in AGENTS.md.
5. Report exact commands, versions, platforms, results, and checks you could not run. Add dated evidence rather than extending old verification claims.

For documentation changes, check relative links and code examples against CLI help. Keep [docs/wiki](docs/wiki/Home.md) canonical; publication to GitHub Wiki is a separate maintainer step. For version changes, update `stdb.lock` and follow [version-bump.md](docs/processes/version-bump.md), including generated bindings and migration review.

## Source and licensing

New code must have compatible provenance. Preserve LICENSE, NOTICE, and genuine upstream/human attribution; do not add proprietary game content, private data, credentials, or GPL code. List third-party source, revision, license, and local changes before importing material. Dependencies and version upgrades require the repository's version process.

Use the owner's configured Git identity for owner-directed work; do not append AI co-author or generated-by credits. Do not rewrite existing history as part of a normal contribution. Describe behavior and validation in the commit and PR, with limitations made explicit.
