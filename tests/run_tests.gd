extends Node
## Headless test suite, one scenario per acceptance criterion (no external framework):
##   godot --headless --path . --fixed-fps 60 tests/run_tests.tscn
## Exit code 0 = all passed. Each scenario builds a fresh game, empties the launcher and drives the real physics.

var failures: Array[String] = []
var checks := 0
var game: Game

func _ready() -> void:
	await get_tree().process_frame
	test_data_and_geometry()
	test_tiers_and_spawning()
	test_scoring_rules()
	await test_trajectory_matches_physics()
	await test_throw_limits_and_double_launch()
	await test_touch_and_mouse_input()
	await test_merge_once()
	await test_merge_chain_and_max_tier()
	await test_float_and_sink()
	await test_displacement_raises_level()
	await test_flush_moves_and_removes()
	await test_blockage_restricts_drainage()
	await test_every_tier_flushable()
	await test_overflow_game_over()
	test_project_and_export()
	print("\n==== %d checks, %d failures ====" % [checks, failures.size()])
	for f in failures:
		print("FAIL: ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		print("  FAIL ", msg)

func near(a: float, b: float, tol: float, msg: String) -> void:
	ok(absf(a - b) <= tol, "%s (got %.3f, want %.3f +- %.3f)" % [msg, a, b, tol])

# ------------------------------------------------------------------ helpers

func new_game(keep_launcher := false) -> Game:
	if game and is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.rng.seed = 1234
	add_child(game)
	await get_tree().physics_frame
	if not keep_launcher:
		game.launcher.enabled = false
		if game.launcher.held:
			game.remove_object(game.launcher.held)
			game.launcher.held = null
	return game

func step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func seconds(s: float) -> void:
	await step(int(s * 60.0))

func count_tier(t: int) -> int:
	var n := 0
	for o in game.objects:
		if o.tier == t:
			n += 1
	return n

func flush_until(cond: Callable, max_flushes: int) -> int:
	var n := 0
	while n < max_flushes and not cond.call():
		while not game.water.can_flush():
			await step(5)
		game.request_flush()
		n += 1
		await seconds(float(Cfg.c.flush.duration) + 0.5)
	return n

# ------------------------------------------------------------------ static checks

func test_data_and_geometry() -> void:
	var geo := Cfg.geo
	ok(geo.left.size() > 20, "smoothed bowl profile")
	var prev := INF
	for y in range(int(geo.rim_y), int(geo.throat_y), 20):
		var v := geo.volume_at_level(y)
		ok(v < prev, "water volume falls as the level drops (y=%d)" % y)
		prev = v
		near(geo.level_for_volume(v), y, 1.5, "level_for_volume inverts volume_at_level at y=%d" % y)
	ok(geo.width_at(Cfg.bowl.rest_level_y) > 500.0, "bowl is wide at the water line")
	near(geo.width_at(geo.throat_y + 50), Cfg.bowl.drain_width, 0.01, "outlet width = drain_width")
	ok(Cfg.bowl.overflow_y < Cfg.bowl.rest_level_y and Cfg.bowl.overflow_y > geo.rim_y, "overflow line between rim and rest level")
	for k in ["throw", "water", "flush", "drain", "overflow", "merge", "score"]:
		ok(Cfg.c.has(k), "config section " + k)

func test_tiers_and_spawning() -> void:
	ok(Cfg.max_tier() == 6, "six tiers")
	var prev_area := 0.0
	for t in range(1, 7):
		var o := FlushObject.create(t, null)
		ok(o.area > prev_area * 1.2, "tier %d is bigger than tier %d (area %.0f)" % [t, t - 1, o.area])
		ok(o.samples.size() >= 20, "tier %d has buoyancy samples" % t)
		ok(o.sprite != null, "tier %d has its Layer sprite" % t)
		prev_area = o.area
		o.free()
	var g := Game.new()
	g.rng.seed = 99
	var seen := {}
	for i in 600:
		var t := g.roll_tier()
		seen[t] = true
		if t < 1 or t > 3:
			ok(false, "natural spawns are tiers 1-3 (got %d)" % t)
	ok(seen.size() == 3, "all three spawn tiers appear")
	g.free()

func test_scoring_rules() -> void:
	for t in range(1, 6):
		ok(Cfg.flush_points(t + 1) >= 2 * Cfg.flush_points(t), "flush reward grows exponentially (tier %d)" % (t + 1))
		ok(Cfg.merge_points(t + 1) < Cfg.flush_points(t + 1) / 2, "merging gives small points (tier %d)" % (t + 1))
		# the core decision: merging two and flushing the result beats flushing both now
		ok(Cfg.merge_points(t + 1) + Cfg.flush_points(t + 1) > 2 * Cfg.flush_points(t), "waiting to merge pays more (tier %d)" % t)

# ------------------------------------------------------------------ throwing

func test_trajectory_matches_physics() -> void:
	await new_game(true)
	var L := game.launcher
	for drag in [Vector2(-150, -250), Vector2(220, -120), Vector2(-60, -400), Vector2(300, 60)]:
		await step(int(Cfg.c.throw.cooldown * 60) + 5)
		ok(L.state == Launcher.State.READY, "launcher ready for the next throw")
		L.begin_aim(L.launch_pos)
		L.drag_to(L.launch_pos + drag)
		await step(2)
		var predicted := L.preview.duplicate()
		var o := L.held
		ok(predicted.size() > 10, "preview has points for drag %s" % drag)
		L.release()
		var worst := 0.0
		var compared := 0
		for i in mini(predicted.size(), 40):
			await get_tree().physics_frame
			if o.get_contact_count() > 0 or o.sub_frac > 0.0:
				break
			worst = maxf(worst, o.global_position.distance_to(predicted[i]))
			compared += 1
		ok(compared >= 8, "compared enough free-flight frames (%d) for drag %s" % [compared, drag])
		ok(worst < 6.0, "trajectory preview matches flight within 6 px (worst %.2f) for drag %s" % [worst, drag])

func test_throw_limits_and_double_launch() -> void:
	await new_game(true)
	var L := game.launcher
	var t: Dictionary = Cfg.c.throw
	near(L.velocity_for_drag(Vector2(0, -2000)).length(), t.max_speed, 0.01, "max throw speed is capped")
	near(L.velocity_for_drag(Vector2(0, -float(t.dead_zone) - 0.01)).length(), t.min_speed, 1.0, "min throw speed just past the dead zone")
	ok(L.velocity_for_drag(Vector2(0, -10)) == Vector2.ZERO, "tiny drag = no throw")
	ok(L.velocity_for_drag(Vector2(100, -100)).x < 0 and L.velocity_for_drag(Vector2(100, -100)).y > 0, "throw goes opposite to the drag")
	# cancel inside the dead zone keeps the object
	L.begin_aim(L.launch_pos)
	L.drag_to(L.launch_pos + Vector2(5, 5))
	ok(not L.release(), "dead-zone release cancels")
	ok(L.held != null and L.state == Launcher.State.READY, "cancelled throw keeps the object")
	# double launch protection
	var n0 := game.objects.size()
	L.begin_aim(L.launch_pos)
	L.drag_to(L.launch_pos + Vector2(0, -200))
	ok(L.release(), "first release launches")
	ok(not L.release(), "second release does nothing")
	L.begin_aim(L.launch_pos)
	ok(L.state == Launcher.State.WAITING and not L.release(), "no aiming during the cooldown")
	ok(L.held == null, "no object until the cooldown ends")
	await step(int(t.cooldown * 60) + 3)
	ok(L.held != null, "next object appears after the cooldown")
	ok(game.objects.size() == n0 + 1, "exactly one new object after one launch")

func test_touch_and_mouse_input() -> void:
	await new_game(true)
	var L := game.launcher
	# design/world point -> window pixel (stretch transform * camera transform), like a real finger
	var to_screen := func(p: Vector2) -> Vector2: return L.get_viewport().get_final_transform() * (L.get_canvas_transform() * p)
	# touch
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = to_screen.call(L.launch_pos + Vector2(20, 10))
	Input.parse_input_event(ev)
	await step(1)
	ok(L.state == Launcher.State.AIMING, "touch near the launcher starts aiming")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = to_screen.call(L.launch_pos + Vector2(-100, -220))
	Input.parse_input_event(drag)
	await step(1)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = drag.position
	Input.parse_input_event(up)
	await step(1)
	ok(L.launches == 1, "touch release launches")
	await step(int(Cfg.c.throw.cooldown * 60) + 3)
	# a touch far away from the launcher does nothing
	ev.position = to_screen.call(Vector2(540, 1500))
	Input.parse_input_event(ev)
	await step(1)
	ok(L.state == Launcher.State.READY, "touch far from the launcher is ignored")
	up.position = ev.position
	Input.parse_input_event(up)
	await step(1)
	# mouse (emulated as touch by the project setting)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = to_screen.call(L.launch_pos)
	mb.global_position = mb.position
	Input.parse_input_event(mb)
	await step(1)
	ok(L.state == Launcher.State.AIMING, "mouse press near the launcher starts aiming")
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = to_screen.call(L.launch_pos + Vector2(150, -200))
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await step(1)
	ok(L.current_velocity().length() > Cfg.c.throw.min_speed, "mouse drag sets a throw")
	var mu := mb.duplicate()
	mu.pressed = false
	mu.position = mm.position
	mu.global_position = mm.position
	Input.parse_input_event(mu)
	await step(1)
	ok(L.launches == 2, "mouse release launches (same path as touch)")
	# the FLUSH button reacts to a click/tap
	var c := game.get_viewport().get_final_transform() * game.hud.flush_button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = c
	press.global_position = c
	Input.parse_input_event(press)
	await step(1)
	var rel := press.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)
	await step(1)
	ok(game.water.flushing(), "FLUSH button starts a flush")

# ------------------------------------------------------------------ merging

func test_merge_once() -> void:
	await new_game()
	game.make_object(2, Vector2(540, 900))
	var b := game.make_object(2, Vector2(560, 700))
	b.linear_velocity = Vector2(0, 600)
	await seconds(1.5)
	ok(count_tier(2) == 0, "two tier-2 objects merged")
	ok(count_tier(3) == 1, "exactly one tier-3 created (no duplicate merge)")
	ok(game.objects.size() == 1, "no leftovers after a merge")
	ok(game.stats.merges == 1, "one merge counted")
	ok(game.score == Cfg.merge_points(3), "merge awards merge points")
	# momentum inheritance
	var g2 := await new_game()
	var x := g2.make_object(1, Vector2(300, 400))
	var y := g2.make_object(1, Vector2(388, 400))
	x.gravity_scale = 0.0
	y.gravity_scale = 0.0
	x.linear_velocity = Vector2(600, -100)
	y.linear_velocity = Vector2(0, -100)
	await step(20)
	ok(count_tier(2) == 1, "flying pair merged")
	if count_tier(2) == 1:
		var m: FlushObject = g2.objects[0]
		ok(m.linear_velocity.x > 60.0, "merged object keeps the pair's momentum (vx=%.0f)" % m.linear_velocity.x)

func test_merge_chain_and_max_tier() -> void:
	await new_game()
	for i in 3:
		game.make_object(1, Vector2(480 + i * 60, 900 - i * 120))
	await seconds(3.0)
	ok(count_tier(1) == 1 and count_tier(2) == 1, "three ducks -> one tier 2 + one duck (got t1=%d t2=%d)" % [count_tier(1), count_tier(2)])
	await new_game()
	game.make_object(6, Vector2(400, 900))
	game.make_object(6, Vector2(700, 900))
	await seconds(3.0)
	ok(count_tier(6) == 2, "max-tier objects never merge")

# ------------------------------------------------------------------ water

func test_float_and_sink() -> void:
	await new_game()
	var duck := game.make_object(1, Vector2(400, 1000))
	var boot := game.make_object(5, Vector2(700, 1000))
	await seconds(5.0)
	var lvl := game.water.level_y
	ok(duck.sub_frac > 0.1 and duck.sub_frac < 0.9, "duck floats partially submerged (%.2f)" % duck.sub_frac)
	near(duck.global_position.y, lvl, 50.0, "duck floats at the surface")
	ok(boot.sub_frac > 0.99, "boot is fully submerged")
	ok(boot.global_position.y > lvl + 120.0, "boot sank to the bottom")
	var tp := game.make_object(2, Vector2(540, 1000))
	await seconds(4.0)
	ok(tp.sub_frac > duck.sub_frac, "denser toilet paper floats lower than the duck")

func test_displacement_raises_level() -> void:
	await new_game()
	await seconds(0.5)
	var before := game.water.level_y
	var b := game.make_object(5, Vector2(540, 1250))
	await seconds(3.0)
	var after := game.water.level_y
	var expected := b.area / Cfg.geo.width_at(before)
	ok(before - after > expected * 0.6, "submerged boot raises the water (%.1f px, ~%.1f expected)" % [before - after, expected])
	game.remove_object(b)
	await seconds(2.0)
	near(game.water.level_y, before, 3.0, "level returns when the object is gone")

func test_flush_moves_and_removes() -> void:
	await new_game()
	var duck := game.make_object(1, Vector2(330, 1100))
	var tp := game.make_object(2, Vector2(760, 1100))
	await seconds(3.0)
	var p0 := duck.global_position
	var lvl0 := game.water.level_y
	game.request_flush()
	ok(game.water.flushing(), "flush starts")
	ok(not game.water.can_flush(), "no second flush while flushing")
	var lowest := lvl0
	var moved := 0.0
	var full := false
	for i in int((float(Cfg.c.flush.duration) + float(Cfg.c.flush.siphon_tail)) * 60.0) + 30:
		await get_tree().physics_frame
		lowest = maxf(lowest, game.water.level_y)
		full = full or game.water.strength() > 0.99
		if is_instance_valid(duck):
			moved = maxf(moved, duck.global_position.distance_to(p0))
	ok(full, "vortex reaches full strength")
	ok(moved > 60.0, "vortex moves floating objects (%.0f px)" % moved)
	ok(lowest > lvl0 + 60.0, "free flush lowers the visible water level (%.0f -> %.0f)" % [lvl0, lowest])
	ok(not is_instance_valid(duck) or not game.objects.has(duck), "small floating duck got flushed")
	ok(not is_instance_valid(tp) or not game.objects.has(tp), "toilet paper got flushed")
	ok(game.score >= Cfg.flush_points(1) + Cfg.flush_points(2), "flushing scores (score %d)" % game.score)
	ok(not game.water.can_flush(), "flush has a cooldown")
	await seconds(float(Cfg.c.flush.cooldown) + 0.2)
	ok(game.water.can_flush(), "flush ready again after the cooldown")
	await seconds(4.0)
	near(game.water.level_y, Cfg.bowl.rest_level_y, 8.0, "tank refills to rest level")

func test_blockage_restricts_drainage() -> void:
	await new_game()
	var gold := game.make_object(6, Vector2(540, 1250))
	await seconds(4.0)
	ok(game.water.blockage > 0.8, "golden toilet blocks the drain (blockage %.2f)" % game.water.blockage)
	ok(game.water.plug == gold, "golden toilet is detected as the plug")
	var lvl0 := game.water.level_y
	game.request_flush()
	await seconds(1.9)
	ok(game.water.level_y < lvl0 - 40.0, "blocked flush RAISES the water (%.0f -> %.0f)" % [lvl0, game.water.level_y])
	ok(gold.squeeze > 0.2, "drain pressure builds up on the plug (%.2f)" % gold.squeeze)
	# a free bowl drains the same flush
	await new_game()
	await seconds(1.0)
	var free0 := game.water.level_y
	game.request_flush()
	await seconds(float(Cfg.c.flush.duration))
	ok(game.water.level_y > free0 + 60.0, "unblocked flush lowers the water (%.0f -> %.0f)" % [free0, game.water.level_y])

func test_every_tier_flushable() -> void:
	for t in range(1, 7):
		await new_game()
		var o := game.make_object(t, Vector2(540 + (t % 2) * 40, 1000))
		await seconds(3.0)
		var oid := o.get_instance_id()
		var n := await flush_until(func(): return not is_instance_id_valid(oid), 5)
		ok(not is_instance_id_valid(oid), "tier %d can be flushed (took %d flushes)" % [t, n])
		ok(game.stats.flushed.get(t, 0) == 1, "tier %d flush scored" % t)
		ok(not game.game_over, "flushing a lone tier %d does not flood the toilet" % t)
		print("  tier %d flushed after %d flush(es), squeezed=%d" % [t, n, game.stats.squeezed])

func test_overflow_game_over() -> void:
	await new_game()
	var w := game.water
	# momentary overflow: no game over
	w.volume = Cfg.geo.volume_at_level(Cfg.bowl.overflow_y - 60)
	await seconds(1.0)
	ok(game.over_t > 0.5, "overflow timer runs while above the line")
	w.volume = w.rest_volume
	await seconds(2.5)
	ok(not game.game_over, "a short splash over the line is forgiven")
	ok(game.over_t < 0.5, "overflow timer recovers")
	# sustained overflow: blocked toilet, keep the water up
	var gold := game.make_object(6, Vector2(540, 1250))
	await seconds(3.0)
	w.volume = Cfg.geo.volume_at_level(Cfg.bowl.overflow_y - 60)
	await seconds(float(Cfg.c.overflow.grace_time) + 0.6)
	ok(game.game_over, "sustained overflow ends the game")
	ok(game.hud.restart_button.visible, "restart button shown")
	ok(not game.launcher.enabled, "no throwing after game over")
	ok(is_instance_valid(gold), "scene still alive after game over")

func test_project_and_export() -> void:
	ok(ProjectSettings.get_setting("display/window/handheld/orientation") == 1, "portrait orientation")
	ok(ProjectSettings.get_setting("display/window/size/viewport_width") == 1080 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1920, "9:16 design size")
	ok(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse") == true, "mouse emulates touch")
	ok(Engine.physics_ticks_per_second == 60, "60 Hz physics")
	var cfg := ConfigFile.new()
	ok(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg present")
	if cfg.get_value("preset.0", "platform", "") == "Android":
		ok(str(cfg.get_value("preset.0.options", "package/unique_name", "")) == "com.wrongbutton.flushroyale", "android package name")
