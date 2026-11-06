extends Node
## Visual QA of the TOILET SHAKE bonus: the SHAKE button, the hand reaching down, gripping the rim, shaking, letting go.
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots_shake.tscn

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/dev/out"))
	Game.carry = {"level": 1, "score": 4321}
	var game: Game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.intros_enabled = false
	game.reload_enabled = false
	add_child(game)
	for i in 22:
		game.make_object(1 + randi() % 6, Vector2(randf_range(260, 820), randf_range(520, 900)))
		for k in 4:
			await get_tree().physics_frame
	for i in 240:
		await get_tree().physics_frame
	game.add_shake(1.6)
	await _frames(20)
	await _shot("shake_0_button")
	game.request_shake()
	for at in [["shake_1_reach", 0.3], ["shake_2_grip", 0.6], ["shake_3_shake", 1.15], ["shake_4_shake", 1.6], ["shake_5_lift", 2.55]]:
		await _until(at[1])
		await _shot(at[0])
	get_tree().quit()

var _t0 := -1.0
func _until(s: float) -> void:
	if _t0 < 0.0:
		_t0 = Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - _t0 < s:
		await get_tree().process_frame

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/dev/out/%s.png" % n)
	print("shot ", n)
