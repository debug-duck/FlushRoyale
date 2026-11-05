extends Node
## Balance/stability probe: a simple bot plays real games (random aimed throws; flushes when the drain area holds
## something or the water is high) until the toilet floods or the time cap. Prints per-game stats and frame cost.
##   godot --headless --path . --fixed-fps 60 tests/bot_probe.tscn -- --games=3 --cap=400 [--greedy]
var game: Game
var cap := 400.0
var greedy := false

func _ready() -> void:
	var games := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			games = int(a.trim_prefix("--games="))
		elif a.begins_with("--cap="):
			cap = float(a.trim_prefix("--cap="))
		elif a == "--greedy":
			greedy = true
	for g in games:
		await play(g)
	get_tree().quit()

func play(seed: int) -> void:
	if game:
		game.queue_free()
		await get_tree().process_frame
	seed(seed * 7919 + 1)
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.rng.seed = seed + 11
	add_child(game)
	await get_tree().physics_frame
	var t := 0.0
	var max_objs := 0
	var worst_ms := 0.0
	var total_ms := 0.0
	var frames := 0
	var clogged_t := 0.0
	var max_fill := 0.0
	var flushes := 0
	while t < cap and not game.game_over:
		var L := game.launcher
		if L.state == Launcher.State.READY and randf() < 0.012:
			L.begin_aim(L.launch_pos)
			L.drag_to(L.launch_pos + Vector2(randf_range(-260, 260), randf_range(-380, -120)))
			L.release()
		var w := game.water
		var low := 0
		for o in game.objects:
			if o.global_position.y > 1300 and not o.held:
				low += 1
		var want := (low >= 1 and randf() < 0.01) or w.fill_frac() > 0.7 or w.plug != null
		if greedy:
			want = w.fill_frac() > 0.8 or (w.plug != null and w.plug.tier >= 5)
		if want and w.can_flush():
			game.request_flush()
			flushes += 1
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst_ms = maxf(worst_ms, ms)
		total_ms += ms
		frames += 1
		max_objs = maxi(max_objs, game.objects.size())
		if w.blockage > 0.75:
			clogged_t += 1.0 / 60.0
		max_fill = maxf(max_fill, w.fill_frac())
		t += 1.0 / 60.0
	print("game %d: %s at %.0fs score=%d launches=%d merges=%d flushes=%d flushed=%s squeezed=%d max_objs=%d clogged=%.0fs max_fill=%.2f | frame avg %.2f ms worst %.1f ms" % [
		seed, "FLOODED" if game.game_over else "alive", t, game.score, game.stats.launches, game.stats.merges, flushes,
		game.stats.flushed, game.stats.squeezed, max_objs, clogged_t, max_fill, total_ms / frames, worst_ms])
