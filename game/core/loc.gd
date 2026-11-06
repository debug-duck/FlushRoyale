extends Node
## Autoload "Loc": text localisation. The English string is the key (gettext style), so code and data keep readable text;
## `Loc.t("TRY AGAIN")` returns the active language's entry from data/i18n/<lang>.json, or the English text when it has none.
## Language: Android follows the phone's system language (when a file for it exists); every other platform stays English.

const DIR := "res://data/i18n/"
const DEFAULT := "en"

var lang := DEFAULT
var _table: Dictionary = {}

func _ready() -> void:
	set_language(system_language())

## Languages that ship a strings file (data/i18n/<code>.json).
func available() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		var n := f.trim_suffix(".remap")
		if n.ends_with(".json"):
			out.append(n.get_basename())
	return out

## Android: the device language (e.g. "de" from de-DE), if supported. Desktop/editor: always English.
func system_language() -> String:
	if not OS.has_feature("android"):
		return DEFAULT
	var code := OS.get_locale_language()
	return code if code in available() else DEFAULT

func set_language(code: String) -> void:
	lang = code
	_table = {}
	if code == DEFAULT:
		return
	var f := FileAccess.open(DIR + code + ".json", FileAccess.READ)
	if f == null:
		lang = DEFAULT
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_table = parsed

## Use an in-memory table (tests; a future in-game language picker can call set_language instead).
func use_table(code: String, table: Dictionary) -> void:
	lang = code
	_table = table

## Translate one string (unknown strings and numbers pass through unchanged).
func t(s: String) -> String:
	if _table.is_empty() or s == "":
		return s
	return String(_table.get(s, s))
