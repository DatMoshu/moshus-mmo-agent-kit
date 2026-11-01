## Hud: the game-agnostic on-screen UI shared by every renderer (it is a CanvasLayer above both the
## 2D canvas and the 3D viewport). Shows stats, inventory, chat, the NPC talk panel, short action
## messages and the controls help. It never talks to the server: main.gd feeds it with update() and
## reacts to its signals.
## A game swaps in its own HUD with main.set_hud(MyHud.new()) from Game.extend: MyHud extends Hud, overrides every
## method in FACADE (main calls only these, and listens to the three signals), and skips super._ready() so the
## default widgets are never built. update(d) receives the keys listed at update() below.
class_name Hud
extends CanvasLayer

## The methods main.gd calls on its HUD (a replacement overrides all of them).
const FACADE := ["is_typing", "open_chat", "close_inputs", "toggle_help", "toast", "show_talk", "end_talk",
	"talk_text", "update"]

signal chat_submitted(text: String)
signal talk_submitted(text: String)
signal talk_closed

const HELP := """Controls
  WASD / arrow keys   move
  F                   attack the nearest adjacent monster
  G                   pick up gold / items next to you
  H                   drink a healing potion
  T                   talk to the nearest adjacent townsperson
  Enter               chat (Enter sends, Esc cancels)
  Tab / F3            switch 2D / 3D view
  F4 / Shift+F4       next / previous tileset (art pack)
  \\ F5..F12, [ ]     3D view toggles and camera pitch (listed on the status line)
  F1                  show / hide this help
Walk off a town's edge to leave it; step on a moongate to travel."""

var _status := Label.new()
var _inv := Label.new()
var _chat_log := Label.new()
var _chat_in := LineEdit.new()
var _toast := Label.new()
var _toast_until := 0
var _help := Label.new()
var _talk_panel := PanelContainer.new()
var _talk_title := Label.new()
var _talk_text := Label.new()
var _talk_in := LineEdit.new()


func _ready() -> void:
	layer = 10
	for l in [_status, _inv, _chat_log, _toast, _help, _talk_title, _talk_text]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_font_size_override("font_size", 16)
	_status.position = Vector2(10, 8)
	add_child(_status)
	_inv.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inv.position = Vector2(-230, 8)
	_inv.size = Vector2(220, 200)
	_inv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_inv)
	_chat_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_log.position = Vector2(10, -230)
	_chat_log.size = Vector2(620, 180)
	_chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_chat_log)
	_chat_in.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_in.position = Vector2(10, -44)
	_chat_in.size = Vector2(620, 32)
	_chat_in.placeholder_text = "say something (Enter to send, Esc to cancel)"
	_chat_in.max_length = 200
	_chat_in.visible = false
	_chat_in.text_submitted.connect(_on_chat)
	add_child(_chat_in)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 60)
	_toast.size = Vector2(600, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	add_child(_toast)
	_help.text = HELP
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.position = Vector2(-260, -150)
	_help.add_theme_font_size_override("font_size", 18)
	_help.visible = false
	add_child(_help)
	# Talk panel (bottom centre).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.12, 0.88)
	sb.border_color = Color(0.7, 0.6, 0.3)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	_talk_panel.add_theme_stylebox_override("panel", sb)
	_talk_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_talk_panel.position = Vector2(-330, -300)
	_talk_panel.custom_minimum_size = Vector2(660, 0)
	var box := VBoxContainer.new()
	_talk_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_talk_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk_text.custom_minimum_size = Vector2(630, 120)
	_talk_in.placeholder_text = "your words (BYE or Esc to leave)"
	_talk_in.text_submitted.connect(func(t: String): _talk_in.clear(); talk_submitted.emit(t))
	box.add_child(_talk_title)
	box.add_child(_talk_text)
	box.add_child(_talk_in)
	_talk_panel.add_child(box)
	_talk_panel.visible = false
	add_child(_talk_panel)


## True while a text field has the keyboard (gameplay keys are ignored then).
func is_typing() -> bool:
	return _chat_in.has_focus() or _talk_in.has_focus()


func open_chat() -> void:
	_chat_in.visible = true
	_chat_in.grab_focus()


func close_inputs() -> void:
	_chat_in.release_focus()
	_chat_in.visible = false
	if _talk_panel.visible:
		end_talk()


func _on_chat(text: String) -> void:
	_chat_in.clear()
	_chat_in.release_focus()
	_chat_in.visible = false
	if text.strip_edges() != "":
		chat_submitted.emit(text.strip_edges())


func toggle_help() -> void:
	_help.visible = not _help.visible


func toast(text: String, seconds: float = 2.5) -> void:
	_toast.text = text
	_toast_until = Time.get_ticks_msec() + int(seconds * 1000)


func show_talk(title: String, text: String, focus: bool = true) -> void:
	_talk_panel.visible = true
	_talk_title.text = title
	_talk_text.text = text
	if focus:
		_talk_in.grab_focus()


func end_talk() -> void:
	_talk_panel.visible = false
	_talk_in.release_focus()
	talk_closed.emit()


func talk_text() -> String:
	return _talk_text.text if _talk_panel.visible else ""


## d: {name, hp, max_hp, level, xp, gold, kills, deaths, map, renderer, tileset, inventory: [[name, qty]],
##     chat: [[name, text, here]]}
func update(d: Dictionary) -> void:
	_status.text = "%s   HP %d/%d   Lv %d   XP %d   Gold %d   Kills %d   Deaths %d\n%s   [%s]   %s   F1 help" % [
		d.get("name", "?"), d.get("hp", 0), d.get("max_hp", 0), d.get("level", 1), d.get("xp", 0),
		d.get("gold", 0), d.get("kills", 0), d.get("deaths", 0), d.get("map", ""), d.get("renderer", ""),
		"F4 " + String(d.get("tileset", "")) if String(d.get("tileset", "")) != "" else ""]
	var hp_f := float(d.get("hp", 0)) / maxf(1.0, float(d.get("max_hp", 1)))
	_status.add_theme_color_override("font_color", Color.WHITE if hp_f > 0.3 else Color(1, 0.5, 0.45))
	var inv := PackedStringArray(["Inventory"])
	for it in d.get("inventory", []):
		inv.append("%s x%d" % [it[0], it[1]])
	if inv.size() == 1:
		inv.append("(empty)")
	_inv.text = "\n".join(inv)
	var lines := PackedStringArray()
	for c in d.get("chat", []):
		lines.append(("%s: %s" if c[2] else "[far] %s: %s") % [c[0], c[1]])
	_chat_log.text = "\n".join(lines)
	_toast.visible = Time.get_ticks_msec() < _toast_until
