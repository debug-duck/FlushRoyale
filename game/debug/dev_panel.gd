class_name DevPanel
extends CanvasLayer
## DEV MODE panel (unlocked by tapping the title logo 5x, like RockRocketLaser): touch-sized cheat buttons to test the levels.
## Pauses the game while open. Works in every build (phones too); nothing is saved.

var game: Game
var _root: Control
var _toggles := {}          # name -> Button (labels refreshed)

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var vs := _root.get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.1, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var title := _label("DEV MODE", 56, Color("ffcf4a"))
	title.position = Vector2(0, 24)
	title.size = Vector2(vs.x, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	var x0 := 36.0
	var gap := 16.0
	var bw := (vs.x - x0 * 2 - gap) / 2.0
	var bh := 84.0
	var y := 110.0
	var rows := [
		[["god", "", Color("3fa66b"), _toggle_god], ["", "RESTART LEVEL", Color("7a5fc0"), func(): _jump(Cfg.level)]],
		[["", "<<  PREV LEVEL", Color("7a5fc0"), func(): _jump(Cfg.level - 1)], ["", "NEXT LEVEL  >>", Color("e8642c"), func(): _jump(Cfg.level + 1)]],
		[["", "+1 FLUSH CHARGE", Color("2c7ac0"), func(): game.add_meter(1.0)], ["", "ROYAL FLUSH NOW", Color("d4a017"), _royal_now]],
		[["", "+1 TOILET SHAKE", Color("b0632c"), func(): game.add_shake(1.0)], ["", "SHAKE NOW", Color("b0632c"), _shake_now]],
		[["", "DRAIN WATER", Color("2c9ac0"), _drain], ["", "RAISE WATER", Color("c0392b"), _raise]],
		[["freeze", "", Color("2c7ac0"), _toggle_freeze], ["", "CLEAR BOWL", Color("c0392b"), _clear_bowl]],
		[["slow", "", Color("2c7ac0"), _toggle_slow], ["stats", "", Color("2c7ac0"), _toggle_stats]],
		[["", "SHOW AN INTRO CARD", Color("8a4fc0"), _show_intro], ["", "REPLAY ALL INTROS", Color("8a4fc0"), _replay_intros]],
		[["coll", "", Color("555a70"), _toggle_collision], ["", "CLOSE", Color("555060"), close]],
	]
	for row in rows:
		for i in row.size():
			var r: Array = row[i]
			var b := _btn(r[1], Vector2(x0 + i * (bw + gap), y), Vector2(bw, bh), r[2], r[3])
			if r[0] != "":
				_toggles[r[0]] = b
		y += bh + 12
	y += 8
	y = _tier_row("NEXT THROW:", y, func(t): _set_next(t))
	y = _tier_row("DROP IN BOWL:", y, func(t): _drop(t))
	var hdr := _label("JUMP TO LEVEL", 32, Color("ffe9b0"))
	hdr.position = Vector2(x0, y + 4)
	_root.add_child(hdr)
	y += 52
	for i in Cfg.level_count():
		var here := i == Cfg.level
		var b := _btn("%d  %s%s" % [i + 1, Cfg.levels[i].name, "   <" if here else ""], Vector2(x0, y), Vector2(vs.x - x0 * 2, 72),
			Color("e8642c") if here else Color("3a5a8a"), func(): _jump(i))
		b.add_theme_font_size_override("font_size", 30)
		y += 82
	_refresh()

## A row of 9 small buttons with the level's object icons; f(tier) on press.
func _tier_row(caption: String, y: float, f: Callable) -> float:
	var vs := _root.get_viewport_rect().size
	var l := _label(caption, 30, Color("ffe9b0"))
	l.position = Vector2(36, y)
	_root.add_child(l)
	y += 44
	var n := Cfg.max_tier()
	var w := (vs.x - 72.0 - (n - 1) * 8.0) / n
	for t in range(1, n + 1):
		var b := _btn(str(t), Vector2(36 + (t - 1) * (w + 8.0), y), Vector2(w, w), Color("2a3550"), func(): f.call(t))
		var tex: Texture2D = game.tier_texture(t)
		if tex:
			b.icon = tex
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.text = ""
	return y + w + 16

func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("101018"))
	l.add_theme_constant_override("outline_size", 10)
	return l

func _btn(text: String, pos: Vector2, size: Vector2, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.25) if st == "pressed" else col
		sb.set_corner_radius_all(18)
		sb.set_border_width_all(4)
		sb.border_color = Color("101018")
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(func():
		cb.call()
		_refresh())
	_root.add_child(b)
	return b

func _refresh() -> void:
	if not is_instance_valid(game):
		return
	var on := func(name: String, v: bool) -> String: return "%s: %s" % [name, "ON" if v else "OFF"]
	_toggles.god.text = on.call("GOD MODE", Game.god_mode)
	_toggles.freeze.text = on.call("FREEZE WATER", game.water.frozen)
	_toggles.slow.text = on.call("SLOW-MO", Game.dev_slowmo)
	_toggles.stats.text = on.call("STATS", Game.dev_stats)
	_toggles.coll.text = on.call("COLLISION", game.bowl.debug_draw)

func close() -> void:
	get_tree().paused = false
	queue_free()

func _toggle_god() -> void:
	Game.god_mode = not Game.god_mode

func _toggle_freeze() -> void:
	game.water.frozen = not game.water.frozen

func _toggle_slow() -> void:
	Game.dev_slowmo = not Game.dev_slowmo
	Engine.time_scale = 0.3 if Game.dev_slowmo else 1.0

func _toggle_stats() -> void:
	Game.dev_stats = not Game.dev_stats

func _toggle_collision() -> void:
	game.bowl.debug_draw = not game.bowl.debug_draw
	game.bowl.queue_redraw()

func _drain() -> void:
	game.water.volume = game.water.rest_volume
	game.over_t = 0.0

func _raise() -> void:
	game.water.volume += 80000.0

func _clear_bowl() -> void:
	for o in game.objects.duplicate():
		if not o.held:
			game.remove_object(o)

func _set_next(t: int) -> void:
	game.dev_set_held(t)

func _drop(t: int) -> void:
	game.make_object(t, Vector2(randf_range(380, 700), 650))

## Cycle through this level's intro cards (and the grand reveal card text of the last tier is seen via ROYAL FLUSH NOW).
static var _intro_i := -1
func _show_intro() -> void:
	var tiers: Array[int] = []
	for t in range(1, Cfg.max_tier()):
		if str(Cfg.tier(t).get("intro", "")) != "":
			tiers.append(t)
	if tiers.is_empty():
		return
	_intro_i = (_intro_i + 1) % tiers.size()
	close()
	game.showcase.intro(tiers[_intro_i])

func _replay_intros() -> void:
	game.dev_reset_intros()
	close()

func _shake_now() -> void:
	close()
	if game.shake_charges == 0:
		game.add_shake(1.0)
	game.request_shake()

func _royal_now() -> void:
	close()
	game.dev_royal_now()

func _jump(i: int) -> void:
	if i < 0 or i >= Cfg.level_count():
		return
	get_tree().paused = false
	Game.carry = {"level": i, "score": game.score}
	game._reload()
