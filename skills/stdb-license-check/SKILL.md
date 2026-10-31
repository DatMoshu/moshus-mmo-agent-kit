---
name: stdb-license-check
description: Check SpacetimeDB BSL limits, kit/asset/dependency licenses and game-IP risks before publishing a game, repo or hosted world. Not legal advice. Use before launch, open-sourcing, or using third-party content.
---

# License check (not legal advice)

Read `docs/legal/LICENSING.md` first. This is a checklist for spotting questions to take to a lawyer or a rights
holder. It does not give answers.

## SpacetimeDB

- [ ] **BSL 1.1:** count your production instances. The grant covers one, and the server can't be offered as a
      database service to third parties.
- [ ] More than one instance, multi-host regions or a hosted platform: use Maincloud or get a commercial license from
      Clockwork Labs.
- [ ] Each version's change date converts it to AGPL v3 with a linking exception. Note the date for your pinned
      version.
- [ ] Client SDKs and the official skills have their own licenses (many are Apache-2.0). Keep their LICENSE and NOTICE
      files.

## Your repo

- [ ] Your game code license is chosen and in `LICENSE`.
- [ ] Vendored code keeps its license file and attribution (`NOTICE`, `skills/vendor/official/ATTRIBUTION.md`).
- [ ] No GPL or AGPL code is copied into code you will ship under another license unless you comply.
- [ ] Dependency licenses are scanned (`cargo deny check licenses`, `npx license-checker --summary`).

## Content and IP

- [ ] No assets, maps, text, names or music from commercial games unless licensed. "Fan remake" and "free" are not
      defenses.
- [ ] Engine reimplementations that load the player's own legally owned game files are a different risk profile from
      shipping the content. Get advice.
- [ ] Trademarks: don't use another game's name in your title or store page.
- [ ] Asset store and AI-generated assets: check each license's terms on redistribution and commercial use.

## Exit

List each open question with an owner. Launch blockers are: the BSL instance count, unlicensed content, and GPL
contamination.
