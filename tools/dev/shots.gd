extends Node
## Visual QA: scripted scenes in the real game, screenshots to tools/dev/out/.
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 --resolution 540x960 tools/dev/shots.tscn
## Per level: a pile of every tier; level 1 also: aiming, a triple merge, a flush, the ROYAL FLUSH and the level panel.

var game: Game

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/dev/out"))
	for lv in Cfg.level_count():
		await _level_pile(lv)
	await _danger()
	await _royal()
	get_tree().quit()

func _new_game(level: int) -> void:
	if game:
		game.queue_free()
		await get_tree().process_frame
	Game.carry = {"level": level, "score": 0}
	game = load("res://game/main.tscn").instantiate()
	game.persist = false
	game.intros_enabled = false
	game.rng.seed = 7
	add_child(game)
	await get_tree().physics_frame

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _level_pile(level: int) -> void:
	await _new_game(level)
	var spots := [[1, 300, 600], [2, 760, 560], [3, 420, 450], [4, 650, 420], [5, 330, 250], [6, 760, 200], [7, 520, 0], [8, 540, -350], [1, 860, 300], [2, 240, 100]]
	for d in spots:
		game.make_object(d[0], Vector2(d[1], d[2]))
		await _frames(8)
	for t in range(1, 9):
		game.discovered[t] = true
	await _frames(200)
	var L := game.launcher
	L.begin_aim(L.launch_pos)
	L.drag_to(L.launch_pos + Vector2(-170, -250))
	await _frames(3)
	await _shot("level%d_pile" % (level + 1))
	L.release()

## Danger: a clogged drain, the water rising toward the line, the red edge glow and rising arrows.
func _danger() -> void:
	await _new_game(1)
	for t in [6, 4, 2, 2, 5]:
		game.make_object(t, Vector2(500 + randf() * 80, 1000))
		await _frames(20)
	await _frames(200)
	game.water.volume = Cfg.geo.volume_at_level(930.0)
	await _frames(90)
	await _shot("danger")
	game.add_meter(1.0)
	game.request_flush()
	await _frames(60)
	await _shot("emergency_flush")

func _royal() -> void:
	await _new_game(0)
	# triple merge: three shampoos dropped together
	for i in 3:
		game.make_object(3, Vector2(430 + i * 110, 900))
	await _frames(40)
	await _shot("triple_merge")
	await _frames(60)
	game.add_meter(2.0)
	game.request_flush()
	await _frames(50)
	await _shot("flush_charges")
	await _frames(150)
	# two tier-8 objects collide -> tier 9 -> ROYAL FLUSH
	for t in [1, 2, 3, 4, 5, 2, 1]:
		game.make_object(t, Vector2(300 + randf() * 480, 700 + randf() * 300))
	await _frames(120)
	game.make_object(8, Vector2(380, 500))
	var b := game.make_object(8, Vector2(700, 300))
	b.linear_velocity = Vector2(-500, 300)
	await _frames(60)
	await _shot("royal_unlocked")
	for i in 300:
		await get_tree().physics_frame
		if game.royal_armed:
			break
	await _frames(30)
	await _shot("royal_ready")
	game.request_flush()
	for i in 120:
		await get_tree().physics_frame
		if game._royal_started:
			break
	await _frames(70)
	await _shot("royal_pour")
	for i in 900:
		await get_tree().physics_frame
		if game.state != Game.State.ROYAL:
			break
	await _frames(40)
	await _shot("level_done")

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/dev/out/%s.png" % n)
	print("shot ", n, " state=", game.state, " objs=", game.objects.size(), " score=", game.score, " charges=", game.charges, " meter=", snappedf(game.meter, 0.01))
