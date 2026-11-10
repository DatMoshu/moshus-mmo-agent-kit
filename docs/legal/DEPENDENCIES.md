# Dependency and redistribution inventory

This is a release-maintenance inventory, not a legal certification. Keep the full
license texts; a package manifest label is not a substitute for its license.

## Material stored in this repository

| Material | License evidence | Maintenance obligation |
|---|---|---|
| Kit code, documentation and authored fixtures | Root [LICENSE](../../LICENSE), Apache-2.0 | Retain license and applicable notices in distributions |
| Official SpacetimeDB skills | [Vendored license](../../skills/vendor/official/LICENSE), [attribution](../../skills/vendor/official/ATTRIBUTION.md) | Preserve upstream attribution; review the pinned source when refreshing |
| Godot SDK, both client copies | [Basic client license](../../templates/client/godot/addons/SpacetimeDB/LICENSE), [shard client license](../../templates/client/godot-shard/addons/SpacetimeDB/LICENSE), MIT | Keep flametime copyright and license, including with modified copies |
| SDK SVG interface icons | Included within each SDK directory under its retained license | Keep their provenance with the SDK |
| Default Godot icon SVGs | [Godot MIT license](GODOT-LICENSE.txt), Godot Engine contributors | Preserve copyright and license; these are upstream icons, not kit-authored artwork |

The standalone SpacetimeDB server is downloaded separately and is not vendored.
Its [version-specific license](https://github.com/clockworklabs/SpacetimeDB/blob/v2.14.0/LICENSE.txt)
must be reviewed separately from the module and client SDK licenses; see
[the licensing guide](LICENSING.md).

## Dependencies installed by the build

The npm lockfiles record the complete resolved package graph, including optional
platform packages. The initial release-readiness inventory found these labels:

| Lockfile | License labels recorded for dependencies |
|---|---|
| `tools/loadtest/bots/package-lock.json` | MIT, ISC, Apache-2.0 |
| `templates/sidecar/package-lock.json` | MIT, ISC, Apache-2.0 |
| `templates/server/ts-single/package-lock.json` | MIT, ISC, Apache-2.0 |
| `templates/client/web-admin/package-lock.json` | MIT, ISC, Apache-2.0, BSD-3-Clause, MPL-2.0 |

The web build's MPL-2.0 entries are Lightning CSS and its optional platform
packages. This does not make the kit itself MPL-2.0. Before distributing build
tools or modified dependencies, inspect the package's actual license and source
availability obligations. Review the resulting browser bundle separately from
the development dependency tree.

Rust lockfiles do not contain license texts. After fetching pinned packages, run
`cargo metadata --locked --format-version 1` in each module and inspect the license
and license-file entries of every dependency; retain notices for the artifacts
you redistribute. A successful compile does not establish license compliance.

## Before each release

1. Regenerate the inventory after any dependency or vendor change.
2. Inspect missing or changed license declarations against the downloaded package.
3. Preserve human authorship, copyright and NOTICE material during history cleanup.
4. Review SVGs, fixtures and example text for third-party content. This kit does not
   grant rights to commercial game maps, dialogue, sprites, music or trademarks.
5. Record the exact revision and unresolved questions in the release evidence.

No dependency source or license text was imported merely to produce this inventory.
