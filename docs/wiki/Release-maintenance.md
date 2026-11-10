# Release maintenance and wiki synchronization

Prepare a concrete candidate before publication: one revision, reproducible commands, explicit gaps, and a maintainer decision about distribution.

## Candidate review

1. Audit tracked files/history for private paths, secrets, proprietary content and attribution without printing sensitive values. Preserve unrelated work and original history.
2. Check LICENSE, NOTICE, vendored source/license records, pins, and the pinned server's production terms. State uncertainties.
3. Run a clean-checkout source build and two-client smoke with isolated endpoint/data/config. Record OS, versions, duration and setup exclusions.
4. Run applicable static, binding, feature, engine and load checks. Include skipped checks. Review README claims against logs.
5. Check local links and render Markdown/Mermaid in the intended host. Source inspection alone is not visual-render proof.
6. Review diff/SHA. Public publishing, releases, wiki writes and destructive history replacement need an explicit owner decision. Keep prepared history separate, with old/new SHA mapping and consumer impact.

## Optional GitHub Wiki

Pages in [this directory](Home.md) are canonical and usable from a clone. GitHub Wiki is a separate Git repository; see [GitHub's documentation](https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages). Do not independently edit the published copy and then overwrite it from an older source checkout.

After publication approval and selection of the final repository URL:

1. Enable/initialize the Wiki if needed; clone its `.wiki.git` repo into separate staging. Never generate wiki output over the source worktree.
2. Copy only `docs/wiki/*.md`, retaining page basenames, Home.md and _Sidebar.md. Add a header naming the source SHA and canonical URL.
3. Rewrite staged page links such as `Installation.md` to wiki routes such as `Installation`. Rewrite links leaving this directory to absolute source URLs pinned to the approved SHA. Preserve anchors. Process the sidebar too; do not change canonical files.
4. Inspect every URL, fence, table and Mermaid diagram in preview. Source directories need the host's directory route. Provide a link back to canonical docs.
5. Review the diff, commit with the maintainer identity, and push only after approval. Record source SHA/wiki commit together. Review removed pages explicitly; do not delete unrelated wiki content.

Mappings: `Testing.md` → `Testing`; `../../README.md` → the approved repository's `blob/<source-sha>/README.md`; `../../templates/server/rust-single` → `tree/<source-sha>/templates/server/rust-single`. Owner/slug must be real before generating URLs. These instructions perform no sync or publication.

## Design references

Organization is informed by [Bevy's README](https://github.com/bevyengine/bevy/blob/main/README.md): brief purpose, first example, deeper links, and explicit limitations. [SpacetimeDB's repository](https://github.com/clockworklabs/SpacetimeDB) supplies the relevant runtime/SDK/example separation. [GitHub's wiki guide](https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages) establishes the separate-repository workflow. These are organizational references; no code/artwork was imported.
