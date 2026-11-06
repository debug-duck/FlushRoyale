class_name FlushObject
extends RigidBody2D
## One throwable/mergeable object of the current level. Collision = shapes from data/levels.json (hand-authored) or
## data/shapes_generated.json, scaled so the tier covers Cfg.tier_area(t); the Layer sprite is fitted on top. A grid of sample points (equal area each) gives buoyancy, displacement and vortex forces that act at
## the right place, so torques (upside-down ducks, plungers floating handle-up) emerge from the physics.

const SAMPLE_TARGET := 40
static var _geometry_cache := {}       # "level:tier" -> {scale, area, samples}: the grid scan is too slow to redo per merge

var tier := 1
var def: Dictionary
var game: Node
var area := 0.0                        # px^2 (union of the shapes)
var samples := PackedVector2Array()    # local points, each worth area / samples.size()
var hull := PackedVector2Array()       # local outline points (for the drain width test)
var held := false
var merging := false
var passing := false                   # squeezed through the drain by pressure: ignores the drain layer
var squeeze := 0.0                     # 0..1 progress of the pressure squeeze while plugging the drain
var is_plug := false
var sub_frac := 0.0                    # submerged share, written by Water every physics frame
var was_under := false
var born := 0.0
var swirl_phase := randf() * TAU     # each object sloshes differently in the whirlpool
var sprite: Sprite2D
var _sprite_scale := Vector2.ONE
var _shape_nodes: Array[CollisionShape2D] = []
var _shape_pos: Array[Vector2] = []
var _grow := 1.0
var _grow_from := 1.0
var _pop_t := 9.0
var _squash := 1.0
var _shapes_local: Array = []          # [{type, data}] for inside tests

static func create(t: int, game_node: Node) -> FlushObject:
	var o := FlushObject.new()
	o.game = game_node
	o._setup(t)
	return o

func _setup(t: int) -> void:
	tier = t
	def = Cfg.tier(t)
	name = "T%d_%s" % [t, str(def.name).replace(" ", "")]
	var key := "%s:%d" % [Cfg.level_id(), t]
	if not _geometry_cache.has(key):
		_build_shapes(1.0)                      # raw units -> measure, then rebuild at the size the curve asks for
		_compute_area_and_samples()
		var k := sqrt(Cfg.tier_area(t) / maxf(area, 1.0))
		_clear_shapes()
		_build_shapes(k)
		_compute_area_and_samples()
		_geometry_cache[key] = {"scale": k, "area": area, "samples": samples}
	else:
		_build_shapes(_geometry_cache[key].scale)
	var sc: float = _geometry_cache[key].scale
	area = _geometry_cache[key].area
	samples = _geometry_cache[key].samples
	mass = maxf(0.05, float(def.density) * area / 1000.0)
	if def.has("com"):
		center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = Vector2(def.com[0], def.com[1]) * sc
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.get("friction", 0.45))
	pm.bounce = float(def.get("bounce", 0.12))
	physics_material_override = pm
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	can_sleep = false
	collision_layer = Cfg.LAYER_OBJECTS
	collision_mask = Cfg.LAYER_BOWL | Cfg.LAYER_OBJECTS | Cfg.LAYER_DRAIN
	var path := "res://assets/processed/" + str(def.sprite.file)
	if ResourceLoader.exists(path):
		sprite = Sprite2D.new()
		sprite.texture = load(path)
		var size := Vector2(def.sprite.size[0], def.sprite.size[1]) * sc
		_sprite_scale = size / sprite.texture.get_size()
		sprite.scale = _sprite_scale
		add_child(sprite)
	body_entered.connect(_on_body_entered)
	born = Time.get_ticks_msec() / 1000.0

func _build_shapes(sc: float) -> void:
	for s in def.shapes:
		_add_shape(s, sc)

func _clear_shapes() -> void:
	for n in _shape_nodes:
		n.free()
	_shape_nodes.clear()
	_shape_pos.clear()
	_shapes_local.clear()
	hull.clear()
	samples.clear()

func _add_shape(s: Dictionary, sc: float) -> void:
	var cs := CollisionShape2D.new()
	var pos := Vector2.ZERO
	if s.has("pos"):
		pos = Vector2(s.pos[0], s.pos[1]) * sc
	match s.type:
		"circle":
			var c := CircleShape2D.new()
			c.radius = s.r * sc
			cs.shape = c
			for i in 16:
				hull.append(pos + Vector2.from_angle(TAU * i / 16.0) * c.radius)
			_shapes_local.append({"type": "circle", "pos": pos, "r": c.radius})
		"capsule":
			var c := CapsuleShape2D.new()
			c.radius = s.r * sc
			c.height = s.h * sc
			cs.shape = c
			var half := c.height * 0.5 - c.radius
			for i in 16:
				var a := TAU * i / 16.0
				hull.append(pos + Vector2(cos(a) * c.radius, sin(a) * c.radius + (half if sin(a) > 0 else -half)))
			_shapes_local.append({"type": "capsule", "pos": pos, "r": c.radius, "half": half})
		_:
			var pts := PackedVector2Array()
			if s.type == "rect":
				var h := Vector2(s.size[0], s.size[1]) * sc * 0.5
				var b: float = s.get("bevel", 0.0) * sc
				pts = PackedVector2Array([Vector2(-h.x + b, -h.y), Vector2(h.x - b, -h.y), Vector2(h.x, -h.y + b), Vector2(h.x, h.y - b),
					Vector2(h.x - b, h.y), Vector2(-h.x + b, h.y), Vector2(-h.x, h.y - b), Vector2(-h.x, -h.y + b)])
			else:
				for p in s.points:
					pts.append(Vector2(p[0], p[1]) * sc)
			var c := ConvexPolygonShape2D.new()
			c.set_point_cloud(pts)
			cs.shape = c
			var poly := Geometry2D.convex_hull(pts)
			for p in poly:
				hull.append(p + pos)
			_shapes_local.append({"type": "poly", "pos": pos, "poly": poly})
	cs.position = pos
	add_child(cs)
	_shape_nodes.append(cs)
	_shape_pos.append(pos)

func _inside(p: Vector2) -> bool:
	for s in _shapes_local:
		var q: Vector2 = p - s.pos
		match s.type:
			"circle":
				if q.length() <= s.r:
					return true
			"capsule":
				var y := clampf(q.y, -s.half, s.half)
				if Vector2(q.x, q.y - y).length() <= s.r:
					return true
			_:
				if Geometry2D.is_point_in_polygon(q, s.poly):
					return true
	return false

func _compute_area_and_samples() -> void:
	var r := Rect2(hull[0], Vector2.ZERO)
	for p in hull:
		r = r.expand(p)
	var fine := 3.0
	var count := 0
	var y := r.position.y + fine * 0.5
	while y < r.end.y:
		var x := r.position.x + fine * 0.5
		while x < r.end.x:
			if _inside(Vector2(x, y)):
				count += 1
			x += fine
		y += fine
	area = count * fine * fine
	var g := sqrt(area / SAMPLE_TARGET)
	y = r.position.y + g * 0.5
	while y < r.end.y:
		var x := r.position.x + g * 0.5
		while x < r.end.x:
			if _inside(Vector2(x, y)):
				samples.append(Vector2(x, y))
			x += g
		y += g

## Equivalent radius (for previews, falloffs and effects).
func radius() -> float:
	return sqrt(area / PI)

## Horizontal width of the object at its current rotation (what has to fit through the drain).
func extent_x() -> float:
	var lo := INF
	var hi := -INF
	var rot := Transform2D(rotation, Vector2.ZERO)
	for p in hull:
		var x := (rot * p).x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return (hi - lo) * _grow

func set_held(on: bool) -> void:
	held = on
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = on
	collision_layer = 0 if on else Cfg.LAYER_OBJECTS
	collision_mask = 0 if on else (Cfg.LAYER_BOWL | Cfg.LAYER_OBJECTS | Cfg.LAYER_DRAIN)

## Slingshot release: an impulse of mass * v gives exactly the launch velocity the trajectory preview used.
func launch(v: Vector2) -> void:
	set_held(false)
	apply_central_impulse(v * mass)

## Merge result: starts slightly small and grows (no violent overlap push-out), plus a squash/pop.
func start_pop(grow_from: float) -> void:
	_grow_from = grow_from
	_grow = grow_from
	_pop_t = 0.0
	_apply_grow()

## Squeezed through the drain by pressure (ignores the drain layer). In the ROYAL FLUSH everything also ignores the
## other objects, so the whole bowl pours down the drain.
func start_passing(royal_flush := false) -> void:
	passing = true
	is_plug = false
	merging = false
	collision_mask = Cfg.LAYER_BOWL if royal_flush else (Cfg.LAYER_BOWL | Cfg.LAYER_OBJECTS)

func _apply_grow() -> void:
	for i in _shape_nodes.size():
		_shape_nodes[i].scale = Vector2.ONE * _grow
		_shape_nodes[i].position = _shape_pos[i] * _grow

## Farthest collision point from the centre (broad phase for Game's touch scan).
func reach() -> float:
	var r := 0.0
	for p in hull:
		r = maxf(r, p.length())
	return r * _grow

## True if any of our collision shapes is within `pad` px of body `b` (a real shape query: works for resting contacts that
## the contact signal never reported).
func touches(b: FlushObject, pad: float) -> bool:
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.collision_mask = Cfg.LAYER_OBJECTS
	q.margin = pad
	q.exclude = [get_rid()]
	for cs in _shape_nodes:
		q.shape = cs.shape
		q.transform = cs.global_transform
		for hit in space.intersect_shape(q, 12):
			if hit.collider == b:
				return true
	return false

func _on_body_entered(b: Node) -> void:
	if b is FlushObject and game and game.has_method("try_merge"):
		game.try_merge(self, b)

func _process(dt: float) -> void:
	if _pop_t < 1.0:
		_pop_t = minf(1.0, _pop_t + dt / maxf(0.05, float(Cfg.c.merge.grow_time) * 2.2))
		_grow = lerpf(_grow_from, 1.0, minf(1.0, _pop_t * 2.2))
		_apply_grow()
	if passing:
		var target := clampf(Cfg.geo.drain_w * 0.92 / maxf(extent_x(), 1.0), 0.35, 1.0)
		_squash = lerpf(_squash, target, minf(1.0, dt * 10.0))
	if sprite:
		var a := 0.22 * exp(-6.0 * _pop_t) * sin(_pop_t * 22.0) if _pop_t < 1.0 else 0.0
		var wob := sin(Time.get_ticks_msec() * 0.04) * 0.05 * squeeze if is_plug else 0.0
		var g := lerpf(_grow, 1.0, 0.4) if _pop_t < 1.0 else 1.0
		var local_scale := _sprite_scale * Vector2(1.0 + a + wob, 1.0 - a - wob) * g
		if passing:
			# squash in WORLD x (the drain is vertical), whatever the object's rotation
			var w := Transform2D(Vector2(_squash, 0), Vector2(0, 1.0 / sqrt(_squash)), Vector2.ZERO)
			sprite.global_transform = Transform2D(0, global_position) * w * Transform2D(rotation, local_scale, 0.0, Vector2.ZERO)
		else:
			sprite.transform = Transform2D(0.0, local_scale, 0.0, Vector2.ZERO)
		sprite.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.55, 0.5), squeeze * 0.7) if is_plug else Color.WHITE
	if is_plug or squeeze > 0.0 or not sprite:
		queue_redraw()

func _draw() -> void:
	if not sprite:
		var col := Color(def.color)
		for s in _shapes_local:
			var p: Vector2 = s.pos * _grow
			match s.type:
				"circle":
					draw_circle(p, s.r * _grow, col)
				"capsule":
					draw_rect(Rect2(p - Vector2(s.r, s.half) * _grow, Vector2(s.r * 2.0, s.half * 2.0) * _grow), col)
					draw_circle(p + Vector2(0, -s.half) * _grow, s.r * _grow, col)
					draw_circle(p + Vector2(0, s.half) * _grow, s.r * _grow, col)
				_:
					var poly := PackedVector2Array()
					for q in s.poly:
						poly.append(p + q * _grow)
					draw_colored_polygon(poly, col)
	if squeeze > 0.01 and (is_plug or passing):
		# pressure gauge ring: how close the drain pressure is to pushing this plug through
		draw_set_transform(Vector2.ZERO, -rotation)
		var r := radius() * 0.9 + 18.0
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(0, 0, 0, 0.35), 12.0)
		draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * squeeze, 40, Color(1.0, 0.35 + 0.4 * (1.0 - squeeze), 0.2), 9.0)
		draw_set_transform(Vector2.ZERO, 0.0)
