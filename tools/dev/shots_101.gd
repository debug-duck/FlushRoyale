extends Node
## Visual QA of 1.0.1: title (any aspect: run with different --resolution and `-- --only=title`), LEVEL SELECT, every
## new location with its nine objects, a big cascade, the Earth finale.
##   xvfb-run -a -s "-screen 0 1280x1400x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots_101.tscn
##   ... --resolution 540x1170 tools/dev/shots_101.tscn -- --only=title      (19.5:9)   540x1200 = 20:9

var game: Game
var only := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/dev/out"))
	var vs := get_viewport().get_visible_rect().size
	var tag := "%dx%d" % [int(vs.x), int(vs.y)]
	var title: Title = load("res://game/ui/title.tscn").instantiate()
	title.change_scenes = false
	title.save = {}
	add_child(title)
	await _frames(150)
	await _shot("t101_title_" + tag)
	if only == "title":
		get_tree().quit()
		return
	title.save = {"unlocked": 4, "completed": ["dorm", "whitehouse", "royal"], "seen": {"dorm": 9, "whitehouse": 9, "royal": 9, "area51": 5}}
	title.open_levels()
	await _frames(30)
	await _shot("t101_levels")
	title.level_select._scroll.scroll_vertical = 2000
	await _frames(10)
	await _shot("t101_levels_end")
	title.queue_free()
	for lv in [3, 4, 5, 6]:
		await _new(lv)
		for t in range(1, 10):
			game.make_object(t, Vector2(200 + (t % 3) * 330, 500 + (t / 3) * 120))
			await _frames(6)
		await _physics(180)
		await _shot("t101_level_%s" % Cfg.level_id())
	# a big cascade
	await _new(4)
	for n in 9:
		game._score_merge(2 + (n % 5), Vector2(540, 1050), 50.0, n == 4)
	await _frames(3)
	await _shot("t101_cascade")
	# the finale
	await _new(6)
	game.dev_royal_now()
	while not game.royal_armed:
		await get_tree().physics_frame
	await _real(1.6)
	await _shot("t101_finale_reveal")
	game.request_flush()
	await _real(3.5)
	await _shot("t101_finale_flush")
	while game.state == Game.State.ROYAL:
		await get_tree().physics_frame
	await _real(3.0)
	await _shot("t101_finale_end")
	get_tree().quit()

func _new(level: int) -> void:
	if game:
		game.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	Game.carry = {"level": level, "score": 31337}
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.intros_enabled = false
	game.reload_enabled = false
	add_child(game)
	await _physics(30)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _real(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/dev/out/%s.png" % n)
	print("shot ", n)
