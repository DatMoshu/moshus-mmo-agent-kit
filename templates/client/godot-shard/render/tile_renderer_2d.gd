## TileRenderer2D: the classic top-down tile view (one 16 px tile per map cell, scaled).
class_name TileRenderer2D
extends MapRenderer

const SCALE := 2.0 # screen px per tile px

var _canvas := Node2D.new()
var _state: MapViewState


func _ready() -> void:
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)


func set_active(on: bool) -> void:
	_canvas.visible = on


func describe() -> String:
	return "2D tiles"


func render(state: MapViewState) -> void:
	_state = state
	last_state = state
	_canvas.queue_redraw()


func refresh_atlas() -> void:
	_canvas.queue_redraw()


func set_screen_offset(px: Vector2) -> void:
	screen_offset = px
	_canvas.position = px.round()
	_canvas.queue_redraw()


func _tpx() -> float:
	return TileSource.TILE_PX * SCALE


func world_to_screen(tile: Vector2, height := 0.0) -> Vector2:
	if _state == null or not _canvas.is_inside_tree():
		return Vector2(NAN, NAN)
	var local := _canvas.get_viewport_rect().size / 2.0 + (tile - _state.focus) * _tpx() + Vector2(0, (0.5 - height) * _tpx())
	return _canvas.get_global_transform_with_canvas() * local


func screen_to_world(screen: Vector2) -> Vector2:
	if _state == null or not _canvas.is_inside_tree():
		return Vector2(NAN, NAN)
	var local := _canvas.get_global_transform_with_canvas().affine_inverse() * screen
	return _state.focus + (local - _canvas.get_viewport_rect().size / 2.0) / _tpx()


func _on_draw() -> void:
	if _state == null:
		return
	var c := _canvas
	var view := c.get_viewport_rect().size
	var center := view / 2.0
	var origin := _state.focus
	var tpx := TileSource.TILE_PX * SCALE
	var tex := tiles.view_atlas() if tiles else null
	var sz := Vector2(tpx, tpx)
	if tex and _state.map_id >= 0:
		# Tiles covering the visible rect in canvas-local space: the canvas is shifted by screen_offset, so the
		# visible area is (-offset .. view - offset); one tile of margin on every side.
		var off := _canvas.position
		var lo := origin + (-off - center) / tpx
		var hi := origin + (view - off - center) / tpx
		for ty in range(floori(lo.y) - 1, ceili(hi.y) + 2):
			for tx in range(floori(lo.x) - 1, ceili(hi.x) + 2):
				var tile := tiles.tile_at(_state.map_id, tx, ty)
				if tile >= 0:
					c.draw_texture_rect_region(tex, Rect2(center + (Vector2(tx, ty) - origin) * tpx, sz), tiles.view_tile_rect(tile))
	for it in _state.items:
		var p: Vector2 = center + (it["pos"] - origin) * tpx - sz / 2.0
		if tex:
			c.draw_texture_rect_region(tex, Rect2(p + sz * 0.2, sz * 0.6), tiles.view_tile_rect(it["tile"]))
		else:
			c.draw_rect(Rect2(p + sz * 0.3, sz * 0.4), Color.YELLOW)
	for n in _state.npcs:
		if n["tile"] == 0:
			continue
		var p: Vector2 = center + (n["pos"] - origin) * tpx - sz / 2.0
		if tex:
			c.draw_texture_rect_region(tex, Rect2(p, sz), tiles.view_tile_rect(n["tile"]))
		else:
			c.draw_rect(Rect2(p, sz), Color.ORANGE)
	for m in _state.monsters:
		var p: Vector2 = center + (m["pos"] - origin) * tpx - sz / 2.0
		if tex:
			c.draw_texture_rect_region(tex, Rect2(p, sz), tiles.view_tile_rect(_frame(m["tile"])))
		else:
			c.draw_rect(Rect2(p, sz), Color.RED)
		if m["id"] == _state.target_id:
			c.draw_rect(Rect2(p, sz), Color.RED, false, 2.0)
		if not external_tags:
			_hp_bar(p + Vector2(0, -6), tpx, m["hp"], m["max_hp"])
	for e in _state.entities:
		var p: Vector2 = center + (e["pos"] - origin) * tpx
		var color := Color.GOLD if e["is_me"] else Color.SKY_BLUE
		if tex:
			c.draw_texture_rect_region(tex, Rect2(p - sz / 2.0, sz), tiles.view_tile_rect(tiles.player_tile))
			c.draw_rect(Rect2(p - sz / 2.0, sz), color, false, 2.0)
		else:
			c.draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), color)
		if external_tags:
			continue
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(e["name"]).x
		c.draw_string_outline(font, p + Vector2(-w / 2.0, -tpx / 2.0 - 10), e["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		c.draw_string(font, p + Vector2(-w / 2.0, -tpx / 2.0 - 10), e["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		if int(e.get("max_hp", 0)) > 0:
			_hp_bar(p + Vector2(-tpx / 2.0, -tpx / 2.0 - 6), tpx, e["hp"], e["max_hp"])


func _hp_bar(at: Vector2, w: float, hp: int, max_hp: int) -> void:
	if max_hp <= 0:
		return
	var f := clampf(float(hp) / max_hp, 0.0, 1.0)
	_canvas.draw_rect(Rect2(at, Vector2(w, 4)), Color(0, 0, 0, 0.7))
	_canvas.draw_rect(Rect2(at, Vector2(w * f, 4)), Color.LIME_GREEN if f > 0.5 else (Color.ORANGE if f > 0.25 else Color.RED))


## Monster tiles come in 2-frame pairs (even/odd) in the published tile list: alternate twice a second.
func _frame(t: int) -> int:
	return (t & ~1) + (int(Time.get_ticks_msec() / 500) & 1) if t >= 128 else t
