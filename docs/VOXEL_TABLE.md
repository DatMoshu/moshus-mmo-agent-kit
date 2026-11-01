# Voxel table format (3D view)

`VoxelRenderer3D` voxelizes each tile's 16x16 atlas pixels at run time into height columns. The **voxel
table** says how: tile id -> category -> height profile. A game supplies it through
`TileSource.voxel_table()` (a world document's `client.voxel`, or a TileSource override); an empty table
means the generic `client/render/voxel/tile_profiles.json` (flat ground, ids 64+ low props).

Atlas pixels are matched to the 16-colour EGA palette (`client/render/palette.gd`; nearest colour when
not exact). Pixel rules below key on that palette index.

```json
{
  "categories": {
    "<name>": {
      "base": 0,            // height in 1/16 tile above grass level (negative = sunk: water, floors)
      "ground": "#rrggbb",  // colour for palette index 0 (black, the tile background)
      "side": "#rrggbb",    // side faces (default: ground darkened)
      "opaque": false,      // blocks line of sight (LOS toggle)
      "water": false, "glow": false,
      "black_water": -3,    // optional: black pixels become water at this height (bridges)
      "bevel": [2, 1], "bevel_strong": [3, 2, 1],   // subtracted at d px from a lower neighbour
      "terrace": {"step": 2, "every": 3, "max": 8}, "round": 5,
      "vary": {"h": 1, "c": 0.07},                  // per-clump height / colour jitter ("vary" option)
      "pixels": {"<palette index>|*": {"dh": 3} | {"canopy": [bottom, top]} | {"colour": "#..", "keep": false}}
    }
  },
  "tiles": [[first_id, last_id, "<category>"], ...],   // unlisted ids use "prop" (or the first category)
  "walk": {"categories": {"<name>": true}, "tiles": {"<id>": false}},  // client pathing fallback
  "sprites": {"pairs": [[first, last], ...], "avatar": 31}  // 2-frame billboard animation ranges; hero id
}
```
