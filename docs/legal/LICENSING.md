# Licensing guide for SpacetimeDB games

> **This is not legal advice.** It is a plain-language summary written by developers for developers, to help you ask
> the right questions. Licenses are legal documents. Read the actual texts linked below, and for anything commercial
> or uncertain, talk to a lawyer or to Clockwork Labs. Summaries were checked against the SpacetimeDB 2.14.0
> `LICENSE.txt` on 2026-10-30. Licenses change between versions, so re-check when you bump `stdb.lock`.

## The pieces and their licenses

| Piece | License (2.14.0) | What it means for you, in short |
|---|---|---|
| SpacetimeDB server (standalone, CLI, core) | Business Source License 1.1 with an Additional Use Grant | Production use is allowed with **at most one SpacetimeDB instance in production**, and **not as a Database Service**. Otherwise you need a commercial license. |
| Same, after the Change Date | AGPL v3.0 with a linking exception | Each version converts on its Change Date (2031-10-25 for 2.14.0) or four years after its first public release, whichever is first. |
| Module crate / client SDKs / codegen output | Usually Apache-2.0 (check the `LICENSE` file in each subdirectory of the SpacetimeDB repo) | Your game code that uses them can be under any license. Keep the notices. |
| Official agent skills (`skills/vendor/official`) | Apache-2.0 | Vendored unmodified with LICENSE and attribution in this kit. |
| Godot community SDK (`flametime/Godot-SpacetimeDB-SDK`) | MIT | Keep its LICENSE in `addons/SpacetimeDB`. |
| This kit | see `LICENSE` and `NOTICE` at the kit root | Your game built from it is yours. |
| Your module and client code | your choice | You own it. Generated bindings are part of your code. |

The SpacetimeDB repository's root `LICENSE.txt` describes subdirectory-specific licenses and also contains a
conflict-precedence clause. Read the root and component texts together. That is why SDKs and the module crate can be more permissive than the server. Always check the specific
subdirectory you use.

## Key terms in the Additional Use Grant (paraphrased)

- **"No more than one SpacetimeDB instance in production."** One running server (process/host) serving your
  application. One instance can hold many databases (for example a global database plus region databases on the same
  server), which is also the only setup where 2.14 inter-database communication works.
- **"Database Service"**: a commercial offering that lets third parties (not your employees or contractors) create
  tables whose schemas they control. Hosting *your* game for players is not that. Selling "SpacetimeDB hosting" or
  letting customers upload their own modules would be.
- **Non-production use** (development, testing, staging, CI) is granted without the one-instance limit.

## Common situations

| Situation | Likely fine under the grant? | Notes |
|---|---|---|
| Local development, any number of servers | Yes | Non-production. |
| One self-hosted server running your game, with several databases | Yes | The default topology for this kit up to rung 1,000. |
| Staging plus production servers | Probably | Staging is non-production; confirm if staging serves real players. |
| Two production servers (for example EU and US regions) | **No**, without a commercial license | Talk to Clockwork Labs, or use Maincloud. |
| Using Maincloud (hosted by Clockwork Labs) | Governed by Maincloud's terms | Different terms and pricing; read them. |
| Offering your engine as a platform where creators upload modules | **Risky**: may be a Database Service | Get advice before building this. |
| Forking and modifying the server | Allowed under the BSL | Modified copies stay under the BSL, and the same production limits apply. |

## Content and code from other projects

- **Do not copy GPL code** (for example GPL-licensed game server reimplementations) into a module or client you plan
  to ship under other terms. Read it for ideas only if you're comfortable doing so, and write your own.
- **Do not ship copyrighted game assets or data** (maps, sprites, text, item tables) from commercial games or their
  fan reimplementations without permission. "Inspired by" mechanics is generally different from copied content, but
  that line is a legal question.
- Fonts, music, sound packs and store assets each have their own licenses. Track them in your own `NOTICE`.

## Checklist before you ship

1. List every third-party component and its license in `NOTICE` (the `stdb-license-check` skill automates the scan).
2. Confirm your production topology fits the grant, or get a commercial license, or use Maincloud.
3. Keep LICENSE files of vendored code in place.
4. Re-read the SpacetimeDB `LICENSE.txt` for your pinned version.
5. If anything is unclear, ask a lawyer.

## Sources

- SpacetimeDB license: <https://github.com/clockworklabs/SpacetimeDB/blob/v2.14.0/LICENSE.txt>
- Business Source License FAQ (MariaDB): <https://mariadb.com/bsl-faq-adopting/>
- AGPL v3: <https://www.gnu.org/licenses/agpl-3.0.html>
