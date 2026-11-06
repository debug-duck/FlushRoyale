extends Node
## Autoload `Cfg`: the data files loaded once (config, bowl, levels, generated shapes) plus the current level.
## Everything tunable lives in data/*.json. `tier(t)` always answers for the CURRENT level.

const LAYER_BOWL := 1      # bowl walls, rim, screen edges
const LAYER_OBJECTS := 2   # merging objects
const LAYER_DRAIN := 4     # lower funnel + outlet + trap gate (a squeezed plug ignores these)

var c: Dictionary          # config.json merged with the current level's `params`
var base_c: Dictionary
var bowl: Dictionary
var levels: Array
var generated: Dictionary
var geo: BowlGeometry
var level := 0             # index into levels

func _init() -> void:
	base_c = _load("res://data/config.json")
	bowl = _load("res://data/bowl.json")
	levels = _load("res://data/levels.json").levels
	generated = _load("res://data/shapes_generated.json")
	geo = BowlGeometry.new(bowl)
	set_level(0)

func set_level(i: int) -> void:
	level = clampi(i, 0, levels.size() - 1)
	c = base_c.duplicate(true)
	var params: Dictionary = levels[level].get("params", {})
	for section in params:
		if c.has(section) and c[section] is Dictionary:
			c[section].merge(params[section], true)
		else:
			c[section] = params[section]

func level_def() -> Dictionary:
	return levels[level]

## A text field of the current level (name, tagline, royal_message), "" when missing. Translate with Loc.t().
func level_text(key: String) -> String:
	return str(levels[level].get(key, ""))

func level_id() -> String:
	return levels[level].id

func level_count() -> int:
	return levels.size()

## Normalised tier definition of the current level: name, density, resistance, color, shapes, sprite{file,size}, com?.
func tier(t: int) -> Dictionary:
	var tiers: Array = levels[level].tiers
	var d: Dictionary = tiers[clampi(t, 1, tiers.size()) - 1].duplicate(true)
	var res: Array = c.tiers.resistance
	d.tier = t
	d.resistance = d.get("resistance", res[clampi(t, 1, res.size()) - 1])
	if not d.has("shapes"):
		var g: Dictionary = generated.get(d.sprite, {})
		d.shapes = g.get("shapes", [{"type": "circle", "r": 50}])
		d.sprite_size = g.get("size", [100, 100])
	d.sprite = {"file": d.sprite, "size": d.get("sprite_size", [100, 100])}
	return d

func max_tier() -> int:
	return levels[level].tiers.size()

## Target area of a tier (px^2): the same size curve for every level.
func tier_area(t: int) -> float:
	return float(c.tiers.base_area) * pow(float(c.tiers.ratio), t - 1)

func spawn_weights() -> Array:
	return levels[level].get("spawn_weights", [45, 35, 20])

func flush_points(t: int) -> int:
	return int(c.score.flush_base * pow(c.score.flush_mult, t - 1))

func merge_points(new_tier: int) -> int:
	return int(c.score.merge_base * pow(2, new_tier - 1))

static func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "missing " + path)
	var d = JSON.parse_string(f.get_as_text())
	assert(d is Dictionary, "bad json " + path)
	return d
