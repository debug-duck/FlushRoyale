extends Node
## Visual QA: plays a scripted scene in the real game and saves screenshots to tools/dev/out/.
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots.tscn

var game: Game
var frame := 0
var shots := {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/dev/out"))
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.rng.seed = 7
	add_child(game)
	# a messy bowl: a pile of objects of every tier
	var drops := [[1, 300, 600], [1, 760, 560], [2, 420, 500], [3, 640, 450], [2, 820, 380], [4, 520, 300], [5, 380, 200], [1, 700, 150], [6, 560, 0], [3, 250, 100]]
	for d in drops:
		game.make_object(d[0], Vector2(d[1], d[2]))

func _physics_process(_dt: float) -> void:
	frame += 1
	var L := game.launcher
	if frame == 150:
		L.begin_aim(L.launch_pos)
	if frame > 150 and frame < 175:
		L.drag_to(L.launch_pos + Vector2(-180, -260) * (frame - 150) / 25.0)
	if frame == 178:
		_shot("1_aiming")
	if frame == 180:
		L.release()
	if frame == 230:
		_shot("2_after_throw")
	if frame == 300:
		game.request_flush()
	if frame == 340:
		_shot("3_flush")
	if frame == 400:
		_shot("4_flush_late")
	if frame == 600:
		_shot("5_after_flush")
	if frame == 640:
		game.water.volume = Cfg.geo.volume_at_level(760)
	if frame == 700:
		_shot("6_overflowing")
	if frame == 900:
		_shot("7_game_over")
		get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/dev/out/%s.png" % n)
	print("shot ", n, " level=", snappedf(game.water.level_y, 1), " block=", snappedf(game.water.blockage, 0.01), " objs=", game.objects.size(), " score=", game.score)
