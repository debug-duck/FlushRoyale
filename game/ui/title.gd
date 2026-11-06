class_name Title
extends Node2D
## Title screen: key art, the game logo (drops in, bobs, squashes when tapped), objects from every location spiralling into
## the toilet's whirlpool, PLAY / CONTINUE buttons and the best score. Tapping the logo 5x (taps < 1.2 s apart) toggles
## DEV MODE (Game.dev, not saved), as in RockRocketLaser.
## 1.0.1: LEVELS opens the LEVEL SELECT (game/ui/level_select.gd). The key art is a 1080x2560 outpainted version of the
## original (which sits at y 0..1920 of the design space): it covers tall phones (up to 21:9) without stretching, and
## cover_scale() enlarges it around the composition's centre for anything taller or wider. UI respects the safe area.

const GAME_SCENE := "res://game/main.tscn"
const DRAIN := Vector2(540, 1395)          # whirlpool centre in the key art
const STUDIO := "WRONG BUTTON STUDIO"      # a name: never translated
const DEV_LABEL := "DEV"
const STUDIO_LINE := "%s  v%s"             # studio name + version: not translated

var change_scenes := true                  # tests turn this off
var logo: Sprite2D
var ui: CanvasLayer
var play_button: Button
var continue_button: Button
var levels_button: Button
var level_select: LevelSelect
var save := {}
var _t := 0.0
var _logo_scale := 1.0
var _squash := 0.0
var _taps := 0
var _last_tap := -9.0
var _toast := ""
var _toast_t := 9.0
var _flyers: Array = []
var _spawn_t := 0.0
var _textures: Array[Texture2D] = []
var _font: Font
var _bg: Texture2D                         # held here: a texture loaded inside _draw() is freed before it renders
var _bg_rect := Rect2(0, 0, 1080, 1920)    # where the key art goes in design space (tall art: Rect2(0, -320, 1080, 2560))
const BRAND_BLUE := Color(0.1176, 0.3922, 0.8235)   # = boot splash / clear colour

func _ready() -> void:
	Engine.time_scale = 1.0
	_font = ThemeDB.fallback_font
	var cam := Camera2D.new()
	cam.position = Vector2(540, 960)
	add_child(cam)
	cam.make_current()
	save = _load_save()
	var tall := "res://assets/processed/ui/title_bg_tall.jpg"
	var bgp := "res://assets/processed/ui/title_bg.jpg"
	if ResourceLoader.exists(tall):
		_bg = load(tall)
		_bg_rect = Rect2(0, -320, 1080, 2560)
	elif ResourceLoader.exists(bgp):
		_bg = load(bgp)
	for lv in Cfg.levels:                  # decorative flyers: every object of every location
		for t in lv.tiers:
			var p := "res://assets/processed/" + str(t.sprite)
			if ResourceLoader.exists(p):
				_textures.append(load(p))
	var lp := "res://assets/processed/ui/game_logo.png"
	logo = Sprite2D.new()
	if ResourceLoader.exists(lp):
		logo.texture = load(lp)
		_logo_scale = 660.0 / logo.texture.get_width()
	logo.position = Vector2(540, 470)
	logo.z_index = 10
	add_child(logo)
	_build_ui()

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	Hud.fit_safe_area(root)
	play_button = _button(root, Loc.t("PLAY"), Color(0.98, 0.72, 0.12), 84, Rect2(-300, -640, 600, 170))
	play_button.pressed.connect(func(): start(0))
	var unlocked := int(Game.progress_of(save).unlocked)
	continue_button = _button(root, Loc.t("CONTINUE: LEVEL %d") % (unlocked + 1), Color(0.2, 0.62, 1.0), 48, Rect2(-300, -445, 600, 120))
	continue_button.visible = unlocked > 0 and unlocked < Cfg.level_count()
	continue_button.pressed.connect(func(): start(unlocked))
	levels_button = _button(root, Loc.t("LEVELS"), Color(0.55, 0.3, 0.85), 52, Rect2(-300, -300, 600, 120))
	levels_button.pressed.connect(open_levels)
	root.draw.connect(func(): _draw_ui(root))
	set_meta("ui_root", root)

func _button(root: Control, text: String, col: Color, size: int, r: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.18))
	b.add_theme_constant_override("outline_size", 14)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.2) if st == "pressed" else col
		sb.set_corner_radius_all(48)
		sb.set_border_width_all(9)
		sb.border_color = Color(0.1, 0.1, 0.18)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 8)
		b.add_theme_stylebox_override(st, sb)
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = r.position.x
	b.offset_top = r.position.y
	b.offset_right = r.end.x
	b.offset_bottom = r.end.y
	root.add_child(b)
	return b

## LEVEL SELECT on top of the title (the title keeps animating behind it).
func open_levels() -> void:
	if level_select:
		return
	level_select = LevelSelect.new()
	level_select.save = save
	level_select.chosen.connect(start)
	level_select.back.connect(close_levels)
	ui.add_child(level_select)
	Hud.fit_safe_area(level_select)
	Sfx.play("whoosh", 1.0, -4.0)

func close_levels() -> void:
	if level_select:
		level_select.queue_free()
		level_select = null
		Sfx.play("whoosh", 0.8, -6.0)

## How much the key art (at `art` in design space) must be enlarged around the composition centre (540, 960) so that it
## covers the visible area `vis` (never stretched: one factor for both axes; 1.0 when it already covers).
static func cover_scale(art: Rect2, vis: Rect2) -> float:
	var c := Vector2(540, 960)
	var k := 1.0
	if c.x - art.position.x > 0.0:
		k = maxf(k, (c.x - vis.position.x) / (c.x - art.position.x))
	if art.end.x - c.x > 0.0:
		k = maxf(k, (vis.end.x - c.x) / (art.end.x - c.x))
	if c.y - art.position.y > 0.0:
		k = maxf(k, (c.y - vis.position.y) / (c.y - art.position.y))
	if art.end.y - c.y > 0.0:
		k = maxf(k, (vis.end.y - c.y) / (art.end.y - c.y))
	return k

## The visible part of the design space (the camera centres 1080x1920 on any aspect: canvas_items + expand).
func visible_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(Vector2(540, 960) - vs * 0.5, vs)

## Start a run at `level` (0 = new game from the first location).
func start(level: int) -> void:
	Game.carry = {} if level <= 0 else {"level": level, "score": 0}
	Sfx.play("flush_big", 1.1, -4.0)
	if change_scenes:
		get_tree().change_scene_to_file(GAME_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = get_canvas_transform().affine_inverse() * event.position
	if pos == Vector2.INF or level_select:
		return
	if logo.texture and Rect2(logo.position - logo.texture.get_size() * _logo_scale * 0.5, logo.texture.get_size() * _logo_scale).has_point(pos):
		tap_logo()

## A tap on the logo: squash it; 5 quick taps toggle DEV MODE.
func tap_logo() -> void:
	_squash = 1.0
	Sfx.play("pop", randf_range(0.9, 1.2))
	var now := Time.get_ticks_msec() / 1000.0
	_taps = _taps + 1 if now - _last_tap < 1.2 else 1
	_last_tap = now
	if _taps >= 5:
		_taps = 0
		Game.dev = not Game.dev
		if not Game.dev:
			Game.god_mode = false
			Game.dev_slowmo = false
			Game.dev_stats = false
		_toast = DEV_LABEL + (" MODE ON" if Game.dev else " MODE OFF")
		_toast_t = 0.0

func _process(dt: float) -> void:
	_t += dt
	_toast_t += dt
	_squash = maxf(0.0, _squash - dt * 3.0)
	# logo: drop in with a bounce, then bob; squash when tapped
	var drop := 1.0 - exp(-_t * 5.0) * cos(_t * 12.0)
	var bob := sin(_t * 2.2) * 10.0
	logo.position = Vector2(540, lerpf(-300.0, 390.0, clampf(drop, 0.0, 1.2)) + bob)
	var sq := sin(_squash * 18.0) * _squash * 0.18
	logo.scale = Vector2(_logo_scale * (1.0 + sq), _logo_scale * (1.0 - sq))
	logo.rotation = sin(_t * 1.3) * 0.03
	# objects spiralling into the toilet
	_spawn_t -= dt
	if _spawn_t <= 0.0 and not _textures.is_empty():
		_spawn_t = randf_range(0.35, 0.8)
		var side := -1.0 if randf() < 0.5 else 1.0
		_flyers.append({"tex": _textures.pick_random(), "a0": randf() * TAU, "r0": randf_range(380.0, 520.0), "t": 0.0,
			"life": randf_range(2.2, 3.4), "spin": randf_range(-6.0, 6.0), "dir": side, "size": randf_range(90.0, 150.0)})
	for f in _flyers:
		f.t += dt
	_flyers = _flyers.filter(func(f): return f.t < f.life)
	queue_redraw()
	var root: Control = get_meta("ui_root")
	root.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-1200, -2000, 3480, 6000), BRAND_BLUE)
	if _bg:
		var k := cover_scale(_bg_rect, visible_rect())
		var c := Vector2(540, 960)
		draw_texture_rect(_bg, Rect2(c + (_bg_rect.position - c) * k, _bg_rect.size * k), false)
	for f in _flyers:
		var k: float = f.t / f.life                 # 0 -> 1: spiral inward and shrink into the whirlpool
		var r: float = f.r0 * (1.0 - k)
		var a: float = f.a0 + f.dir * k * 5.0
		var p := DRAIN + Vector2(cos(a) * r, sin(a) * r * 0.45 - (1.0 - k) * 520.0)
		var s: float = f.size * (1.0 - k * 0.85)
		var tex: Texture2D = f.tex
		var sc := s / maxf(tex.get_width(), tex.get_height())
		draw_set_transform(p, f.spin * f.t, Vector2(sc, sc))
		draw_texture(tex, -tex.get_size() * 0.5, Color(1, 1, 1, clampf((1.0 - k) * 4.0, 0.0, 1.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ui(root: Control) -> void:
	var vs := root.size
	var best := Loc.t("BEST %d") % int(save.get("best", 0))
	_text(root, Vector2(vs.x * 0.5, vs.y - 110), best, 46, Color(1, 0.9, 0.5))
	var studio_line := STUDIO_LINE % [STUDIO, Game.version()]
	_text(root, Vector2(vs.x * 0.5, vs.y - 45), studio_line, 28, Color(1, 1, 1, 0.75))
	if _toast_t < 2.0:
		_text(root, Vector2(vs.x * 0.5, vs.y * 0.5), _toast, 72, Color(1, 0.6, 0.2, clampf(2.0 - _toast_t, 0.0, 1.0)))
	if Game.dev:
		_text(root, Vector2(vs.x - 90, 60), DEV_LABEL, 40, Color(1, 0.6, 0.2))

func _text(root: Control, p: Vector2, s: String, size: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	root.draw_string_outline(_font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, Color(0.1, 0.1, 0.18, col.a))
	root.draw_string(_font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _load_save() -> Dictionary:
	if not FileAccess.file_exists(Game.SAVE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	return d if d is Dictionary else {}
