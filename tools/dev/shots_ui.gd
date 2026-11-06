extends Node
## Visual QA of the UI: title screen (after the logo drop), DEV toggle, the DEV panel over a game, the boot splash image.
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots_ui.tscn

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/dev/out"))
	var title: Title = load("res://game/ui/title.tscn").instantiate()
	title.change_scenes = false
	add_child(title)
	for i in 150:
		await get_tree().process_frame
	await _shot("title")
	for i in 5:
		title.tap_logo()
	for i in 20:
		await get_tree().process_frame
	await _shot("title_dev")
	title.queue_free()
	Game.carry = {"level": 1, "score": 0}
	var game: Game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.reload_enabled = false
	add_child(game)
	for i in 60:
		await get_tree().physics_frame
	Game.dev_stats = true
	for i in 30:
		await get_tree().process_frame
	await _shot("game_dev_stats")
	game.open_dev_panel()
	for i in 10:
		await get_tree().process_frame
	await _shot("dev_panel")
	get_tree().paused = false
	get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/dev/out/%s.png" % n)
	print("shot ", n)
