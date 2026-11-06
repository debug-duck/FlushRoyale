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
	await test_resting_matches_merge()
	await test_toilet_shake()
	await test_chain()
	await test_cascade_feedback()
	await test_royal_flush_and_levels()
	await test_rising_water()
	await test_natural_clear()
	await test_emergency_flush_sacrifice()
	await test_title_and_dev_mode()
	await test_level_select_and_progress()
	await test_showcase()
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
	game.intros_enabled = false
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
	ok(Cfg.level_count() == 7, "seven locations (1.0.1)")
	var order := []
	for lv in Cfg.levels:
		order.append(lv.id)
	ok(order == ["dorm", "whitehouse", "royal", "area51", "vatican", "hollywood", "earth"], "play order: %s" % str(order))
	ok(Cfg.levels[-1].get("finale", null) is Dictionary, "the last location is the finale")
	for lv in Cfg.level_count():
		Cfg.set_level(lv)
		var id := Cfg.level_id()
		ok(Cfg.max_tier() == 9, "%s has nine tiers" % id)
		ok(ResourceLoader.exists("res://assets/processed/" + str(Cfg.level_def().background)), "%s background exists" % id)
		ok(ResourceLoader.exists("res://assets/processed/ui/thumb_%s.jpg" % id), "%s level-select thumbnail exists" % id)
		for k in ["name", "tagline", "royal_message"]:
			ok(str(Cfg.level_def().get(k, "")) != "", "%s has a %s" % [id, k])
		var prev_area := 0.0
		var names := {}
		for t in range(1, 10):
			var o := FlushObject.create(t, null)
			near(o.area, Cfg.tier_area(t), Cfg.tier_area(t) * 0.04, "%s tier %d is scaled to the size curve" % [id, t])
			ok(o.area > prev_area * 1.3, "%s tier %d bigger than tier %d" % [id, t, t - 1])
			ok(o.samples.size() >= 20, "%s tier %d has buoyancy samples" % [id, t])
			ok(o.sprite != null, "%s tier %d has its Layer sprite" % [id, t])
			ok(o.get_child_count() > 0 and o.hull.size() >= 3, "%s tier %d has collision shapes" % [id, t])
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
	var duck := game.make_object(1, Vector2(400, 1000))      # party cup, density 0.45
	var boot := game.make_object(4, Vector2(700, 1000))      # unopened textbook, density 1.9
	await seconds(5.0)
	var lvl := game.water.level_y
	ok(duck.sub_frac > 0.1 and duck.sub_frac < 0.9, "party cup floats partially submerged (%.2f)" % duck.sub_frac)
	near(duck.global_position.y, lvl, 60.0, "party cup floats at the surface")
	ok(boot.sub_frac > 0.99, "textbook is fully submerged")
	ok(boot.global_position.y > lvl + 120.0, "textbook sank to the bottom")
	var tp := game.make_object(2, Vector2(540, 1000))
	await seconds(4.0)
	ok(tp.sub_frac > duck.sub_frac, "denser pizza floats lower than the cup")
	var sock := game.make_object(3, Vector2(300, 1000))      # radioactive sock, 0.28: unusually buoyant
	await seconds(4.0)
	ok(sock.sub_frac < tp.sub_frac, "radioactive sock rides higher than the pizza (%.2f < %.2f)" % [sock.sub_frac, tp.sub_frac])

func test_displacement_raises_level() -> void:
	await new_game()
	await seconds(0.5)
	var before := game.water.level_y
	var b := game.make_object(7, Vector2(540, 1100))         # filthy couch: floats, mostly submerged
	await seconds(3.0)
	var after := game.water.level_y
	var expected := b.area * b.sub_frac / Cfg.geo.width_at(before)
	ok(before - after > expected * 0.6, "the submerged part of the couch raises the water (%.1f px, ~%.1f expected)" % [before - after, expected])
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
	ok(game.score == 0, "an emergency flush scores nothing (score %d)" % game.score)
	ok(game.stats.lost.get(1, 0) + game.stats.lost.get(2, 0) == 2, "flushed objects are LOST")
	ok(not game.water.can_flush(), "flush has a cooldown")
	await seconds(float(Cfg.c.flush.cooldown) + 0.2)
	ok(game.water.can_flush(), "flush ready again after the cooldown")
	await seconds(4.0)
	near(game.water.level_y, Cfg.bowl.rest_level_y, 8.0, "tank refills to rest level")

func test_blockage_restricts_drainage() -> void:
	await new_game()
	var gold := game.make_object(9, Vector2(540, 1250))
	await seconds(4.0)
	ok(game.water.blockage > 0.8, "the university blocks the drain (blockage %.2f)" % game.water.blockage)
	ok(game.water.plug == gold, "it is detected as the plug")
	var lvl0 := game.water.level_y
	game.request_flush()
	await seconds(1.9)
	ok(game.water.level_y > lvl0 - 20.0, "a blocked emergency flush does not drain (%.0f -> %.0f)" % [lvl0, game.water.level_y])
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
			ok(game.stats.flushed.get(t, 0) == 1 and game.stats.lost.get(t, 0) == 1, "%s tier %d went down the drain (lost)" % [Cfg.level_id(), t])
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

## The megaphone bug: in a crowded bowl matching objects came to rest against each other without a contact report (the signal
## only reports NEW contacts, max_contacts_reported per body). The touch scan must merge every resting matching pair.
func test_resting_matches_merge() -> void:
	await new_game(false, 1)
	var a := game.make_object(5, Vector2(470, 1000))
	var b := game.make_object(5, Vector2(610, 1000))
	a.merging = true          # busy when they touch: the contact signal is used up
	await seconds(2.0)
	ok(game.objects.has(a) and game.objects.has(b), "megaphones are not merged while one is busy")
	a.merging = false
	await seconds(0.6)
	ok(not game.objects.has(a) and not game.objects.has(b), "resting megaphones merge as soon as they can (touch scan)")
	var leftovers := 0
	for run in 3:
		await new_game(false, 1)
		var r := RandomNumberGenerator.new()
		r.seed = 77 + run
		for i in 36:
			game.make_object(1 + r.randi() % 6, Vector2(r.randf_range(250, 830), r.randf_range(500, 900)))
			await step(4)
		await seconds(6.0)
		var objs := game.objects.filter(func(o): return not o.merging)
		for i in objs.size():
			for j in range(i + 1, objs.size()):
				if objs[i].tier == objs[j].tier and objs[i].tier < Cfg.max_tier() and objs[i].touches(objs[j], 1.0):
					leftovers += 1
		print("  crowded bowl %d: %d objects, scan merges %d" % [run, game.objects.size(), int(game.stats.get("scan_merges", 0))])
	ok(leftovers == 0, "no matching pair stays resting in contact in a crowded bowl (%d left)" % leftovers)

## TOILET SHAKE bonus: earned by merges; the hand shakes EVERY object (also wedged / resting ones), nothing leaves the bowl,
## and a plug in the drain is knocked loose.
func test_toilet_shake() -> void:
	await new_game(false, 0, true)
	ok(game.shake_charges == 0 and not game.request_shake(), "no shake before it is earned")
	var need := int(ceil(1.0 / float(Cfg.c.shake.per_merge)))
	for i in need - 1:
		game._score_merge(2, Vector2(540, 1000), 30.0, false)
	ok(game.shake_charges == 0, "not yet after %d merges" % (need - 1))
	game._score_merge(2, Vector2(540, 1000), 30.0, false)
	ok(game.shake_charges == 1, "a shake is earned after %d merges" % need)
	# a crowded bowl, settled: every object must get shaken
	await new_game(false, 1)
	var r := RandomNumberGenerator.new()      # own generator: effects elsewhere draw from the global one
	r.seed = 5
	for i in 26:
		game.make_object(1 + r.randi() % 5, Vector2(r.randf_range(250, 830), r.randf_range(520, 900)))
		await step(4)
	await seconds(5.0)
	var before := game.objects.duplicate()
	game.add_shake(1.0)
	ok(game.request_shake() and game.shaker.active(), "the SHAKE button starts the hand")
	ok(not game.request_shake(), "one shake at a time")
	var tot := float(Cfg.c.shake.reach_time) + float(Cfg.c.shake.grab_pause) + float(Cfg.c.shake.duration) + float(Cfg.c.shake.lift_time)
	var out := 0
	for i in int((tot + 0.2) * 60.0):
		await get_tree().physics_frame
		for o in game.objects:
			if o.global_position.y < float(Cfg.bowl.rim_slope_top_y) - 300.0 or o.global_position.x < 0.0 or o.global_position.x > 1080.0:
				out += 1
	ok(not game.shaker.active(), "the shake ends (%.1f s)" % tot)
	near(game.camera.offset.length() + absf(game.camera.rotation), 0.0, 0.001, "the camera is back in place")
	var least := 9999.0
	var n := 0
	for o in before:
		if game.shaker.moved.has(o) and is_instance_valid(o) and game.objects.has(o):
			least = minf(least, float(game.shaker.moved[o]))
			n += 1
	print("  shake: %d objects tracked, least moved %.0f px, merges %d" % [n, least, game.stats.merges])
	ok(n >= 5 and least >= 60.0, "every object gets a good shake (least %.0f px)" % least)
	ok(out == 0, "nothing is thrown out of the bowl (%d frames out)" % out)
	ok(game.stats.lost.is_empty(), "the shake loses nothing down the drain")
	# a wedged plug is knocked loose
	await new_game(false, 0)
	var monster := game.make_object(8, Vector2(540, 1150))
	await seconds(4.0)
	ok(game.water.plug == monster, "the debt monster plugs the drain")
	var y0 := monster.global_position.y
	var top := y0
	game.add_shake(1.0)
	game.request_shake()
	for i in int((tot + 0.2) * 60.0):
		await get_tree().physics_frame
		top = minf(top, monster.global_position.y)
	ok(y0 - top >= 120.0, "the shake knocks the plug loose (lifted %.0f px)" % (y0 - top))

## 1.0.1 cascade rewards: escalating feedback per cascade level, a lone triple is recognised, effects never pause or slow
## the game, the camera kick decays, and there is only ever one combo label.
func test_cascade_feedback() -> void:
	await new_game(false, 0)
	var cc: Dictionary = Cfg.c.cascade
	var levels: Array = cc.levels
	var p := Vector2(540, 1000)
	game._score_merge(2, p, 30.0, false)
	ok(game.hud._combo_text == "" and game.trauma == 0.0, "a single merge: just the existing pop")
	game._score_merge(2, p, 30.0, false)
	ok(game.hud._combo_text == "" and game.haptics_log.is_empty(), "chain 2: only the rising pling")
	var seen_levels := []
	for n in range(3, 10):
		game._score_merge(2, p, 30.0, false)
		for i in levels.size():
			if n == int(levels[i].from):
				seen_levels.append(i)
				ok((levels[i].texts as Array).has(game.hud._combo_text), "chain %d shows a level-%d message (%s)" % [n, i, game.hud._combo_text])
				ok(game.haptics_log[-1] == int(levels[i].haptic_ms), "chain %d buzzes %d ms" % [n, int(levels[i].haptic_ms)])
	ok(seen_levels == [0, 1, 2], "short, large and exceptional cascades are told apart")
	ok(game.hud._combo_n == 9, "the label counts the merges (x%d)" % game.hud._combo_n)
	ok(game.fx.sparks.size() > 60, "an exceptional cascade throws confetti and sparks (%d)" % game.fx.sparks.size())
	ok(game.hud._screen_flash_t < 0.1, "...and flashes the screen")
	ok(game.trauma > 0.5, "...and kicks the camera (trauma %.2f)" % game.trauma)
	ok(not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0), "effects never pause or slow the game")
	await seconds(1.2)
	ok(game.trauma == 0.0 and game.camera.offset.length() < 0.5, "the camera kick is brief (offset %.1f)" % game.camera.offset.length())
	# a lone triple, long after the cascade
	game._sim_t += 10.0
	var n_h := game.haptics_log.size()
	game._score_merge(3, p, 40.0, true)
	ok(game.chain == 1 and (cc.triple.texts as Array).has(game.hud._combo_text), "a lone triple gets its own message (%s)" % game.hud._combo_text)
	ok(game.haptics_log.size() == n_h + 1 and game.trauma > 0.0, "...a buzz and a small kick")

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
	for lv in Cfg.level_count():
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
		var unlocked := false
		for i in 60 * 3:
			await get_tree().physics_frame
			if game.state == Game.State.ROYAL_READY:
				unlocked = true
				break
		ok(unlocked, "%s: merging two tier-8 objects unlocks the ROYAL FLUSH" % Cfg.level_id())
		ok(game.discovered.has(9), "%s: the royal object is discovered" % Cfg.level_id())
		ok(not game.launcher.enabled, "no throwing once the royal flush is unlocked")
		# the level is won: an overflow can no longer steal it
		game.water.frozen = false
		game.water.volume = Cfg.geo.volume_at_level(Cfg.bowl.overflow_y - 80)
		game.water.frozen = true
		await seconds(float(Cfg.c.overflow.grace_time) + 1.0)
		ok(game.state == Game.State.ROYAL_READY and not game.game_over, "%s: overflow cannot end a won level" % Cfg.level_id())
		ok(game.royal_armed, "%s: the royal flush is armed once the cascade settled" % Cfg.level_id())
		ok(game.can_flush(), "the button now fires the royal flush")
		ok(game.request_flush() and game.state == Game.State.ROYAL, "%s: the player triggers the ROYAL FLUSH" % Cfg.level_id())
		ok(not game.launcher.enabled, "no throwing during the royal flush")
		var done := false
		var max_trauma := 0.0
		for i in 60 * 20:
			await get_tree().physics_frame
			max_trauma = maxf(max_trauma, game.trauma)
			if game.state != Game.State.ROYAL:
				done = true
				break
		if game.is_finale():
			ok(max_trauma >= 0.5, "finale: the whole toilet shakes (trauma %.2f)" % max_trauma)
			ok(game.backdrop.earth_gone >= 1.0, "finale: the Earth disappears from the sky")
		ok(done, "%s: the royal flush ends" % Cfg.level_id())
		ok(game.objects.is_empty(), "%s: the royal flush empties the bowl (%d left)" % [Cfg.level_id(), game.objects.size()])
		ok(game.score - before >= Cfg.flush_points(9) * int(Cfg.c.royal.multiplier), "%s: royal flush pays x%d (%d)" % [Cfg.level_id(), Cfg.c.royal.multiplier, game.score - before])
		ok(not game.game_over, "%s: no game over during the royal flush" % Cfg.level_id())
		near(Engine.time_scale, 1.0, 0.001, "slow motion is over")
		ok(game.hud.restart_button.visible, "%s: end panel shown" % Cfg.level_id())
		var score := game.score
		if lv < Cfg.level_count() - 1:
			ok(game.state == Game.State.LEVEL_DONE, "%s: level complete" % Cfg.level_id())
			ok(game.hud.restart_button.text == "NEXT LEVEL", "button says NEXT LEVEL")
			game._on_panel_button()
			ok(Game.carry.get("level", -1) == lv + 1 and Game.carry.get("score", -1) == score, "NEXT LEVEL carries the score into level %d" % (lv + 2))
		else:
			ok(game.state == Game.State.VICTORY, "last level: victory")
			ok(game.is_finale(), "the last location is the finale")
			ok(game.hud.restart_button.text == "NEW GAME", "finale: NEW GAME? (button %s)" % game.hud.restart_button.text)
			ok(game.hud.menu_button.visible, "finale: MENU is offered too")
			game._on_panel_button()
			ok(Game.carry.is_empty(), "NEW GAME starts a fresh run from the first location")
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
		if d != "debug":            # the DEV panel is English on purpose (as in RockRocketLaser)
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
				rest = RegEx.create_from_string('level_text\\("[a-z_]+"\\)').sub(rest, "", true)   # data keys, not text
				ok(literal.search(rest) == null, "untranslated text at %s:%d: %s" % [path.get_file(), i + 1, line.strip_edges()])
	# runtime: a language table is used, formats fill after translating, unknown keys fall back to English
	ok(Loc.system_language() == "en", "desktop/editor language is English")
	Loc.use_table("xx", {"FLUSH": "SPUEL", "CHAIN x%d": "KETTE x%d", "Party Cup": "Partybecher", "THE DORMITORY": "DAS WOHNHEIM"})
	ok(Loc.t("FLUSH") == "SPUEL", "translated string")
	ok(Loc.t("CHAIN x%d") % 3 == "KETTE x3", "format translated before filling")
	ok(Loc.t("NOT A KEY") == "NOT A KEY", "unknown text falls back to English")
	Cfg.set_level(0)
	ok(Loc.t(Cfg.level_def().name) == "DAS WOHNHEIM" and Loc.t(Cfg.tier(1).name) == "Partybecher", "level and object names translate")
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

# ------------------------------------------------------------------ PoC 3: arcade pressure

## Water rises while the drain is obstructed (faster when worse), recovers when it is clear.
func test_rising_water() -> void:
	await new_game()
	await seconds(2.0)
	near(game.water.level_y, Cfg.bowl.rest_level_y, 6.0, "a clear drain holds the rest level")
	ok(game.water.rise_rate() == 0.0, "no rising with a clear drain")
	# one sunk textbook is only a warning; two objects in the drain = partial obstruction
	var book := game.make_object(4, Vector2(540, 1300))
	await seconds(5.0)
	ok(game.water.obstruction > float(Cfg.c.drain.clog_above) and game.water.rise_rate() == 0.0, "a single textbook in the drain is a warning, not yet rising (%.2f)" % game.water.obstruction)
	var book2 := game.make_object(6, Vector2(500, 1150))
	await seconds(5.0)
	var partial: float = game.water.rise_rate()
	ok(game.water.obstruction > float(Cfg.c.water.rise_from), "textbook + laptop obstruct the drain (%.2f)" % game.water.obstruction)
	ok(partial > 0.0, "obstructed drain: the water rises")
	var cap := Cfg.geo.volume_at_level(Cfg.bowl.overflow_y) - Cfg.geo.volume_at_level(Cfg.bowl.rest_level_y)
	print("  partial obstruction %.2f: rise %.0f/s = %.0f s to overflow" % [game.water.obstruction, partial, cap / maxf(partial, 1.0)])
	ok(cap / partial > 120.0, "a partial clog builds up slowly: > 2 min to overflow (%.0f s)" % (cap / partial))
	var l0 := game.water.level_y
	await seconds(3.0)
	ok(game.water.level_y < l0 - 5.0, "the level climbs while obstructed")
	# severe: the university wedged in the funnel
	game.remove_object(book)
	game.remove_object(book2)
	game.make_object(9, Vector2(540, 1200))
	await seconds(5.0)
	var severe: float = game.water.rise_rate()
	print("  severe obstruction %.2f: rise %.0f/s = %.0f s to overflow" % [game.water.obstruction, severe, cap / maxf(severe, 1.0)])
	ok(severe > partial, "a severe clog rises faster than a partial one")
	ok(cap / severe > 45.0 and cap / severe < 110.0, "a severe clog overflows in ~1-1.5 min (%.0f s)" % (cap / severe))
	# clear again: recovery
	for o in game.objects.duplicate():
		game.remove_object(o)
	var high := game.water.level_y
	await seconds(4.0)
	ok(game.water.rise_rate() == 0.0, "rising stops when the drain clears")
	ok(game.water.level_y > high + 10.0, "the water recovers toward rest (%.0f -> %.0f)" % [high, game.water.level_y])

## A clog can clear itself: two textbooks in the drain merge into a floating plushie.
func test_natural_clear() -> void:
	await new_game()
	game.make_object(4, Vector2(540, 1300))
	await seconds(5.0)
	ok(game.water.obstruction > float(Cfg.c.drain.clog_above), "textbook clogs the drain (%.2f)" % game.water.obstruction)
	var b := game.make_object(4, Vector2(560, 1000))
	b.linear_velocity = Vector2(0, 700)
	for i in 60 * 8:
		await get_tree().physics_frame
		if game.stats.clears > 0:
			break
	ok(game.stats.merges >= 1, "the second textbook merges with the plug")
	ok(game.stats.clears >= 1, "the merge cleared the drain (floating plushie): UNCLOGGED")

## The emergency flush saves the bowl; a big plug survives ONE flush (the water drains past it), repeated flushes sacrifice it,
## and every sacrifice drains extra water.
func test_emergency_flush_sacrifice() -> void:
	await new_game(false, 0, true)
	game.charges = 3
	var monster := game.make_object(8, Vector2(540, 1150))   # student debt monster: sinks and plugs the funnel
	await seconds(4.0)
	game.water.volume = Cfg.geo.volume_at_level(900.0)
	await seconds(0.5)
	var high := game.water.level_y
	var cid := monster.get_instance_id()
	ok(game.request_flush(), "emergency flush spends a charge")
	await seconds(float(Cfg.c.flush.duration) + float(Cfg.c.flush.siphon_tail) + 0.3)
	ok(is_instance_id_valid(cid), "one flush does not take the debt monster (big objects resist)")
	ok(game.water.level_y > high + 60.0, "...but the water drained past it (%.0f -> %.0f)" % [high, game.water.level_y])
	var flushes := 1
	while flushes < 3 and is_instance_id_valid(cid):
		while not game.water.can_flush():
			await step(5)
		game.request_flush()
		flushes += 1
		await seconds(0.2)
	await seconds(float(Cfg.c.flush.duration) + float(Cfg.c.flush.siphon_tail) + 0.3)
	ok(not is_instance_id_valid(cid), "repeated panic flushes sacrifice it (%d flushes)" % flushes)
	ok(game.stats.lost.get(8, 0) == 1, "it counts as LOST")
	ok(game.score == 0, "no points for an emergency flush")
	# a sacrifice takes water with it
	var v0 := Cfg.geo.volume_at_level(950.0)
	game.water.volume = v0
	game.water.drain_for_sacrifice(Cfg.tier_area(6))
	ok(v0 - game.water.volume > 50000.0, "a sacrificed laptop drains a lot of water (%.0f px^2)" % (v0 - game.water.volume))

# ------------------------------------------------------------------ title screen + dev mode

func test_title_and_dev_mode() -> void:
	Game.dev = false
	var title: Title = load("res://game/ui/title.tscn").instantiate()
	title.change_scenes = false
	add_child(title)
	await step(5)
	ok(title.logo.texture != null, "title shows the game logo")
	ok(title._bg != null, "title key art loaded")
	for i in 4:
		title.tap_logo()
	ok(not Game.dev, "4 logo taps: no dev mode yet")
	title.tap_logo()
	ok(Game.dev, "5 logo taps: DEV MODE on")
	title.start(2)
	ok(Game.carry.get("level", -1) == 2, "CONTINUE starts at the saved level")
	title.start(0)
	ok(Game.carry.is_empty(), "PLAY starts a fresh run")
	title.queue_free()
	await step(2)
	# dev panel
	await new_game(true, 0)
	ok(game.hud.dev_button.visible, "DEV button visible in dev mode")
	game.open_dev_panel()
	await get_tree().process_frame
	ok(get_tree().paused, "dev panel pauses the game")
	var panel: DevPanel = null
	for c in game.get_children():
		if c is DevPanel:
			panel = c
	ok(panel != null, "dev panel opened")
	if panel:
		panel._set_next(6)
		ok(game.launcher.held != null and game.launcher.held.tier == 6, "dev: choose the next throw")
		panel._toggle_god()
		ok(Game.god_mode, "dev: god mode on")
		panel._royal_now()
		ok(not get_tree().paused, "closing the panel unpauses")
		ok(game.state == Game.State.ROYAL_READY, "dev: royal flush unlocked instantly")
	get_tree().paused = false
	Game.god_mode = false
	Game.dev = false

## PoC 4: intro cards (selected objects, once, never during a cascade, tap / timeout), the grand reveal of the last
## object on every completion, and the reveal card getting flushed with everything else.
func test_showcase() -> void:
	for lv in Cfg.levels:
		var n := 0
		for i in lv.tiers.size():
			var t: Dictionary = lv.tiers[i]
			if t.has("intro"):
				n += 1
				ok(i < lv.tiers.size() - 1, "%s: the last object has a grand reveal, not an intro" % lv.id)
				ok(str(t.intro).length() <= 80, "%s: intro of %s is short (%d chars)" % [lv.id, t.name, str(t.intro).length()])
		ok(n >= 3 and n <= 6, "%s: only selected objects get an intro (%d)" % [lv.id, n])
		ok(str(lv.tiers[-1].get("reveal", "")) != "", "%s: the last object has a reveal line" % lv.id)
	var drain := Vector2(Cfg.geo.cx, Cfg.geo.throat_y)
	# --- a merge discovers the Unopened Textbook (dorm tier 4): queued, shown only after the cascade
	await new_game(false, 0)
	game.intros_enabled = true
	var sc: Showcase = game.showcase
	var a := game.make_object(3, Vector2(470, 900))
	var b := game.make_object(3, Vector2(610, 900))
	a.linear_velocity = Vector2(300, 0)
	b.linear_velocity = Vector2(-300, 0)
	var merged_at := -1.0
	for i in 60 * 3:
		await get_tree().physics_frame
		if game.discovered.has(4):
			merged_at = game._sim_t
			break
	ok(merged_at > 0.0, "two socks make a textbook")
	ok(not sc.active(), "no card in the middle of the cascade")
	var shown_at := -1.0
	for i in 60 * 4:
		await get_tree().physics_frame
		if sc.active():
			shown_at = game._sim_t
			break
	ok(sc.mode == Showcase.Mode.INTRO and sc.tier == 4, "the textbook gets its intro card")
	ok(shown_at - merged_at >= float(Cfg.c.chain.window) - 0.05, "the card waits for the chain window (%.2f s)" % (shown_at - merged_at))
	ok(get_tree().paused, "the intro pauses the game")
	var glyphs := sc._parts.filter(func(p): return p.kind == "glyph").size()
	ok(glyphs == "UNOPENEDTEXTBOOK".length(), "every letter of the name is its own piece (%d)" % glyphs)
	ok(sc._parts.filter(func(p): return p.kind == "pic" and p.tex != null).size() == 1, "the card reuses the object's artwork")
	for i in 20:
		await get_tree().process_frame
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = Vector2(300, 900)
	Input.parse_input_event(tap)
	for i in 3:
		await get_tree().process_frame
	ok(not get_tree().paused, "a tap dismisses the card and resumes the game")
	for i in 40:
		await get_tree().process_frame
	ok(not sc.active(), "the card has flown away")
	ok(not game.wants_intro(4), "each intro is shown once")
	# --- objects without an intro line just get the NEW: text; timeout closes a card by itself
	ok(not game.wants_intro(5), "the plushie has no intro (selective)")
	sc.intro(8)
	var closed := false
	for i in int((float(Cfg.c.showcase.intro_time) + 1.0) * 60.0):
		await get_tree().process_frame
		if not sc.active():
			closed = true
			break
	ok(closed and not get_tree().paused, "an untouched card leaves after ~%.1f s" % float(Cfg.c.showcase.intro_time))
	# --- spawn tiers are known from the start: the sock is introduced when it first sits in the slingshot
	game.dev_set_held(3)
	var sock := false
	for i in 60 * 3:
		await get_tree().physics_frame
		if sc.active():
			sock = sc.tier == 3
			break
	ok(sock, "the Radioactive Sock is introduced in the slingshot")
	sc.dismiss()
	for i in 30:
		await get_tree().process_frame
	# --- the grand reveal (every completion) and the card that gets flushed
	for lv in [0, 2]:
		await new_game(false, lv)
		sc = game.showcase
		game.dev_royal_now()
		for i in 60 * 3:
			await get_tree().physics_frame
			if game.royal_armed:
				break
		ok(sc.mode == Showcase.Mode.REVEAL and sc.tier == Cfg.max_tier(), "%s: the last object gets its grand reveal" % Cfg.level_id())
		ok(not get_tree().paused, "the reveal does not pause (the ROYAL FLUSH button must work)")
		for i in 90:
			await get_tree().process_frame
		ok(sc._revealed, "the drumroll ends with the reveal")
		ok(game.request_flush() and sc.mode == Showcase.Mode.FLUSHING, "%s: ROYAL FLUSH starts flushing the card" % Cfg.level_id())
		var torn := 0
		var swallowed := 0
		var level_while_card := false
		var gone := false
		for i in 60 * 14:
			await get_tree().process_frame
			if sc.active() and (game.state == Game.State.LEVEL_DONE or game.state == Game.State.VICTORY):
				level_while_card = true
			if sc.active():
				torn = maxi(torn, sc._parts.filter(func(p): return p.detached).size())
				for p in sc._parts:
					if p.detached and p.w.k >= 0.99 and sc._piece_xf(p).origin.distance_to(drain) < 4.0:
						swallowed += 1
			elif not gone:
				gone = true
				ok(game.hud._banner == "ROYAL FLUSH!", "the ROYAL FLUSH banner follows once the card is gone")
			if game.state == Game.State.LEVEL_DONE or game.state == Game.State.VICTORY:
				break
		ok(torn >= 40, "%s: the card breaks into its pieces (%d)" % [Cfg.level_id(), torn])
		ok(swallowed > 0, "%s: the pieces end up in the drain" % Cfg.level_id())
		ok(gone and not level_while_card, "%s: the level transition waits for the card" % Cfg.level_id())
		ok(game.state == Game.State.LEVEL_DONE or game.state == Game.State.VICTORY, "%s: then the level is complete" % Cfg.level_id())

## 1.0.1: LEVEL SELECT + progress (unlock after completing the previous location, completion saved, pre-1.0.1 saves keep
## working), the title art covers tall phones, the blue boot splash, the version.
func test_level_select_and_progress() -> void:
	Game.dev = false
	var p0 := Game.progress_of({})
	ok(p0.unlocked == 0 and p0.completed.is_empty(), "fresh save: nothing completed")
	var old := {"best": 1234, "seen": {"dorm": 9}, "unlocked": 2}      # a PoC 3.1 - 4.1 save
	var po := Game.progress_of(old)
	ok(po.completed == ["dorm", "whitehouse"], "old save: the levels before CONTINUE count as completed (%s)" % str(po.completed))
	ok(Game.level_unlocked(old, 2) and not Game.level_unlocked(old, 3), "old save: level 3 open, level 4 locked")
	var new_save := {"unlocked": 0, "completed": ["dorm"]}
	ok(Game.level_unlocked(new_save, 1) and not Game.level_unlocked(new_save, 2), "completing a location unlocks the next one")
	Game.dev = true
	ok(Game.level_unlocked({}, 6), "DEV MODE opens every location")
	Game.dev = false
	# completing a location in the game saves it
	await new_game(false, 3)
	game._level_done()
	ok(game._save.completed.has("area51") and int(game._save.unlocked) == 4, "completing AREA 51 saves it and unlocks THE VATICAN")
	ok(game.state == Game.State.LEVEL_DONE and game.hud.menu_button.visible, "end panel offers MENU")
	ok(not game.hud.flush_button.visible and not game.hud.shake_button.visible, "no gameplay buttons over the end panel")
	await new_game(false, 2)
	Game.dev = true
	game._level_done()
	Game.dev = false
	ok(not game._save.has("completed"), "DEV MODE completions are not saved")
	# the screen itself
	var title: Title = load("res://game/ui/title.tscn").instantiate()
	title.change_scenes = false
	add_child(title)
	await step(3)
	title.save = {"unlocked": 1, "completed": ["dorm"]}
	ok(title.levels_button != null and title.levels_button.visible, "the title has a LEVELS button")
	title.open_levels()
	await step(3)
	var ls := title.level_select
	ok(ls != null and ls.cards.size() == Cfg.level_count(), "one card per location (%d)" % (ls.cards.size() if ls else 0))
	ok(ls.size.x > 500 and ls.size.y > 900, "the level select fills the screen (%s)" % str(ls.size))
	var picked := []
	ls.chosen.connect(func(i): picked.append(i))
	ls._pick(4)
	ok(picked.is_empty(), "a locked location cannot be started")
	ls._pick(1)
	ok(picked == [1], "an unlocked location starts")
	ok(ls.completed(0) and not ls.completed(1), "completed locations are marked")
	ls.back.emit()
	await step(2)
	ok(title.level_select == null, "BACK returns to the menu")
	title.queue_free()
	# title art covers 16:9 .. 21:9 without stretching
	var art := Rect2(0, -320, 1080, 2560)
	for vis in [Rect2(0, 0, 1080, 1920), Rect2(0, -210, 1080, 2340), Rect2(0, -240, 1080, 2400), Rect2(0, -300, 1080, 2520)]:
		near(Title.cover_scale(art, vis), 1.0, 0.001, "the tall title art covers %dx%d unscaled" % [vis.size.x, vis.size.y])
	var tab := Rect2(-180, 0, 1440, 1920)              # a 3:4 tablet: wider than the art
	var k := Title.cover_scale(art, tab)
	var c := Vector2(540, 960)
	var scaled := Rect2(c + (art.position - c) * k, art.size * k)
	ok(scaled.encloses(tab), "on a wide screen the art is enlarged (x%.2f) until it covers" % k)
	# blue boot splash, no border mismatch
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	ok(bg.b > 0.7 and bg.r < 0.3, "boot splash background is blue")
	var img: Image = (load(str(ProjectSettings.get_setting("application/boot_splash/image"))) as Texture2D).get_image()
	var corner := img.get_pixel(2, 2)
	ok(absf(corner.r - bg.r) < 0.03 and absf(corner.g - bg.g) < 0.03 and absf(corner.b - bg.b) < 0.03, "splash canvas = splash background colour (no borders)")
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	ok(clear.is_equal_approx(bg), "clear colour = splash blue (no flash between splash and title)")
	ok(Game.version() == "1.0.1", "version 1.0.1")
	var ep := FileAccess.get_file_as_string("res://export_presets.cfg")
	ok(ep.contains("version/name=\"1.0.1\"") and ep.contains("permissions/vibrate=true"), "Android: version 1.0.1, VIBRATE for haptics")

func test_project_and_export() -> void:
	ok(ProjectSettings.get_setting("display/window/handheld/orientation") == 1, "portrait orientation")
	ok(ProjectSettings.get_setting("display/window/size/viewport_width") == 1080 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1920, "9:16 design size")
	ok(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse") == true, "mouse emulates touch")
	ok(Engine.physics_ticks_per_second == 60, "60 Hz physics")
	# boot splash = Wrong Button Studio logo, never the Godot one
	var splash := str(ProjectSettings.get_setting("application/boot_splash/image", ""))
	ok(splash == "res://assets/processed/ui/splash_wrong_button.png" and ResourceLoader.exists(splash), "boot splash is the studio logo")
	ok(ProjectSettings.get_setting("application/boot_splash/show_image", true) == true, "boot splash image shown")
	ok(ProjectSettings.get_setting("application/boot_splash/fullsize", false) == true, "boot splash scales to fit the screen (never cut)")
	var sp: Texture2D = load(splash)
	ok(sp and absf(sp.get_width() / float(sp.get_height()) - 1080.0 / 1920.0) < 0.01, "splash canvas is portrait 9:16")
	ok(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://game/ui/title.tscn", "the game starts on the title screen")
	var cfg := ConfigFile.new()
	ok(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg present")
	if cfg.get_value("preset.0", "platform", "") == "Android":
		ok(str(cfg.get_value("preset.0.options", "package/unique_name", "")) == "com.wrongbutton.flushroyale", "android package name")
