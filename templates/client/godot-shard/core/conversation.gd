## Conversation: one NPC dialogue session, driven by typed keywords (the classic "talk" model).
## The core UI (ui/hud.gd) only calls these; a game adapter subclasses it with its own rules and data
## (or a game's own, e.g. a reader for the player's own dialogue files). Nothing here is sent to the server.
class_name Conversation
extends RefCounted

var title := ""   # shown above the talk panel (e.g. the NPC's name once known)
var done := false # true once the NPC ended the conversation (panel closes after the last line)


## First line(s) when the conversation opens.
func open() -> String:
	return ""


## The NPC's answer to one typed line.
func reply(_text: String) -> String:
	done = true
	return ""
