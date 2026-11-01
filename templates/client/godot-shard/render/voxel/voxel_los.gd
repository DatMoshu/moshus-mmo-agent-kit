## Presentation-only line of sight (no gameplay effect): Bresenham rays from the focus tile to every tile within
## `radius`; a tile is visible when no OPAQUE tile (voxel table `opaque`) lies strictly between.
## Used only when MapViewState.visibility is null (no server LOS yet).
class_name VoxelLos
extends RefCounted


static func compute(tiles: TileSource, prof: VoxelProfiles, map_id: int, origin: Vector2i, radius: int, wrap: bool) -> PackedByteArray:
	var side := radius * 2 + 1
	var out := PackedByteArray()
	out.resize(side * side)
	var size := tiles.map_size(map_id)
	if size == Vector2i.ZERO:
		out.fill(255)
		return out
	var opaque := PackedByteArray()
	opaque.resize(side * side)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := origin.x + dx
			var y := origin.y + dy
			if wrap:
				x = posmod(x, size.x); y = posmod(y, size.y)
			var t := tiles.tile_at(map_id, x, y)
			opaque[(dy + radius) * side + dx + radius] = prof.opaque_tile[t] if t >= 0 else 0
	var r2 := radius * radius + radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			out[(dy + radius) * side + dx + radius] = 255 if _clear(opaque, side, radius, dx, dy) else 0
	return out


static func _clear(opaque: PackedByteArray, side: int, r: int, tx: int, ty: int) -> bool:
	var x := 0
	var y := 0
	var ax := absi(tx)
	var ay := absi(ty)
	var sx := 1 if tx > 0 else -1
	var sy := 1 if ty > 0 else -1
	var err := ax - ay
	while true:
		if x == tx and y == ty:
			return true
		if (x != 0 or y != 0) and opaque[(y + r) * side + x + r]:
			return false
		var e2 := err * 2
		if e2 > -ay:
			err -= ay; x += sx
		if e2 < ax:
			err += ax; y += sy
	return true
