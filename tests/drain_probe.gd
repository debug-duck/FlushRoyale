extends Node
## Drain/flush probe: drops one object of each requested tier into an empty bowl, flushes repeatedly and prints
## position, width, blockage, plug and squeeze every 0.5 s.   godot --headless --path . --fixed-fps 60 tests/drain_probe.tscn -- --tiers=1,4,6
var game: Game
var level := 0
var drop_x := 560.0

func _ready() -> void:
	var tiers := [1, 4, 6]
	level = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--x="):
			drop_x = float(a.trim_prefix("--x="))
		if a.begins_with("--level="):
			level = int(a.trim_prefix("--level="))
		if a.begins_with("--tiers="):
			tiers = Array(a.trim_prefix("--tiers=").split(",")).map(func(x): return int(x))
	for t in tiers:
		await run(t)
	get_tree().quit()

func run(t: int) -> void:
	if game:
		game.queue_free()
		await get_tree().process_frame
	Game.carry = {"level": level, "score": 0}
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.intros_enabled = false
	game.reload_enabled = false
	game.charges = 99
	add_child(game)
	await get_tree().physics_frame
	game.launcher.enabled = false
	game.remove_object(game.launcher.held)
	game.launcher.held = null
	var o := game.make_object(t, Vector2(drop_x + (t % 2) * 40.0 if drop_x < 0 else drop_x, 1000))
	print("=== %s tier %d  area %.0f  mass %.1f" % [Cfg.level_id(), t, o.area, o.mass])
	for i in 60:
		if i % 9 == 4 and game.water.can_flush():
			game.request_flush()
		for f in 30:
			await get_tree().physics_frame
		if not is_instance_valid(o) or not game.objects.has(o):
			print("  t=%.1f FLUSHED  score=%d" % [i * 0.5 + 0.5, game.score])
			return
		var w := game.water
		print("  t=%4.1f pos=(%4.0f,%4.0f) rot=%5.0f ext=%4.0f v=%4.0f sub=%.2f | lvl=%4.0f blk=%.2f plug=%s sq=%.2f str=%.2f pass=%s" % [
			i * 0.5 + 0.5, o.global_position.x, o.global_position.y, rad_to_deg(o.rotation), o.extent_x(), o.linear_velocity.length(),
			o.sub_frac, w.level_y, w.blockage, w.plug == o, o.squeeze, w.strength(), o.passing])
	print("  NOT FLUSHED")
