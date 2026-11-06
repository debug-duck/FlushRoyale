extends Node
## Balance/stability probe: a bot plays real runs through the levels and prints per-level stats.
##   godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=1500 [--random]
## The bot aims: it tries a fan of slingshot drags, simulates each flight (same integration as the preview) and picks
## the one that lands closest to an object of the same tier (else the bowl centre). --random throws blindly instead.
## Play styles (--policy=...):
##   conservative  aims, throws every ~1.6 s, emergency-flushes when the bowl is 60 % full
##   aggressive    aims, throws every ~1.0 s, flushes only from 85 %
##   flusher       flushes whenever the water is rising and a charge is stored
##   holdout       flushes only when the water is already over the line (overflow countdown running)
## The bot fires the ROYAL FLUSH as soon as it is armed.
var game: Game
var cap := 1500.0
var random_aim := false
var throw_every := 1.6
var policy := "conservative"
var start_level := 0

func _ready() -> void:
	var games := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.trim_prefix("--games="))
		elif a.begins_with("--cap="):
			cap = float(a.trim_prefix("--cap="))
		elif a == "--random":
			random_aim = true
		elif a.begins_with("--start="):
			start_level = int(a.trim_prefix("--start="))
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
	await _new(start_level, 0, seed_i)
	var t := 0.0
	var level_t := 0.0
	var next_throw := 1.0
	var worst_ms := 0.0
	var total_ms := 0.0
	var frames := 0
	var log := []
	var danger_t := 0.0
	var max_fill := 0.0
	throw_every = 1.0 if policy == "aggressive" else 1.6
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
			var want := false
			match policy:
				"conservative":
					want = w.fill_frac() > 0.6
				"aggressive":
					want = w.fill_frac() > 0.85
				"flusher":
					want = w.rise_rate() > 0.0
				"holdout":
					want = game.over_t > 0.0
			if game.charges > 0 and want and w.can_flush():
				game.request_flush()
			if w.rise_rate() > 0.0:
				danger_t += 1.0 / 60.0
			max_fill = maxf(max_fill, w.fill_frac())
		elif game.state == Game.State.ROYAL_READY and game.royal_armed:
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
			log.append("%s %s %.0fs top=%d (merges %d, triples %d, chain %d, flushes %d, lost %s, clears %d, rising %.0f%%, maxfill %.2f, score %d)" % [
				Cfg.level_id(), {Game.State.LEVEL_DONE: "ROYAL", Game.State.VICTORY: "ROYAL+WIN", Game.State.GAME_OVER: "FLOODED"}[game.state],
				level_t, _top(), game.stats.merges, game.stats.triples, game.stats.best_chain, game.stats.flushes, game.stats.lost,
				game.stats.clears, 100.0 * danger_t / maxf(level_t, 1.0), max_fill, game.score])
			danger_t = 0.0
			max_fill = 0.0
			if game.state != Game.State.LEVEL_DONE:
				break
			await _new(Cfg.level + 1, game.score, seed_i)
			level_t = 0.0
			next_throw = 1.0
	if t >= cap:
		log.append("%s CAP at %.0fs top=%d (merges %d, flushes %d, lost %s, rising %.0f%%, maxfill %.2f, score %d)" % [Cfg.level_id(), level_t, _top(), game.stats.merges, game.stats.flushes, game.stats.lost, 100.0 * danger_t / maxf(level_t, 1.0), max_fill, game.score])
	print("game %d: %s | frame avg %.2f ms worst %.1f ms" % [seed_i, " || ".join(log), total_ms / frames, worst_ms])

func _top() -> int:
	var m := 0
	for k in game.stats.reached:
		m = maxi(m, int(k))
	return m

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
	var clog: Array[Vector2] = []      # precision throw: while the water rises, a match sitting in the drain comes first
	for o in game.objects:
		if o != held and o.tier == held.tier and not o.merging and not o.passing:
			targets.append(o.global_position)
			if o.global_position.y > Cfg.geo.throat_y - 260.0:
				clog.append(o.global_position)
	if game.water.rise_rate() > 0.0 and not clog.is_empty():
		targets = clog
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
