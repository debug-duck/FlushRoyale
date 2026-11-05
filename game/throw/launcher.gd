class_name Launcher
extends Node2D
## Slingshot throwing at a fixed spot above the bowl. Touch near the held object, drag BACK, release.
## Direction = opposite of the drag; drag length -> speed (min..max). The dotted preview integrates exactly like
## Godot's 2D solver (v += g*dt; p += v*dt at the physics tick), so it matches the real flight until the first contact.
## Touch and mouse share one code path (mouse is emulated as touch). One finger at a time; a release shorter than the
## dead zone cancels; after a launch there is a cooldown before the next object appears (no double launches).

enum State { WAITING, READY, AIMING }

var game: Node
var held: FlushObject
var state := State.WAITING
var launch_pos := Vector2(540, 420)
var drag_start := Vector2.ZERO
var drag_now := Vector2.ZERO
var touch_index := -1
var cooldown := 0.0
var enabled := true
var preview := PackedVector2Array()
var preview_hit := false
var launches := 0
var t: Dictionary = Cfg.c.throw

func _ready() -> void:
	launch_pos = Vector2(Cfg.bowl.launch[0], Cfg.bowl.launch[1])

func hold(o: FlushObject) -> void:
	held = o
	o.set_held(true)
	o.global_position = launch_pos
	o.rotation = 0.0
	state = State.READY

func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var p := _to_world(event.position)
		if event.pressed:
			if state == State.READY and touch_index == -1 and p.distance_to(launch_pos) <= float(t.grab_radius):
				begin_aim(p, event.index)
				get_viewport().set_input_as_handled()
		elif event.index == touch_index:
			drag_now = p
			release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_index and state == State.AIMING:
		drag_now = _to_world(event.position)
		get_viewport().set_input_as_handled()

func begin_aim(p: Vector2, index := 0) -> bool:
	if state != State.READY or not held or not enabled:
		return false
	state = State.AIMING
	touch_index = index
	drag_start = p
	drag_now = p
	return true

func drag_to(p: Vector2) -> void:
	if state == State.AIMING:
		drag_now = p

## Launch velocity for the current drag (Vector2.ZERO inside the dead zone).
func current_velocity() -> Vector2:
	return velocity_for_drag(drag_now - drag_start)

func velocity_for_drag(drag: Vector2) -> Vector2:
	var d := drag.length()
	if d < float(t.dead_zone):
		return Vector2.ZERO
	var k := clampf((d - float(t.dead_zone)) / (float(t.max_drag) - float(t.dead_zone)), 0.0, 1.0)
	return -drag.normalized() * lerpf(float(t.min_speed), float(t.max_speed), k)

func pull_offset() -> Vector2:
	return (drag_now - drag_start).limit_length(float(t.visual_pull)) if state == State.AIMING else Vector2.ZERO

## Returns true when something was launched.
func release() -> bool:
	if state != State.AIMING:
		return false
	touch_index = -1
	var v := current_velocity()
	if v == Vector2.ZERO or not held:
		state = State.READY          # too short: cancelled, the object stays
		return false
	var o := held
	o.global_position = launch_pos + pull_offset()
	held = null
	state = State.WAITING
	cooldown = float(t.cooldown)
	o.launch(v)
	launches += 1
	Sfx.play("launch", randf_range(0.9, 1.1))
	if game:
		game.on_launched(o)
	return true

func _physics_process(dt: float) -> void:
	if state == State.WAITING and cooldown > 0.0:
		cooldown -= dt
		if cooldown <= 0.0 and game and enabled:
			game.spawn_held()
	if held:
		held.global_position = launch_pos + pull_offset()
		held.linear_velocity = Vector2.ZERO
	_update_preview()
	queue_redraw()

## Same integration as the physics engine, one point per tick, stopping at the bowl, the water or another object.
func _update_preview() -> void:
	preview.clear()
	preview_hit = false
	if state != State.AIMING or not held:
		return
	var v := current_velocity()
	if v == Vector2.ZERO:
		return
	var g := Vector2(0, ProjectSettings.get_setting("physics/2d/default_gravity"))
	var dt := 1.0 / Engine.physics_ticks_per_second
	var p := launch_pos + pull_offset()
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var probe := CircleShape2D.new()
	probe.radius = held.radius() * 0.6
	q.shape = probe
	q.collision_mask = Cfg.LAYER_BOWL | Cfg.LAYER_OBJECTS | Cfg.LAYER_DRAIN
	var water: Water = game.water if game else null
	var n := int(float(t.preview_time) / dt)
	for i in n:
		v += g * dt
		p += v * dt
		preview.append(p)
		if water and p.y >= water.level_y and p.y > Cfg.geo.rim_y:
			preview_hit = true
			break
		if i % 2 == 0:
			q.transform = Transform2D(0.0, p)
			if not space.intersect_shape(q, 1).is_empty():
				preview_hit = true
				break

func _draw() -> void:
	var a := launch_pos + Vector2(-95, 30)
	var b := launch_pos + Vector2(95, 30)
	var ink := Color(0.16, 0.18, 0.26)
	# slingshot: a chrome toilet-roll-holder style fork with a rubber band
	for post in [a, b]:
		draw_line(post, post + Vector2(0, 70), ink, 16.0)
		draw_line(post, post + Vector2(0, 70), Color(0.85, 0.88, 0.93), 9.0)
		draw_circle(post, 13.0, ink)
		draw_circle(post, 8.0, Color(0.95, 0.96, 1.0))
	draw_line(a + Vector2(-50, 70), b + Vector2(50, 70), ink, 16.0)
	draw_line(a + Vector2(-50, 70), b + Vector2(50, 70), Color(0.85, 0.88, 0.93), 9.0)
	var hp := launch_pos + pull_offset()
	var band := Color(0.85, 0.25, 0.2)
	draw_line(a, hp, band, 7.0 if state == State.AIMING else 5.0)
	draw_line(b, hp, band, 7.0 if state == State.AIMING else 5.0)
	if state == State.READY:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_arc(launch_pos, 120.0 + pulse * 10.0, 0, TAU, 48, Color(1, 1, 1, 0.25 + 0.2 * pulse), 4.0)
	if state == State.AIMING:
		var v := current_velocity()
		var k := clampf((v.length() - float(t.min_speed)) / (float(t.max_speed) - float(t.min_speed)), 0.0, 1.0)
		var pc := Color(0.3, 0.9, 0.4).lerp(Color(1.0, 0.3, 0.2), k) if v != Vector2.ZERO else Color(1, 1, 1, 0.4)
		draw_arc(launch_pos, 60.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, pc, 10.0)
		var every: int = t.preview_dot_every
		for i in preview.size():
			if i % every == 0:
				var f := 1.0 - float(i) / maxf(preview.size(), 1.0) * 0.6
				draw_circle(preview[i], 8.0 * f, Color(1, 1, 1, 0.95 * f))
				draw_arc(preview[i], 8.0 * f, 0, TAU, 12, Color(ink, 0.6 * f), 2.0)
		if preview_hit and preview.size() > 0:
			draw_arc(preview[-1], 22.0, 0, TAU, 24, Color(1, 1, 1, 0.9), 4.0)
