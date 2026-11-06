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
	await test_flush_charges()
	await test_triple_merge()
	await test_chain()
	await test_royal_flush_and_levels()
	test_localisation()
	test_project_and_export()
	Game.carry = {}
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

## A fresh game on `level`. Physics tests get unlimited flush charges unless real_charges.
func new_game(keep_launcher := false, level := 0, real_charges := false) -> Game:
	if game and is_instance_valid(game):
		game.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	Game.carry = {"level": level, "score": 0}
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.reload_enabled = false
	game.rng.seed = 1234
	add_child(game)
	await get_tree().physics_frame
	if not real_charges:
		game.charges = 99
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
	ok(Cfg.level_count() == 3, "three levels")
	for lv in Cfg.level_count():
		Cfg.set_level(lv)
		var id := Cfg.level_id()
		ok(Cfg.max_tier() == 9, "%s has nine tiers" % id)
		ok(ResourceLoader.exists("res://assets/processed/" + str(Cfg.level_def().background)), "%s background exists" % id)
		var prev_area := 0.0
		var names := {}
		for t in range(1, 10):
			var o := FlushObject.create(t, null)
			near(o.area, Cfg.tier_area(t), Cfg.tier_area(t) * 0.04, "%s tier %d is scaled to the size curve" % [id, t])
			ok(o.area > prev_area * 1.3, "%s tier %d bigger than tier %d" % [id, t, t - 1])
			ok(o.samples.size() >= 20, "%s tier %d has buoyancy samples" % [id, t])
			ok(o.sprite != null, "%s tier %d has its Layer sprite" % [id, t])
			names[o.def.name] = true
			prev_area = o.area
			o.free()
		ok(names.size() == 9, "%s: nine different objects" % id)
		Cfg.set_level(0)
	# the royal object is creatable: two tier-8 objects fit in the bowl side by side
	var d8 := 2.0 * sqrt(Cfg.tier_area(8) / PI)
	ok(2.0 * d8 < Cfg.geo.width_at(Cfg.bowl.rest_level_y), "two tier-8 objects fit side by side")
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
	for t in range(1, 9):
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
	game.make_object(9, Vector2(400, 900))
	game.make_object(9, Vector2(700, 900))
	await seconds(3.0)
	ok(count_tier(9) == 2, "max-tier objects never merge")
	ok(game.state == Game.State.PLAY, "placing max-tier objects is not a royal flush (only merging is)")

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
	for i in int((float(Cfg.c.flush.duration) + float(Cfg.c.flush.siphon_tail)) * 60.0) + 15:
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
	var gold := game.make_object(9, Vector2(540, 1250))
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
	for lv in 3:
		for t in range(1, 10):
			await new_game(false, lv)
			var o := game.make_object(t, Vector2(540 + (t % 2) * 40, 1000))
			await seconds(3.0)
			var oid := o.get_instance_id()
			var n := await flush_until(func(): return not is_instance_id_valid(oid), 6)
			ok(not is_instance_id_valid(oid), "%s tier %d can be flushed (took %d flushes)" % [Cfg.level_id(), t, n])
			ok(game.stats.flushed.get(t, 0) == 1, "%s tier %d flush scored" % [Cfg.level_id(), t])
			ok(not game.game_over, "flushing a lone %s tier %d does not flood the toilet" % [Cfg.level_id(), t])
			print("  %s tier %d flushed after %d flush(es)" % [Cfg.level_id(), t, n])

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
	var gold := game.make_object(9, Vector2(540, 1250))
	await seconds(3.0)
	w.volume = Cfg.geo.volume_at_level(Cfg.bowl.overflow_y - 60)
	await seconds(float(Cfg.c.overflow.grace_time) + 0.6)
	ok(game.game_over, "sustained overflow ends the game")
	ok(game.hud.restart_button.visible, "restart button shown")
	ok(not game.launcher.enabled, "no throwing after game over")
	ok(is_instance_valid(gold), "scene still alive after game over")

# ------------------------------------------------------------------ PoC 2: earned flush, triple merge, chain, royal flush

func test_flush_charges() -> void:
	await new_game(false, 0, true)
	ok(game.charges == int(Cfg.c.meter.start_charges), "level starts with %d flush charge(s)" % game.charges)
	ok(game.request_flush(), "a stored charge flushes")
	ok(game.charges == 0, "the flush used the charge")
	await seconds(float(Cfg.c.flush.duration) + float(Cfg.c.flush.siphon_tail) + 1.0)
	ok(not game.request_flush(), "no charge, no flush")
	ok(not game.water.flushing(), "water untouched without a charge")
	var m0 := game.meter
	game.make_object(1, Vector2(500, 900))
	var b := game.make_object(1, Vector2(520, 760))
	b.linear_velocity = Vector2(0, 500)
	await seconds(1.0)
	ok(game.meter > m0, "a merge fills the flush meter (%.2f -> %.2f)" % [m0, game.meter])
	game.add_meter(1.0)
	ok(game.charges == 1, "a full meter becomes a charge")
	game.add_meter(10.0)
	ok(game.charges == int(Cfg.c.meter.max_charges), "charges are capped at %d" % game.charges)
	ok(game.request_flush(), "earned charge flushes")

func test_triple_merge() -> void:
	await new_game()
	var r := sqrt(Cfg.tier_area(2) / PI)
	var objs: Array = []
	for i in 3:    # three toilet paper rolls dropped onto each other
		objs.append(game.make_object(2, Vector2(540 + (i - 1) * r * 1.6, 1000 - i * 30)))
	objs[1].linear_velocity = Vector2(0, 400)
	await seconds(2.0)
	ok(game.stats.triples == 1, "three matching objects make a TRIPLE MERGE (triples=%d)" % game.stats.triples)
	ok(count_tier(2) == 0, "all three were consumed")
	ok(count_tier(3) == 2 or count_tier(4) == 1, "...into TWO next-tier objects (t3=%d, t4=%d after a follow-up merge)" % [count_tier(3), count_tier(4)])
	# a lone pair stays a normal merge
	await new_game()
	game.make_object(2, Vector2(300, 1000))
	var b := game.make_object(2, Vector2(310, 860))
	b.linear_velocity = Vector2(0, 400)
	await seconds(1.5)
	ok(game.stats.triples == 0 and count_tier(3) == 1, "a pair is still one merge")

func test_chain() -> void:
	await new_game()
	var x := game.make_object(1, Vector2(300, 1000))
	var y := game.make_object(1, Vector2(388, 1000))
	var u := game.make_object(1, Vector2(700, 1000))
	var v := game.make_object(1, Vector2(788, 1000))
	for o in [x, y, u, v]:
		o.gravity_scale = 0.0
	x.linear_velocity = Vector2(500, 0)
	await seconds(0.5)
	var after_first := game.score
	u.linear_velocity = Vector2(500, 0)
	await seconds(0.5)
	ok(game.chain == 2, "a second merge inside the window is a chain (chain=%d)" % game.chain)
	ok(game.score - after_first > Cfg.merge_points(2), "chained merge pays more (%d > %d)" % [game.score - after_first, Cfg.merge_points(2)])
	for o in game.objects.duplicate():     # the chain results would fall in and merge again: clear the bowl
		game.remove_object(o)
	await seconds(float(Cfg.c.chain.window) + 0.5)
	game.make_object(2, Vector2(540, 1000))
	var w := game.make_object(2, Vector2(560, 860))
	w.linear_velocity = Vector2(0, 400)
	await seconds(1.0)
	ok(game.chain == 1, "the chain resets after the window")

func test_royal_flush_and_levels() -> void:
	for lv in 3:
		await new_game(false, lv)
		ok(game.discovered.size() == 3, "%s: the three spawn tiers are known at the start" % Cfg.level_id())
		for t in [1, 2, 3, 2, 1]:
			game.make_object(t, Vector2(300 + t * 90, 1100))
		await seconds(2.0)
		var before := game.score
		var a := game.make_object(8, Vector2(380, 650))
		var b := game.make_object(8, Vector2(720, 650))
		a.linear_velocity = Vector2(500, 0)
		b.linear_velocity = Vector2(-500, 0)
		var started := false
		for i in 60 * 3:
			await get_tree().physics_frame
			if game.state == Game.State.ROYAL:
				started = true
				break
		ok(started, "%s: merging two tier-8 objects starts the ROYAL FLUSH" % Cfg.level_id())
		ok(game.discovered.has(9), "%s: the royal object is discovered" % Cfg.level_id())
		ok(not game.launcher.enabled, "no throwing during the royal flush")
		var done := false
		for i in 60 * 20:
			await get_tree().physics_frame
			if game.state != Game.State.ROYAL:
				done = true
				break
		ok(done, "%s: the royal flush ends" % Cfg.level_id())
		ok(game.objects.is_empty(), "%s: the royal flush empties the bowl (%d left)" % [Cfg.level_id(), game.objects.size()])
		ok(game.score - before >= Cfg.flush_points(9) * int(Cfg.c.royal.multiplier), "%s: royal flush pays x%d (%d)" % [Cfg.level_id(), Cfg.c.royal.multiplier, game.score - before])
		ok(not game.game_over, "%s: no game over during the royal flush" % Cfg.level_id())
		near(Engine.time_scale, 1.0, 0.001, "slow motion is over")
		ok(game.hud.restart_button.visible, "%s: end panel shown" % Cfg.level_id())
		var score := game.score
		if lv < 2:
			ok(game.state == Game.State.LEVEL_DONE, "%s: level complete" % Cfg.level_id())
			ok(game.hud.restart_button.text == "NEXT LEVEL", "button says NEXT LEVEL")
			game._on_panel_button()
			ok(Game.carry.get("level", -1) == lv + 1 and Game.carry.get("score", -1) == score, "NEXT LEVEL carries the score into level %d" % (lv + 2))
		else:
			ok(game.state == Game.State.VICTORY, "last level: victory")
			ok(game.hud.restart_button.text == "PLAY AGAIN", "button says PLAY AGAIN")
			game._on_panel_button()
			ok(Game.carry.is_empty(), "PLAY AGAIN starts a fresh run")
	# game over -> retry the same level with the score it started with
	await new_game(false, 1)
	game.score = 500
	game.end_game()
	ok(game.hud.restart_button.text == "RETRY LEVEL", "game over offers RETRY LEVEL")
	game._on_panel_button()
	ok(Game.carry.get("level", -1) == 1 and Game.carry.get("score", -1) == 0, "retry restarts the level with its starting score")

# ------------------------------------------------------------------ localisation

func _game_scripts(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_game_scripts(dir.path_join(d), out)

func test_localisation() -> void:
	var f := FileAccess.open("res://data/i18n/en.json", FileAccess.READ)
	ok(f != null, "data/i18n/en.json exists (run tools/i18n/extract_strings.py)")
	if f == null:
		return
	var en: Dictionary = JSON.parse_string(f.get_as_text())
	# every name in the level data and every Loc.t literal in code has a key
	for lv in Cfg.levels:
		ok(en.has(lv.name), "en.json has level name " + str(lv.name))
		for t in lv.tiers:
			ok(en.has(t.name), "en.json has object name " + str(t.name))
	var scripts: Array = []
	_game_scripts("res://game", scripts)
	var call := RegEx.create_from_string('Loc\\.t\\(\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*\\)')
	var display := RegEx.create_from_string('(_text\\(|fx\\.text\\(|banner\\(|\\.text = )')
	var literal := RegEx.create_from_string('"[^"]*[A-Za-z]{2}[^"]*"')
	for path in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line: String = lines[i]
			for m in call.search_all(line):
				ok(en.has(m.get_string(1)), "en.json has %s (%s:%d)" % [m.get_string(1), path.get_file(), i + 1])
			# display call sites must not show raw English: every literal there goes through Loc.t
			if display.search(line) and not line.strip_edges().begins_with("#") and not line.contains("func "):
				var rest := call.sub(line, "", true)
				rest = RegEx.create_from_string('Color\\([^)]*\\)').sub(rest, "", true)
				ok(literal.search(rest) == null, "untranslated text at %s:%d: %s" % [path.get_file(), i + 1, line.strip_edges()])
	# runtime: a language table is used, formats fill after translating, unknown keys fall back to English
	ok(Loc.system_language() == "en", "desktop/editor language is English")
	Loc.use_table("xx", {"FLUSH": "SPUEL", "CHAIN x%d": "KETTE x%d", "Rubber Duck": "Quietscheente", "THE BATHROOM": "DAS BAD"})
	ok(Loc.t("FLUSH") == "SPUEL", "translated string")
	ok(Loc.t("CHAIN x%d") % 3 == "KETTE x3", "format translated before filling")
	ok(Loc.t("NOT A KEY") == "NOT A KEY", "unknown text falls back to English")
	Cfg.set_level(0)
	ok(Loc.t(Cfg.level_def().name) == "DAS BAD" and Loc.t(Cfg.tier(1).name) == "Quietscheente", "level and object names translate")
	Loc.set_language("en")
	ok(Loc.t("FLUSH") == "FLUSH" and Loc.lang == "en", "back to English")
	# shipped languages must keep the placeholders of every key
	var ph := RegEx.create_from_string("%[-+ 0#]*\\d*(?:\\.\\d+)?[dsfx%]")
	for code in Loc.available():
		if code == "en":
			continue
		var tr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/%s.json" % code))
		for k in tr:
			var a := ph.search_all(k).map(func(m): return m.get_string())
			var b := ph.search_all(str(tr[k])).map(func(m): return m.get_string())
			ok(a == b, "%s.json keeps the placeholders of '%s'" % [code, k])

func test_project_and_export() -> void:
	ok(ProjectSettings.get_setting("display/window/handheld/orientation") == 1, "portrait orientation")
	ok(ProjectSettings.get_setting("display/window/size/viewport_width") == 1080 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1920, "9:16 design size")
	ok(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse") == true, "mouse emulates touch")
	ok(Engine.physics_ticks_per_second == 60, "60 Hz physics")
	var cfg := ConfigFile.new()
	ok(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg present")
	if cfg.get_value("preset.0", "platform", "") == "Android":
		ok(str(cfg.get_value("preset.0.options", "package/unique_name", "")) == "com.wrongbutton.flushroyale", "android package name")
