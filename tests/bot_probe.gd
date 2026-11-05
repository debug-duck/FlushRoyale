extends Node
## Balance/stability probe: a bot plays real runs through the levels and prints per-level stats.
##   godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=1500 [--random]
## The bot aims: it tries a fan of slingshot drags, simulates each flight (same integration as the preview) and picks
## the one that lands closest to an object of the same tier (else the bowl centre). --random throws blindly instead.
## Flush policy: spend a charge when the water is high, the drain is plugged, or charges are full and the bottom is busy.
var game: Game
var cap := 1500.0
var random_aim := false
var throw_every := 1.6
var policy := "smart"   # smart | danger (only when the water is near the line)

func _ready() -> void:
	var games := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.trim_prefix("--games="))
		elif a.begins_with("--cap="):
			cap = float(a.trim_prefix("--cap="))
		elif a == "--random":
			random_aim = true
		elif a.begins_with("--policy="):
			policy = a.trim_prefix("--policy=")
	for g in games:
		await play(g)
	get_tree().quit()

func _new(level: int, score: int, seed_i: int) -> void:
	if game:
		game.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	Game.carry = {"level": level, "score": score}
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.reload_enabled = false
	game.rng.seed = seed_i * 101 + level
	add_child(game)
	await get_tree().physics_frame

func play(seed_i: int) -> void:
	seed(seed_i * 7919 + 1)
	await _new(0, 0, seed_i)
	var t := 0.0
	var level_t := 0.0
	var next_throw := 1.0
	var worst_ms := 0.0
	var total_ms := 0.0
	var frames := 0
	var log := []
	while t < cap:
		var L := game.launcher
		var w := game.water
		if game.state == Game.State.PLAY:
			if L.state == Launcher.State.READY and level_t >= next_throw:
				var drag := _random_drag() if random_aim else _aim()
				L.begin_aim(L.launch_pos)
				L.drag_to(L.launch_pos + drag)
				L.release()
				next_throw = level_t + throw_every * randf_range(0.8, 1.3)
			var low := 0
			for o in game.objects:
				if o.global_position.y > 1350 and not o.held:
					low += 1
			var want := w.fill_frac() > 0.7
			if policy == "smart":   # flush the small clutter when the water rises; never flush into a big plug
				var big_plug: bool = w.plug != null and w.plug.tier >= 5
				want = not big_plug and (w.fill_frac() > 0.45 or game.charges >= int(Cfg.c.meter.max_charges))
			if game.charges > 0 and want:
				game.request_flush()
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst_ms = maxf(worst_ms, ms)
		total_ms += ms
		frames += 1
		t += 1.0 / 60.0
		level_t += 1.0 / 60.0
		if game.state == Game.State.LEVEL_DONE or game.state == Game.State.VICTORY or game.state == Game.State.GAME_OVER:
			log.append("%s %s %.0fs reached %s (merges %d, triples %d, best chain %d, flushes %d, squeezed %d, score %d)" % [
				Cfg.level_id(), {Game.State.LEVEL_DONE: "ROYAL", Game.State.VICTORY: "ROYAL+WIN", Game.State.GAME_OVER: "FLOODED"}[game.state],
				level_t, game.stats.reached, game.stats.merges, game.stats.triples, game.stats.best_chain, game.stats.flushes, game.stats.squeezed, game.score])
			if game.state != Game.State.LEVEL_DONE:
				break
			await _new(Cfg.level + 1, game.score, seed_i)
			level_t = 0.0
			next_throw = 1.0
	if t >= cap:
		log.append("%s CAP at %.0fs reached %s (max tier %d, merges %d, triples %d, flushes %d, flushed %s, score %d)" % [Cfg.level_id(), level_t, game.stats.reached, _max_tier(), game.stats.merges, game.stats.triples, game.stats.flushes, game.stats.flushed, game.score])
	print("game %d: %s | frame avg %.2f ms worst %.1f ms" % [seed_i, " || ".join(log), total_ms / frames, worst_ms])

func _max_tier() -> int:
	var m := 0
	for o in game.objects:
		m = maxi(m, o.tier)
	return m

func _random_drag() -> Vector2:
	return Vector2(randf_range(-260, 260), randf_range(-380, -120))

## Best of a fan of drags: flight endpoint (first object or water hit) closest to a same-tier object.
func _aim() -> Vector2:
	var L := game.launcher
	var held := L.held
	if not held:
		return _random_drag()
	var targets: Array[Vector2] = []
	for o in game.objects:
		if o != held and o.tier == held.tier and not o.merging and not o.passing:
			targets.append(o.global_position)
	if targets.is_empty():
		targets.append(Vector2(Cfg.geo.cx + randf_range(-200, 200), game.water.level_y + 60))
	var g := Vector2(0, ProjectSettings.get_setting("physics/2d/default_gravity"))
	var dt := 1.0 / 60.0
	var best := _random_drag()
	var best_d := INF
	for i in 36:
		var drag := Vector2(randf_range(-320, 320), randf_range(-430, 60))
		var v := L.velocity_for_drag(drag)
		if v == Vector2.ZERO:
			continue
		var p := L.launch_pos
		var d_min := INF
		for k in 110:
			v += g * dt
			p += v * dt
			for tp in targets:
				d_min = minf(d_min, p.distance_to(tp))
			if p.y > game.water.level_y + 40.0 or not Rect2(0, -400, 1080, 2400).has_point(p):
				break
		d_min += randf() * 30.0          # imperfect human aim
		if d_min < best_d:
			best_d = d_min
			best = drag
	return best
