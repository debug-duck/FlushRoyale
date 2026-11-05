extends Node
## Autoload `Cfg`: the three data files (config, objects, bowl) loaded once. Everything tunable lives in data/*.json.

const LAYER_BOWL := 1      # bowl walls, rim, screen edges
const LAYER_OBJECTS := 2   # merging objects
const LAYER_DRAIN := 4     # lower funnel + outlet + trap gate (a squeezed plug ignores these)

var c: Dictionary
var bowl: Dictionary
var tiers: Array
var geo: BowlGeometry

func _init() -> void:
	c = _load("res://data/config.json")
	bowl = _load("res://data/bowl.json")
	tiers = _load("res://data/objects.json").tiers
	geo = BowlGeometry.new(bowl)

func tier(t: int) -> Dictionary:
	return tiers[clampi(t, 1, tiers.size()) - 1]

func max_tier() -> int:
	return tiers.size()

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
