class_name BowlGeometry
extends RefCounted
## The toilet interior as numbers: smoothed wall profile (same Catmull-Rom as tools/asset_pipeline/bowl_geometry.py, so
## art and physics agree), wall x at any height, and the water-volume <-> water-level table (2D area in px^2).

const SUBDIV := 6

var cx: float
var rim_y: float
var throat_y: float
var drain_w: float
var outlet_bottom: float
var left: PackedVector2Array      # rim lip -> throat, top to bottom
var right: PackedVector2Array
var _table_y0: float              # area table: index i = height rim_y - 400 + i, value = water area below that height
var _area := PackedFloat32Array()

func _init(b: Dictionary) -> void:
	cx = b.center_x
	rim_y = b.rim_y
	throat_y = b.throat_y
	drain_w = b.drain_width
	outlet_bottom = b.outlet_bottom
	var ctrl: Array[Vector2] = []
	for p in b.inner_left:
		ctrl.append(Vector2(p[0], p[1]))
	ctrl.append(Vector2(cx - drain_w * 0.5, throat_y))
	for i in ctrl.size() - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
		for s in SUBDIV:
			left.append(_catmull(p0, ctrl[i], ctrl[i + 1], p3, float(s) / SUBDIV))
	left.append(ctrl[-1])
	for p in left:
		right.append(Vector2(2.0 * cx - p.x, p.y))
	_build_table()

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## Left wall x at height y (rim width above the rim, drain width below the throat).
func x_left(y: float) -> float:
	if y <= left[0].y:
		return left[0].x
	if y >= throat_y:
		return cx - drain_w * 0.5
	for i in left.size() - 1:
		var a := left[i]
		var b := left[i + 1]
		if y <= b.y:
			return lerpf(a.x, b.x, (y - a.y) / maxf(b.y - a.y, 0.001))
	return cx - drain_w * 0.5

func x_right(y: float) -> float:
	return 2.0 * cx - x_left(y)

func width_at(y: float) -> float:
	return x_right(y) - x_left(y)

## True when p is inside the open interior (bowl above the throat, or the outlet pipe below it).
func inside(p: Vector2) -> bool:
	if p.y < rim_y or p.y > outlet_bottom:
		return false
	return p.x > x_left(p.y) and p.x < x_right(p.y)

func _build_table() -> void:
	_table_y0 = rim_y - 400.0
	var n := int(throat_y - _table_y0) + 1
	_area.resize(n)
	var acc := 0.0
	for i in range(n - 1, -1, -1):
		_area[i] = acc
		acc += width_at(_table_y0 + i + 0.5)

## Water area (bowl part, above the throat) when the surface is at height y.
func volume_at_level(y: float) -> float:
	var f := clampf(y - _table_y0, 0.0, _area.size() - 1.0)
	var i := int(f)
	return lerpf(_area[i], _area[mini(i + 1, _area.size() - 1)], f - i)

## Surface height for a given water area (inverse of volume_at_level).
func level_for_volume(v: float) -> float:
	if v <= 0.0:
		return throat_y
	var lo := 0
	var hi := _area.size() - 1
	if v >= _area[0]:
		return _table_y0 - (v - _area[0]) / width_at(_table_y0)
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _area[mid] >= v:
			lo = mid
		else:
			hi = mid
	var a0 := _area[lo]
	var a1 := _area[hi]
	return _table_y0 + lo + (a0 - v) / maxf(a0 - a1, 0.001)
