class_name Game
extends Node2D
## The whole loop: AIM -> THROW -> MERGE -> GROW -> FLUSH -> SCORE / CLOG -> RECOVER -> ... -> ROYAL FLUSH -> next level.
## Builds the scene in code (camera, background, bowl, water, objects, launcher, fx, hud) and owns the rules:
## spawning, merging (pairs, TRIPLE MERGE, chains), the earned flush (meter -> charges), flush scoring, discovery of a
## level's objects, the ROYAL FLUSH that ends a level, overflow game over and level progression.
## Physics lives in FlushObject / Water / Bowl. All numbers live in data/.

enum State { PLAY, ROYAL, LEVEL_DONE, GAME_OVER, VICTORY }

const SAVE_PATH := "user://best.json"
## Survives reload_current_scene: {level, score} of the run in progress (empty = fresh run from level 1).
static var carry := {}

var geo: BowlGeometry
var bowl: Bowl
var water: Water
var launcher: Launcher
var fx: Fx
var hud: Hud
var objects_root: Node2D
var objects: Array[FlushObject] = []
var state := State.PLAY
var score := 0
var level_start_score := 0
var best := 0
var next_tier := 1
var over_t := 0.0
var game_over := false              # kept for HUD/tests: true in GAME_OVER
var charges := 0
var meter := 0.0
var chain := 0
var chain_mult := 1.0
var discovered := {}                # tier -> true (this level, this run)
var persist := true                 # tests turn this off (no save file)
var reload_enabled := true          # tests turn this off (level changes only set `carry`)
var stats := {"merges": 0, "triples": 0, "flushed": {}, "squeezed": 0, "launches": 0, "flushes": 0, "best_chain": 0, "royal": 0, "reached": {}}
var rng := RandomNumberGenerator.new()
var royal_t := -1.0
var _royal_queue: Array[FlushObject] = []
var _royal_next := 0.0
var _royal_started := false
var _sim_t := 0.0                   # simulation time (chains must not depend on the wall clock)
var _last_merge_t := -99.0
var _pending: Array = []            # [{objs: [a, b(, c)], t: time_left}]
var _textures := {}
var _alarm_t := 0.0
var _save := {}

func _ready() -> void:
	if carry.is_empty():
		Cfg.set_level(0)
	else:
		Cfg.set_level(int(carry.get("level", 0)))
		score = int(carry.get("score", 0))
	level_start_score = score
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
	hud.restart_pressed.connect(_on_panel_button)
	water.squeezed.connect(_on_squeezed)
	water.splashed.connect(func(p, power):
		fx.splash(p, power)
		Sfx.play("splash", randf_range(0.85, 1.15), linear_to_db(clampf(power / 500.0, 0.25, 1.0))))
	for t in range(1, Cfg.max_tier() + 1):   # warm the per-tier geometry + texture caches (no hitch on the first merge)
		FlushObject.create(t, null).free()
		tier_texture(t)
	_save = _load_save()
	best = int(_save.get("best", 0))
	charges = int(Cfg.c.meter.start_charges)
	for t in range(1, Cfg.spawn_weights().size() + 1):
		discovered[t] = true
	next_tier = roll_tier()
	spawn_held()
	hud.banner(Loc.t("LEVEL %d: %s") % [Cfg.level + 1, Loc.t(Cfg.level_def().name)], 2.2)

# ------------------------------------------------------------------ spawning

func roll_tier() -> int:
	var w: Array = Cfg.spawn_weights()
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
	if state != State.PLAY or launcher.held:
		return
	var o := make_object(next_tier, launcher.launch_pos)
	next_tier = roll_tier()
	launcher.hold(o)

func on_launched(_o: FlushObject) -> void:
	stats.launches += 1

# ------------------------------------------------------------------ merging (pair, triple, chain)

## Called from contact signals of BOTH bodies. A pair waits `triple_window` s; a third match touching either joins it.
func try_merge(a: FlushObject, b: FlushObject) -> void:
	if a == b or a.tier != b.tier or a.tier >= Cfg.max_tier() or state != State.PLAY:
		return
	for o in [a, b]:
		if o.held or o.passing or not objects.has(o):
			return
	if a.merging and b.merging:
		return
	if a.merging or b.merging:
		var joined := b if a.merging else a
		var host := a if a.merging else b
		for p in _pending:
			if p.objs.has(host) and p.objs.size() == 2:
				p.objs.append(joined)
				joined.merging = true
				return
		return
	a.merging = true
	b.merging = true
	_pending.append({"objs": [a, b], "t": float(Cfg.c.merge.triple_window)})

func _update_pending(dt: float) -> void:
	for p in _pending.duplicate():
		p.t -= dt
		var alive: Array = p.objs.filter(func(o): return is_instance_valid(o) and objects.has(o))
		if alive.size() < 2:
			for o in alive:
				o.merging = false
			_pending.erase(p)
			continue
		if p.t > 0.0:
			continue
		_pending.erase(p)
		if alive.size() == 2:
			var third := _resting_neighbour(alive)
			if third:
				alive.append(third)
		_merge(alive)

## A matching object already resting against the pair (contact signals only fire on NEW contacts).
func _resting_neighbour(pair: Array) -> FlushObject:
	var pad: float = Cfg.c.merge.triple_pad
	for o in objects:
		if o.tier != pair[0].tier or o.merging or o.held or o.passing or pair.has(o):
			continue
		for q in pair:
			if o.global_position.distance_to(q.global_position) < o.radius() + q.radius() + pad:
				return o
	return null

func _merge(group: Array) -> void:
	var tier: int = group[0].tier + 1
	var mass := 0.0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var spin := 0.0
	for o in group:
		mass += o.mass
		pos += o.global_position * o.mass
		vel += o.linear_velocity * o.mass
		spin += o.angular_velocity
	pos /= mass
	vel = vel / mass * float(Cfg.c.merge.momentum_kept)
	spin /= group.size()
	var rot: float = group[0].rotation
	var triple := group.size() >= 3
	var spread := Vector2.ZERO
	if triple:   # the two results sit apart along the group's long axis
		var far := Vector2.RIGHT
		var best_d := -1.0
		for i in group.size():
			for j in range(i + 1, group.size()):
				var d: Vector2 = group[j].global_position - group[i].global_position
				if d.length() > best_d:
					best_d = d.length()
					far = d.normalized()
		spread = far
	for o in group:
		remove_object(o)
	var made: Array[FlushObject] = []
	for k in (2 if triple else 1):
		var n := FlushObject.create(tier, self)
		var off := spread * (k * 2 - 1) * sqrt(Cfg.tier_area(tier) / PI) * 0.75 if triple else Vector2.ZERO
		n.position = pos + off
		n.rotation = rot
		n.linear_velocity = vel + off.normalized() * 120.0
		n.angular_velocity = spin
		n.start_pop(float(Cfg.c.merge.grow_from))
		objects_root.add_child(n)
		objects.append(n)
		made.append(n)
	_score_merge(tier, pos, made[0].radius(), triple)
	if tier >= Cfg.max_tier():
		start_royal_flush()

func _score_merge(tier: int, pos: Vector2, r: float, triple: bool) -> void:
	var now := _sim_t
	chain = chain + 1 if now - _last_merge_t <= float(Cfg.c.chain.window) else 1
	_last_merge_t = now
	stats.best_chain = maxi(stats.best_chain, chain)
	chain_mult = minf(float(Cfg.c.chain.max_mult), 1.0 + float(Cfg.c.chain.step) * (chain - 1))
	if not stats.reached.has(tier):
		stats.reached[tier] = snappedf(_sim_t, 1.0)       # first time each tier is made (balance probe)
	var pts := int(Cfg.merge_points(tier) * (2 if triple else 1) * chain_mult)
	score += pts
	stats.merges += 1
	var m: Dictionary = Cfg.c.meter
	var gain := (float(m.per_merge) + float(m.tier_bonus) * maxf(0.0, tier - 2)) * chain_mult
	if triple:
		gain += float(m.triple_bonus)
		stats.triples += 1
	add_meter(gain)
	fx.pop(pos, r, Color(Cfg.tier(tier).color))
	fx.text(pos + Vector2(0, -r - 20), Loc.t("+%d") % pts, Color(1, 1, 0.8), 46)
	if triple:
		fx.text(pos + Vector2(0, -r - 80), Loc.t("TRIPLE MERGE!"), Color(0.5, 1.0, 0.9), 62)
		Sfx.play("pop", 0.8)
	elif chain >= 2:
		fx.text(pos + Vector2(0, -r - 80), Loc.t("CHAIN x%d") % chain, Color(1.0, 0.75, 0.3), 50 + mini(chain, 6) * 4)
	if not discovered.has(tier):
		discovered[tier] = true
		hud.reveal(tier)
		if tier < Cfg.max_tier():
			fx.text(pos + Vector2(0, -r - 140), Loc.t("NEW: %s!") % Loc.t(Cfg.tier(tier).name).to_upper(), Color(1, 0.9, 0.4), 58)
		_remember_seen(tier)
	Sfx.play("pop", 1.25 - tier * 0.06)

## Merges fill the meter; a full meter is one more flush charge (capped).
func add_meter(gain: float) -> void:
	var maxc: int = Cfg.c.meter.max_charges
	meter += gain
	while meter >= 1.0:
		if charges < maxc:
			charges += 1
			meter -= 1.0
			hud.flash_flush()
			Sfx.play("plop", 1.5)
		else:
			meter = 1.0
			break

func remove_object(o: FlushObject) -> void:
	objects.erase(o)
	if is_instance_valid(o):
		o.collision_layer = 0
		o.collision_mask = 0
		o.queue_free()

# ------------------------------------------------------------------ flush / royal flush / scoring

func can_flush() -> bool:
	return state == State.PLAY and charges > 0 and water.can_flush()

## Spends one earned charge. Returns true when a flush started.
func request_flush() -> bool:
	if not can_flush():
		if state == State.PLAY and charges == 0:
			hud.flash_flush(true)
		return false
	charges -= 1
	stats.flushes += 1
	return water.start_flush()

func start_royal_flush() -> void:
	if state != State.PLAY:
		return
	state = State.ROYAL
	stats.royal += 1
	royal_t = 0.0
	launcher.enabled = false
	if launcher.held:
		remove_object(launcher.held)
		launcher.held = null
	for p in _pending:
		for o in p.objs:
			if is_instance_valid(o):
				o.merging = false
	_pending.clear()
	Engine.time_scale = float(Cfg.c.royal.slowmo)
	hud.banner(Loc.t("ROYAL FLUSH!"), 3.5, true)
	Sfx.play("flush", 0.7)

func _update_royal(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	royal_t += real_dt
	var r: Dictionary = Cfg.c.royal
	if not _royal_started:
		if royal_t >= float(r.delay):    # the slow-mo moment is over: everything goes
			_royal_started = true
			Engine.time_scale = 1.0
			water.start_flush(float(r.duration))
			_royal_queue.assign(objects.filter(func(o): return not o.held))
			var drain := Vector2(geo.cx, geo.throat_y)
			_royal_queue.sort_custom(func(a, b): return a.global_position.distance_to(drain) < b.global_position.distance_to(drain))
			_royal_next = 0.0
		return
	_royal_next -= real_dt
	while _royal_next <= 0.0 and not _royal_queue.is_empty():
		var o: FlushObject = _royal_queue.pop_front()
		if is_instance_valid(o) and objects.has(o):
			o.start_passing(true)
		_royal_next += float(r.stagger)
	if royal_t > float(r.delay) + float(r.timeout):
		for o in objects.duplicate():
			_flushed(o)              # stragglers still count
	if objects.is_empty() and _royal_queue.is_empty():
		_level_done()

func _flushed(o: FlushObject) -> void:
	var mult: int = int(Cfg.c.royal.multiplier) if state == State.ROYAL else 1
	var pts := Cfg.flush_points(o.tier) * mult
	score += pts
	stats.flushed[o.tier] = stats.flushed.get(o.tier, 0) + 1
	var name_s := Loc.t(o.def.name).to_upper()
	var label := Loc.t("+%d") % pts if o.tier < 4 else Loc.t("%s! +%d") % [name_s, pts]
	if mult > 1:
		label = Loc.t("%s x%d +%d") % [name_s, mult, pts]
	fx.text(Vector2(geo.cx + randf_range(-60, 60), geo.throat_y - 60 - randf_range(0, 80)), label, Color(1, 0.85, 0.3) if mult > 1 else Color(0.6, 1.0, 0.7), 46 + o.tier * 5)
	Sfx.play("gurgle", 1.2 - o.tier * 0.05)
	remove_object(o)

func _on_squeezed(o: FlushObject) -> void:
	stats.squeezed += 1
	if state == State.PLAY:
		fx.text(o.global_position + Vector2(0, -o.radius() - 30), Loc.t("SQUEEEZE!"), Color(1, 0.6, 0.4), 60)
		Sfx.play("squeeze", 1.0)

func _physics_process(dt: float) -> void:
	_sim_t += dt
	var out_y: float = Cfg.bowl.flush_out_y
	for o in objects.duplicate():
		if o.held or o.merging:
			continue
		var p: Vector2 = o.global_position
		if p.y > out_y and absf(p.x - geo.cx) < geo.drain_w:
			_flushed(o)
		elif p.y > 2300.0 or p.x < -400.0 or p.x > 1480.0:
			remove_object(o)        # safety net (never expected)
	_update_pending(dt)
	if state == State.ROYAL:
		_update_royal(dt)
		return
	if state != State.PLAY:
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

# ------------------------------------------------------------------ level flow

func _level_done() -> void:
	state = State.LEVEL_DONE if Cfg.level < Cfg.level_count() - 1 else State.VICTORY
	_record_best()
	hud.show_panel(state)
	Sfx.play("gurgle", 0.6)

func end_game() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	game_over = true
	launcher.enabled = false
	_record_best()
	hud.show_panel(state)
	Sfx.play("gameover")

func _on_panel_button() -> void:
	match state:
		State.LEVEL_DONE:
			next_level()
		State.GAME_OVER:
			retry_level()
		_:
			new_run()

func next_level() -> void:
	carry = {"level": Cfg.level + 1, "score": score}
	_reload()

func retry_level() -> void:
	carry = {"level": Cfg.level, "score": level_start_score}
	_reload()

func new_run() -> void:
	carry = {}
	_reload()

## R key: restart the current level.
func restart() -> void:
	retry_level()

func _reload() -> void:
	Engine.time_scale = 1.0
	if reload_enabled:
		get_tree().reload_current_scene()

func tier_texture(t: int) -> Texture2D:
	var key := "%s:%d" % [Cfg.level_id(), t]
	if not _textures.has(key):
		var path := "res://assets/processed/" + str(Cfg.tier(t).sprite.file)
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]

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
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				if OS.is_debug_build():   # dev helper: drop a tier at the mouse
					make_object(event.keycode - KEY_0, get_global_mouse_position())
			KEY_C:
				if OS.is_debug_build():   # dev helper: +1 flush charge
					add_meter(1.0)
			KEY_L:
				if OS.is_debug_build():   # dev helper: skip to the next level
					if Cfg.level < Cfg.level_count() - 1:
						next_level()

# ------------------------------------------------------------------ save (best score, discovered objects)

func _record_best() -> void:
	if score > best:
		best = score
	_save.best = best
	_write_save()

func _remember_seen(tier: int) -> void:
	var seen: Dictionary = _save.get("seen", {})
	seen[Cfg.level_id()] = maxi(int(seen.get(Cfg.level_id(), 0)), tier)
	_save.seen = seen
	_write_save()

func _load_save() -> Dictionary:
	if not persist or not FileAccess.file_exists(SAVE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d if d is Dictionary else {}

func _write_save() -> void:
	if not persist:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_save))


## The level's background painting plus its edge colours extending past it on taller or wider screens.
class Backdrop extends Node2D:
	var tex: Texture2D
	var top := Color(0.737, 0.92, 0.84)
	var bottom := Color(0.93, 0.59, 0.28)
	func _ready() -> void:
		var path := "res://assets/processed/" + str(Cfg.level_def().background)
		tex = load(path) if ResourceLoader.exists(path) else null
		if tex:
			var img := tex.get_image()
			if img:
				top = img.get_pixel(4, 4)
				bottom = img.get_pixel(4, img.get_height() - 4)
	func _draw() -> void:
		draw_rect(Rect2(-1200, -2000, 3480, 2900), top)
		draw_rect(Rect2(-1200, 1860, 3480, 1500), bottom)
		if tex:
			draw_texture_rect(tex, Rect2(0, 0, 1080, 1920), false)
