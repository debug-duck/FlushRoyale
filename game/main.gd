class_name Game
extends Node2D
## The whole PoC loop: AIM -> THROW -> MERGE -> GROW -> FLUSH -> SCORE / CLOG -> RECOVER.
## Builds the scene in code (camera, background, bowl, water, objects, launcher, fx, hud), owns score, spawning,
## merging, flush scoring and the overflow game over. Physics lives in FlushObject / Water / Bowl.

const BEST_PATH := "user://best.json"

var geo: BowlGeometry
var bowl: Bowl
var water: Water
var launcher: Launcher
var fx: Fx
var hud: Hud
var objects_root: Node2D
var objects: Array[FlushObject] = []
var score := 0
var best := 0
var next_tier := 1
var over_t := 0.0
var game_over := false
var persist := true                 # tests turn this off (no best-score file)
var stats := {"merges": 0, "flushed": {}, "squeezed": 0, "launches": 0}
var rng := RandomNumberGenerator.new()
var _textures := {}
var _alarm_t := 0.0

func _ready() -> void:
	geo = Cfg.geo
	var cam := Camera2D.new()
	cam.position = Vector2(540, 960)
	add_child(cam)
	cam.make_current()
	var backdrop := Backdrop.new()
	backdrop.z_index = -10
	add_child(backdrop)
	bowl = Bowl.new()
	bowl.name = "Bowl"
	add_child(bowl)
	objects_root = Node2D.new()
	objects_root.name = "Objects"
	add_child(objects_root)
	water = Water.new()
	water.name = "Water"
	water.bowl = bowl
	water.game = self
	water.z_index = 5
	add_child(water)
	launcher = Launcher.new()
	launcher.name = "Launcher"
	launcher.game = self
	launcher.z_index = 6
	add_child(launcher)
	fx = Fx.new()
	fx.z_index = 8
	add_child(fx)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.flush_pressed.connect(request_flush)
	hud.restart_pressed.connect(restart)
	water.squeezed.connect(_on_squeezed)
	water.splashed.connect(func(p, power):
		fx.splash(p, power)
		Sfx.play("splash", randf_range(0.85, 1.15), linear_to_db(clampf(power / 500.0, 0.25, 1.0))))
	for t in range(1, Cfg.max_tier() + 1):   # warm the per-tier geometry + texture caches (no hitch on the first merge)
		FlushObject.create(t, null).free()
		tier_texture(t)
	best = _load_best()
	next_tier = roll_tier()
	spawn_held()

# ------------------------------------------------------------------ spawning / merging

func roll_tier() -> int:
	var w: Array = Cfg.c.spawn_weights
	var total := 0.0
	for x in w:
		total += float(x)
	var r := rng.randf() * total
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			return i + 1
	return 1

func make_object(tier: int, pos: Vector2) -> FlushObject:
	var o := FlushObject.create(tier, self)
	o.position = pos
	objects_root.add_child(o)
	objects.append(o)
	return o

func spawn_held() -> void:
	if game_over or launcher.held:
		return
	var o := make_object(next_tier, launcher.launch_pos)
	next_tier = roll_tier()
	launcher.hold(o)

func on_launched(_o: FlushObject) -> void:
	stats.launches += 1

## Called from contact signals of BOTH bodies; the flags make sure a pair merges exactly once.
func try_merge(a: FlushObject, b: FlushObject) -> void:
	if a == b or a.tier != b.tier or a.tier >= Cfg.max_tier():
		return
	for o in [a, b]:
		if o.merging or o.held or o.passing or not objects.has(o):
			return
	a.merging = true
	b.merging = true
	_merge.call_deferred(a, b)

func _merge(a: FlushObject, b: FlushObject) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	var ma := a.mass
	var mb := b.mass
	var pos := (a.global_position * ma + b.global_position * mb) / (ma + mb)
	var vel := (a.linear_velocity * ma + b.linear_velocity * mb) / (ma + mb) * float(Cfg.c.merge.momentum_kept)
	var spin := (a.angular_velocity + b.angular_velocity) * 0.5
	var rot := a.rotation if ma >= mb else b.rotation
	var tier := a.tier + 1
	remove_object(a)
	remove_object(b)
	var n := FlushObject.create(tier, self)
	n.position = pos
	n.rotation = rot
	n.linear_velocity = vel
	n.angular_velocity = spin
	n.start_pop(float(Cfg.c.merge.grow_from))
	objects_root.add_child(n)
	objects.append(n)
	var pts := Cfg.merge_points(tier)
	score += pts
	stats.merges += 1
	fx.pop(pos, n.radius(), Color(Cfg.tier(tier).color))
	fx.text(pos + Vector2(0, -n.radius() - 20), "+%d" % pts, Color(1, 1, 0.8), 46)
	if tier == Cfg.max_tier():
		fx.text(pos + Vector2(0, -n.radius() - 90), str(Cfg.tier(tier).name).to_upper() + "!", Color(1, 0.85, 0.3), 64)
	Sfx.play("pop", 1.25 - tier * 0.08)

func remove_object(o: FlushObject) -> void:
	objects.erase(o)
	if is_instance_valid(o):
		o.collision_layer = 0
		o.collision_mask = 0
		o.queue_free()

# ------------------------------------------------------------------ flush / scoring / overflow

func request_flush() -> void:
	if not game_over:
		water.start_flush()

func _on_squeezed(o: FlushObject) -> void:
	stats.squeezed += 1
	fx.text(o.global_position + Vector2(0, -o.radius() - 30), "SQUEEEZE!", Color(1, 0.6, 0.4), 60)
	Sfx.play("squeeze", 1.0)

func _flushed(o: FlushObject) -> void:
	var pts := Cfg.flush_points(o.tier)
	score += pts
	stats.flushed[o.tier] = stats.flushed.get(o.tier, 0) + 1
	var label := "+%d" % pts if o.tier < 4 else "%s! +%d" % [str(o.def.name).to_upper(), pts]
	fx.text(Vector2(geo.cx, geo.throat_y - 60), label, Color(0.6, 1.0, 0.7), 50 + o.tier * 6)
	Sfx.play("gurgle", 1.2 - o.tier * 0.06)
	remove_object(o)

func _physics_process(dt: float) -> void:
	var out_y: float = Cfg.bowl.flush_out_y
	for o in objects.duplicate():
		if o.held or o.merging:
			continue
		var p: Vector2 = o.global_position
		if p.y > out_y and absf(p.x - geo.cx) < geo.drain_w:
			_flushed(o)
		elif p.y > 2300.0 or p.x < -400.0 or p.x > 1480.0:
			remove_object(o)        # safety net (never expected)
	if game_over:
		return
	if water.level_y <= water.overflow_y:
		over_t += dt
		_alarm_t -= dt
		if _alarm_t <= 0.0:
			_alarm_t = 0.5
			Sfx.play("alarm")
		if over_t >= float(Cfg.c.overflow.grace_time):
			end_game()
	else:
		over_t = maxf(0.0, over_t - dt * 1.5)

func end_game() -> void:
	if game_over:
		return
	game_over = true
	launcher.enabled = false
	if score > best:
		best = score
		_save_best()
	hud.show_game_over()
	Sfx.play("gameover")

func restart() -> void:
	get_tree().reload_current_scene()

func tier_texture(t: int) -> Texture2D:
	if not _textures.has(t):
		var path := "res://assets/processed/objects/" + str(Cfg.tier(t).sprite.file)
		_textures[t] = load(path) if ResourceLoader.exists(path) else null
	return _textures[t]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_F:
				request_flush()
			KEY_R:
				restart()
			KEY_F1:
				bowl.debug_draw = not bowl.debug_draw
				bowl.queue_redraw()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				if OS.is_debug_build():   # dev helper: drop a tier at the mouse
					make_object(event.keycode - KEY_0, get_global_mouse_position())

func _load_best() -> int:
	if not persist or not FileAccess.file_exists(BEST_PATH):
		return 0
	var d = JSON.parse_string(FileAccess.get_file_as_string(BEST_PATH))
	return int(d.get("best", 0)) if d is Dictionary else 0

func _save_best() -> void:
	if not persist:
		return
	var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"best": best}))


## Background painting plus wall/floor colour extending past it on taller or wider screens.
class Backdrop extends Node2D:
	var tex: Texture2D
	func _ready() -> void:
		var path := "res://assets/processed/background.jpg"
		tex = load(path) if ResourceLoader.exists(path) else null
	func _draw() -> void:
		draw_rect(Rect2(-1200, -2000, 3480, 2900), Color(0.737, 0.92, 0.84))
		draw_rect(Rect2(-1200, 1860, 3480, 1500), Color(0.93, 0.59, 0.28))
		if tex:
			draw_texture_rect(tex, Rect2(0, 0, 1080, 1920), false)
