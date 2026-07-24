class_name BriefText
extends RefCounted
## Loads a level's authored FLIGHT PLAN prose from res://assets/briefs/<locale>/
## <stem>.md and renders a tiny markdown subset (**bold**, *italic*) as BBCode.
## Long-form brief prose lives in per-locale files (not the PO catalog); the
## current locale is tried first, then its language subtag, then English.

static var _cache: Dictionary[String, String] = {}


## The raw brief text for a level (already locale-resolved), or "" if none is
## authored yet. Feed the result through md_to_bbcode() for a RichTextLabel.
static func flight_plan(level_index: int) -> String:
	var stem := Campaign.brief_id(level_index)
	var locale := TranslationServer.get_locale()
	var key := "%s/%s" % [locale, stem]
	if _cache.has(key):
		return _cache[key]
	var text := ""
	for loc: String in [locale, locale.split("_")[0], "en"]:
		var path := "res://assets/briefs/%s/%s.md" % [loc, stem]
		if FileAccess.file_exists(path):
			text = FileAccess.open(path, FileAccess.READ).get_as_text().strip_edges()
			break
	_cache[key] = text
	return text


## Convert the supported markdown subset to BBCode for a RichTextLabel: escape
## stray '[' so authored brackets can't inject tags, then **bold** and *italic*
## (bold first, so a '**' pair isn't mis-read as two single '*').
static func md_to_bbcode(text: String) -> String:
	if text.is_empty():
		return ""
	text = text.replace("[", "[lb]")
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	text = bold.sub(text, "[b]$1[/b]", true)
	var italic := RegEx.create_from_string("\\*(.+?)\\*")
	text = italic.sub(text, "[i]$1[/i]", true)
	return text
