class_name Bowl
extends Node2D
## Builds the toilet's collision from BowlGeometry: thick convex wall pieces along the interior profile (so fast throws
## cannot tunnel), the inward rim slopes, screen-edge walls and the outlet. The lower funnel + outlet live on the DRAIN
## layer (a squeezed plug ignores it). The trap gate is a drain-layer bar across the outlet: closed = water seal,
## open during a flush. All art is the background painting; this node only draws in debug mode.

var geo: BowlGeometry
var main_body: StaticBody2D
var drain_body: StaticBody2D
var gate_shape: CollisionShape2D
var gate_y: float
var debug_draw := false

func _ready() -> void:
	geo = Cfg.geo
	var b := Cfg.bowl
	var t: float = b.wall_thickness
	main_body = _body("BowlBody", Cfg.LAYER_BOWL)
	drain_body = _body("DrainBody", Cfg.LAYER_DRAIN)
	var drain_from: float = b.drain_layer_from_y
	for side in [geo.left, geo.right]:
		var outward := -1.0 if side == geo.left else 1.0
		var pts: PackedVector2Array = side.duplicate()
		pts.append(Vector2(pts[-1].x, geo.outlet_bottom))
		for i in pts.size() - 1:
			var a := pts[i]
			var c := pts[i + 1]
			var d := (c - a).normalized()
			var n := Vector2(-d.y, d.x) if outward < 0.0 else Vector2(d.y, -d.x)
			var target := drain_body if a.y >= drain_from else main_body
			# extend each piece a little along the wall so neighbouring pieces overlap (no seams)
			_quad(target, [a - d * 6.0, c + d * 6.0, c + d * 6.0 + n * t, a - d * 6.0 + n * t])
	# rim slopes: from the screen edge down to the rim lip, so everything that lands on the rim slides in
	var top: float = b.rim_slope_top_y
	_quad(main_body, [Vector2(-60, top - 20), geo.left[0], geo.left[0] + Vector2(0, 60), Vector2(-60, top + 60)])
	_quad(main_body, [Vector2(1140, top - 20), geo.right[0], geo.right[0] + Vector2(0, 60), Vector2(1140, top + 60)])
	# screen edges and a ceiling far above the screen (wild lobs come back down)
	_quad(main_body, [Vector2(-160, -1600), Vector2(0, -1600), Vector2(0, top), Vector2(-160, top)])
	_quad(main_body, [Vector2(1080, -1600), Vector2(1240, -1600), Vector2(1240, top), Vector2(1080, top)])
	_quad(main_body, [Vector2(-160, -1760), Vector2(1240, -1760), Vector2(1240, -1600), Vector2(-160, -1600)])
	# trap gate
	gate_y = b.trap_gate_y
	gate_shape = _quad(drain_body, [Vector2(geo.cx - geo.drain_w, gate_y), Vector2(geo.cx + geo.drain_w, gate_y),
		Vector2(geo.cx + geo.drain_w, gate_y + 30), Vector2(geo.cx - geo.drain_w, gate_y + 30)])

func set_gate_open(open: bool) -> void:
	gate_shape.set_deferred("disabled", open)

func gate_open() -> bool:
	return gate_shape.disabled

func _body(n: String, layer: int) -> StaticBody2D:
	var s := StaticBody2D.new()
	s.name = n
	s.collision_layer = layer
	s.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	s.physics_material_override = pm
	add_child(s)
	return s

func _quad(body: StaticBody2D, pts: Array) -> CollisionShape2D:
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(PackedVector2Array(pts))     # convex hull = correct winding whatever the input order
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	return cs

func _process(_dt: float) -> void:
	if debug_draw:
		queue_redraw()

func _draw() -> void:
	if not debug_draw:
		return
	for body in [main_body, drain_body]:
		var col := Color(1, 0.2, 0.2, 0.5) if body == main_body else Color(1, 0.7, 0.1, 0.5)
		for cs in body.get_children():
			if cs is CollisionShape2D and not cs.disabled:
				var pts: PackedVector2Array = cs.shape.points
				pts.append(pts[0])
				draw_polyline(pts, col, 2.0)
