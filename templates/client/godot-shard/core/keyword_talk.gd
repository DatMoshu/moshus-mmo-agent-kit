## KeywordTalk: a game-neutral Conversation. Topics are matched on the first 4 letters of the typed word
## (the classic keyword model); "BYE" (or an empty line) ends it. Any adapter can build one from a
## Dictionary, e.g. DocSource from a world document's "client.dialogue" section:
##   {"look": "a tired innkeeper", "NAME": "I am Bram.", "JOB": "I keep the inn.", "BYE": "Safe roads."}
class_name KeywordTalk
extends Conversation

var topics := {} # 4-letter upper-case key -> answer
var look := "someone"
var bye := "Farewell."


static func from_dict(d: Dictionary) -> KeywordTalk:
	var t := KeywordTalk.new()
	for k in d:
		var key := String(k).to_upper()
		if key == "LOOK":
			t.look = String(d[k])
		elif key == "BYE":
			t.bye = String(d[k])
		else:
			t.topics[key.left(4)] = String(d[k])
	return t


func open() -> String:
	title = "Conversation"
	var keys: Array = topics.keys()
	return "You meet %s.\n\n(Ask about %s; BYE ends it.)" % [look, ", ".join(keys)]


func reply(text: String) -> String:
	var w := text.strip_edges().to_upper()
	if w == "" or w.begins_with("BYE"):
		done = true
		return bye
	if w.left(4) == "NAME":
		title = String(topics.get("NAME", title))
	return String(topics.get(w.left(4), "That I cannot help thee with."))
