extends Node
## Visual QA of the PoC 4 presentation cards: intro cards (entrance + settled), the grand reveal (silhouette + revealed)
## and the reveal card being flushed (shake, tearing, swallowed).
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots_cards.tscn

const INTROS := [[0, 6], [1, 3], [2, 5], [0, 8], [1, 6], [2, 8]]
var game: Game

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/dev/out"))
	for it in INTROS:
		await _new(it[0])
		game.showcase.intro(it[1])
		await _frames(9)
		await _shot("card_%s_%d_in" % [Cfg.level_id(), it[1]])
		await _frames(60)
		await _shot("card_%s_%d" % [Cfg.level_id(), it[1]])
		game.showcase.dismiss()
		await _frames(30)
	for lv in 3:
		await _new(lv)
		game.dev_royal_now()
		while not game.royal_armed:
			await get_tree().physics_frame
		await _frames(30)
		await _shot("reveal_%s_drumroll" % Cfg.level_id())
		await _frames(70)
		await _shot("reveal_%s" % Cfg.level_id())
		game.request_flush()
		await _real(0.9)
		await _shot("reveal_%s_shake" % Cfg.level_id())
		await _real(1.0)
		await _shot("reveal_%s_tear" % Cfg.level_id())
		await _real(1.0)
		await _shot("reveal_%s_suck" % Cfg.level_id())
	get_tree().paused = false
	get_tree().quit()

func _new(level: int) -> void:
	if game:
		get_tree().paused = false
		game.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	Game.carry = {"level": level, "score": 1234}
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.reload_enabled = false
	add_child(game)
	for t in [1, 2, 3, 4, 5, 2, 1, 3]:
		game.make_object(t, Vector2(randf_range(300, 780), randf_range(800, 1000)))
	for i in 90:
		await get_tree().physics_frame

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Real seconds (the royal flush runs in slow motion).
func _real(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/dev/out/%s.png" % n)
	print("shot ", n)
