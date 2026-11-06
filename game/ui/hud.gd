class_name Hud
extends CanvasLayer
## Minimal UI, all drawn in code: score, level title, NEXT preview, discovery strip (the level's 9 objects, unknown
## ones as silhouettes), FLUSH button (stored charges + meter ring), water gauge, warnings, banners (level start,
## ROYAL FLUSH) and the end panels (level flushed / victory / flooded) with one button.

signal flush_pressed
signal shake_pressed
signal restart_pressed
signal dev_pressed
signal menu_pressed

const INK := Color(0.1, 0.1, 0.18)
const GOLD := Color(1.0, 0.82, 0.3)

var game: Node
var root: Control
var flush_button: Button
var shake_button: Button
var _shake_icon: Texture2D
var _shake_flash_t := 9.0
var _shake_flash_bad := false
var restart_button: Button
var menu_button: Button
var dev_button: Button
var font: Font
var _panel_t := -1.0
var _panel_state := 0
var _banner := ""
var _banner_t := 0.0
var _banner_len := 0.0
var _banner_royal := false
var _banner_sub := ""
var _flash_t := 9.0
var _flash_bad := false
var _combo_text := ""            # 1.0.1 cascade label (one, updated in place)
var _combo_n := 0
var _combo_col := Color.WHITE
var _combo_t := 9.0
var _flash_col := Color.WHITE
var _screen_flash_t := 9.0
var _reveal := {}                 # tier -> seconds since revealed

func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_hud)
	add_child(root)
	fit_safe_area(root)
	flush_button = Button.new()
	flush_button.flat = true
	flush_button.focus_mode = Control.FOCUS_NONE
	flush_button.custom_minimum_size = Vector2(250, 250)
	_place(flush_button, Vector2(1, 1), Rect2(-300, -320, 250, 250))
	flush_button.button_down.connect(func(): flush_pressed.emit())
	flush_button.draw.connect(_draw_flush_button)
	root.add_child(flush_button)
	shake_button = Button.new()
	shake_button.flat = true
	shake_button.focus_mode = Control.FOCUS_NONE
	_place(shake_button, Vector2(0, 1), Rect2(150, -340, 190, 200))
	shake_button.button_down.connect(func(): shake_pressed.emit())
	shake_button.draw.connect(_draw_shake_button)
	root.add_child(shake_button)
	if ResourceLoader.exists("res://assets/processed/ui/hand_grip.png"):
		_shake_icon = load("res://assets/processed/ui/hand_grip.png")
	restart_button = Button.new()
	restart_button.text = Loc.t("RESTART")
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.add_theme_font_size_override("font_size", 60)
	restart_button.custom_minimum_size = Vector2(520, 150)
	_place(restart_button, Vector2(0.5, 0.5), Rect2(-260, 170, 520, 150))
	restart_button.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.62, 1.0)
	sb.set_corner_radius_all(40)
	sb.set_border_width_all(8)
	sb.border_color = INK
	for st in ["normal", "hover", "pressed", "focus"]:
		restart_button.add_theme_stylebox_override(st, sb)
	restart_button.add_theme_color_override("font_color", Color.WHITE)
	restart_button.pressed.connect(func(): restart_pressed.emit())
	root.add_child(restart_button)
	menu_button = Button.new()               # end panels: back to the title (LEVEL SELECT lives there)
	menu_button.text = Loc.t("MENU")
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.add_theme_font_size_override("font_size", 44)
	_place(menu_button, Vector2(0.5, 0.5), Rect2(-160, 350, 320, 100))
	var msb := sb.duplicate()
	msb.bg_color = Color(0.45, 0.48, 0.58)
	for st in ["normal", "hover", "pressed", "focus"]:
		menu_button.add_theme_stylebox_override(st, msb)
	menu_button.add_theme_color_override("font_color", Color.WHITE)
	menu_button.visible = false
	menu_button.pressed.connect(func(): menu_pressed.emit())
	root.add_child(menu_button)
	dev_button = Button.new()
	dev_button.text = Title.DEV_LABEL
	dev_button.focus_mode = Control.FOCUS_NONE
	dev_button.add_theme_font_size_override("font_size", 34)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.9, 0.55, 0.1, 0.9)
	dsb.set_corner_radius_all(16)
	dsb.set_border_width_all(4)
	dsb.border_color = INK
	for st in ["normal", "hover", "pressed", "focus"]:
		dev_button.add_theme_stylebox_override(st, dsb)
	_place(dev_button, Vector2(0, 1), Rect2(160, -120, 130, 70))
	dev_button.visible = Game.dev
	dev_button.pressed.connect(func(): dev_pressed.emit())
	root.add_child(dev_button)

## Phones with a notch / rounded corners / gesture bar: keep a full-screen control inside the display's safe area
## (converted from window pixels to canvas units). Only on mobile: on desktop the "safe area" is the monitor's, not ours.
static func fit_safe_area(c: Control) -> void:
	if not OS.has_feature("mobile") or not c.is_inside_tree():
		return
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or safe.size.x <= 0:
		return
	var f := c.get_viewport_rect().size / win
	c.offset_left = safe.position.x * f.x
	c.offset_top = safe.position.y * f.y
	c.offset_right = -(win.x - safe.end.x) * f.x
	c.offset_bottom = -(win.y - safe.end.y) * f.y

## Anchor a control to one point of the screen (0..1) with a pixel rect relative to it.
static func _place(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y

func banner(text: String, seconds: float, royal := false, sub := "") -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = 0.0
	_banner_len = seconds
	_banner_royal = royal

## The cascade label below the discovery strip: a message (kept until a new one arrives) and the merge count.
## text "" = only update the count. n = 0: no count (a lone triple).
func combo(text: String, n: int, col: Color) -> void:
	if text != "":
		_combo_text = text
	_combo_n = n
	_combo_col = col
	_combo_t = 0.0

## A brief full-screen flash (exceptional cascade).
func flash(col: Color) -> void:
	_flash_col = col
	_screen_flash_t = 0.0

func banner_busy() -> bool:
	return _banner_t < _banner_len

func reveal(tier: int) -> void:
	_reveal[tier] = 0.0

## Pulse the SHAKE button: a new shake earned (good) or a press without one (bad).
func flash_shake(bad := false) -> void:
	_shake_flash_t = 0.0
	_shake_flash_bad = bad

## Pulse the FLUSH button: a new charge (good) or a press without charges (bad).
func flash_flush(bad := false) -> void:
	_flash_t = 0.0
	_flash_bad = bad

func show_panel(state: int) -> void:
	_panel_t = 0.0
	_panel_state = state
	restart_button.visible = true
	menu_button.visible = true
	flush_button.visible = false             # the round is over: no gameplay buttons on top of the panel
	shake_button.visible = false
	dev_button.visible = false
	if state == Game.State.VICTORY:          # the finale's buttons appear after the fade to black
		restart_button.modulate.a = 0.0
		menu_button.modulate.a = 0.0
		var tw := restart_button.create_tween().set_parallel()
		tw.tween_property(restart_button, "modulate:a", 1.0, 0.6).set_delay(1.8)
		tw.tween_property(menu_button, "modulate:a", 1.0, 0.6).set_delay(1.8)
	match state:
		Game.State.LEVEL_DONE:
			restart_button.text = Loc.t("NEXT LEVEL")
		Game.State.VICTORY:
			restart_button.text = Loc.t("NEW GAME")
		_:
			restart_button.text = Loc.t("RETRY LEVEL")

## Compatibility with PoC 1 callers/tests.
func show_game_over() -> void:
	show_panel(Game.State.GAME_OVER)

func _process(dt: float) -> void:
	if _panel_t >= 0.0:
		_panel_t += dt
	_banner_t += dt
	_flash_t += dt
	_combo_t += dt
	_screen_flash_t += dt
	_shake_flash_t += dt
	shake_button.queue_redraw()
	for k in _reveal:
		_reveal[k] += dt
	root.queue_redraw()
	flush_button.queue_redraw()

func _text(p: Vector2, s: String, size: int, col := Color.WHITE, center := false, outline := 16) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var q := p - Vector2(w * 0.5, 0) if center else p
	root.draw_string_outline(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	root.draw_string(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_hud() -> void:
	if not game:
		return
	var vs := root.size
	var water: Water = game.water
	var cx := vs.x * 0.5
	# score + best, level title
	_text(Vector2(40, 110), str(game.score), 92)
	_text(Vector2(44, 168), Loc.t("BEST %d") % game.best, 40, Color(1, 1, 1, 0.85))
	_text(Vector2(cx, 62), Loc.t("LEVEL %d/%d") % [Cfg.level + 1, Cfg.level_count()], 34, Color(1, 1, 1, 0.9), true, 12)
	_text(Vector2(cx, 110), Loc.t(Cfg.level_def().name), 44, GOLD, true, 14)
	# next preview
	var box := Rect2(vs.x - 230, 30, 190, 190)
	root.draw_rect(box, Color(1, 1, 1, 0.75))
	root.draw_rect(box, INK, false, 6.0)
	_text(box.position + Vector2(95, 44), Loc.t("NEXT"), 36, Color(0.15, 0.2, 0.3), true, 0)
	_icon(game.next_tier, box.position + Vector2(95, 118), 112.0, true)
	_draw_strip(vs)
	_draw_gauge(vs, water)
	if Game.dev_stats:
		_draw_stats(water)
	# danger: a red glow creeping in from the screen edges as the water climbs (pulses faster while rising)
	if game.state == Game.State.PLAY:
		var f: float = water.fill_frac()
		if f > 0.55:
			var k := clampf((f - 0.55) / 0.45, 0.0, 1.0)
			var speed := 0.006 + (0.01 if water.rise_rate() > 0.0 else 0.0)
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * speed)
			_vignette(vs, Color(0.85, 0.05, 0.05, (0.10 + 0.32 * k) * pulse), 60.0 + 110.0 * k)
		if game.over_t > 0.0:
			var left: float = float(Cfg.c.overflow.grace_time) - game.over_t
			var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
			_text(Vector2(cx, vs.y * 0.37), Loc.t("OVERFLOWING! %.1f") % maxf(left, 0.0), 80, Color(1, 0.3 + 0.4 * flash, 0.2), true)
	_draw_combo(vs)
	if _screen_flash_t < 0.35:
		root.draw_rect(Rect2(Vector2.ZERO, vs), Color(_flash_col.lerp(Color.WHITE, 0.6), 0.45 * (1.0 - _screen_flash_t / 0.35)))
	# banner (not over an end panel or a presentation card)
	if banner_busy() and _panel_t < 0.0 and not game.showcase.active():
		var a := clampf(minf(_banner_t * 4.0, (_banner_len - _banner_t) * 2.0), 0.0, 1.0)
		var pop := 1.0 + 0.25 * exp(-_banner_t * 6.0)
		if _banner_royal:
			var wob := sin(_banner_t * 9.0) * 6.0
			_text_fit(Vector2(cx, vs.y * 0.33 + wob), _banner, int(150 * pop), vs.x - 60.0, Color(GOLD, a), 24)
			_text_lines(Vector2(cx, vs.y * 0.33 + 90), _banner_sub, 54, vs.x - 80.0, Color(1, 1, 1, a))
		else:
			_text_fit(Vector2(cx, vs.y * 0.33), _banner, int(70 * pop), vs.x - 60.0, Color(1, 1, 1, a), 18)
			if _banner_sub != "":
				_text_lines(Vector2(cx, vs.y * 0.33 + 70), _banner_sub, 46, vs.x - 80.0, Color(GOLD, a))
	# end panels
	if _panel_t >= 0.0:
		var a := clampf(_panel_t * 2.0, 0.0, 0.72)
		if _panel_state != Game.State.VICTORY:
			root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.08, 0.15, a))
		var y := vs.y * 0.5
		match _panel_state:
			Game.State.LEVEL_DONE:
				_text(Vector2(cx, y - 380), Loc.t(Cfg.level_def().name), 56, GOLD, true)
				_text_lines(Vector2(cx, y - 270), Loc.t(Cfg.level_text("royal_message")), 84, vs.x - 80.0, Color(0.6, 0.9, 1.0))
				_text(Vector2(cx, y - 40), Loc.t("LEVEL SCORE %d") % (game.score - game.level_start_score), 60, Color.WHITE, true)
				_text(Vector2(cx, y + 50), Loc.t("TOTAL %d") % game.score, 50, Color(1, 1, 1, 0.85), true)
				_text(Vector2(cx, y + 120), Loc.t("NEXT: %s") % Loc.t(Cfg.levels[Cfg.level + 1].name), 44, GOLD, true)
			Game.State.VICTORY:   # the finale: everything is gone. Fade to black, then the question.
				root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, clampf(_panel_t / 1.6, 0.0, 1.0)))
				var ta := clampf((_panel_t - 1.4) / 0.8, 0.0, 1.0)
				_text_lines(Vector2(cx, y - 420), Loc.t(Cfg.level_text("royal_message")), 50, vs.x - 100.0, Color(0.6, 0.9, 1.0, ta))
				_text(Vector2(cx, y - 170), Loc.t("NEW GAME?"), 120, Color(GOLD, ta), true)
				_text(Vector2(cx, y - 40), Loc.t("SCORE %d") % game.score, 64, Color(1, 1, 1, ta), true)
				_text(Vector2(cx, y + 40), Loc.t("BEST %d") % game.best, 46, Color(GOLD, ta * 0.8), true)
			_:
				_text(Vector2(cx, y - 220), Loc.t("FLOODED!"), 140, Color(0.6, 0.85, 1.0), true)
				_text(Vector2(cx, y - 80), Loc.t("SCORE %d") % game.score, 80, Color.WHITE, true)
				_text(Vector2(cx, y + 10), Loc.t("BEST %d") % game.best, 54, GOLD, true)

## DEV stats overlay (debug text, English only on purpose).
func _draw_stats(water: Water) -> void:
	var cap := Cfg.geo.volume_at_level(Cfg.bowl.overflow_y) - water.volume - water.displaced
	var rise := water.rise_rate()
	var lines := [
		"FPS %d   objects %d   state %d" % [Engine.get_frames_per_second(), game.objects.size(), game.state],
		"obstruction %.2f   blockage %.2f   plug %s" % [water.obstruction, water.blockage, str(water.plug.def.name) if water.plug else "-"],
		"fill %.0f%%   rise %.0f/s   overflow in %s" % [water.fill_frac() * 100.0, rise, ("%.0f s" % (cap / rise)) if rise > 0.0 else "-"],
		"charges %d   meter %.2f   chain %d   lost %s" % [game.charges, game.meter, game.chain, str(game.stats.lost)],
	]
	for i in lines.size():
		var p := Vector2(30, 640 + i * 34)
		root.draw_string_outline(font, p, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, INK)
		root.draw_string(font, p, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.7, 1.0, 0.7))

## One line, shrunk to fit max_w.
func _text_fit(p: Vector2, s: String, size: int, max_w: float, col: Color, outline := 16) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w > max_w:
		size = int(size * max_w / w)
	_text(p, s, size, col, true, outline)

## Centered text broken into lines that fit max_w (word wrap), first line at p.
func _text_lines(p: Vector2, s: String, size: int, max_w: float, col: Color) -> void:
	if s == "":
		return
	var lines: Array[String] = []
	var cur := ""
	for word in s.split(" "):
		var test := word if cur == "" else cur + " " + word
		if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			lines.append(cur)
			cur = word
		else:
			cur = test
	lines.append(cur)
	for i in lines.size():
		_text_fit(p + Vector2(0, i * size * 1.1), lines[i], size, max_w, col)

func _vignette(vs: Vector2, col: Color, width: float) -> void:
	var steps := 6
	for i in steps:
		var a := col.a * (1.0 - float(i) / steps)
		var c := Color(col, a)
		var o := width * float(i) / steps
		var t := width / steps
		root.draw_rect(Rect2(0, o, vs.x, t), c)
		root.draw_rect(Rect2(0, vs.y - o - t, vs.x, t), c)
		root.draw_rect(Rect2(o, 0, t, vs.y), c)
		root.draw_rect(Rect2(vs.x - o - t, 0, t, vs.y), c)

## The level's objects in tier order. Unknown = dark silhouette + "?"; the last one is the royal goal (gold frame).
func _draw_strip(vs: Vector2) -> void:
	var n: int = Cfg.max_tier()
	var step := minf(104.0, (vs.x - 80.0) / n)
	var slot := step - 10.0
	var x0 := vs.x * 0.5 - step * (n - 1) * 0.5
	var y := 272.0
	for t in range(1, n + 1):
		var c := Vector2(x0 + (t - 1) * step, y)
		var known: bool = game.discovered.has(t)
		var royal := t == n
		var pulse := 0.0
		if _reveal.has(t) and _reveal[t] < 1.2:
			pulse = sin(_reveal[t] * 14.0) * exp(-_reveal[t] * 3.0)
		var r := Rect2(c - Vector2(slot, slot) * 0.5 * (1.0 + pulse * 0.25), Vector2(slot, slot) * (1.0 + pulse * 0.25))
		root.draw_rect(r, Color(1, 1, 1, 0.55) if known else Color(0.1, 0.12, 0.2, 0.45))
		root.draw_rect(r, GOLD if royal else INK, false, 6.0 if royal else 4.0)
		_icon(t, c, slot - 14.0, known)
		if not known:
			_text(c + Vector2(0, 14), "?", 40, Color(1, 1, 1, 0.8), true, 8)

func _icon(t: int, c: Vector2, size: float, known: bool) -> void:
	var tex: Texture2D = game.tier_texture(t)
	if tex:
		var s := size / maxf(tex.get_width(), tex.get_height())
		var sz := tex.get_size() * s
		root.draw_texture_rect(tex, Rect2(c - sz * 0.5, sz), false, Color.WHITE if known else Color(0.05, 0.05, 0.1, 0.85))
	else:
		root.draw_circle(c, size * 0.35, Color(Cfg.tier(t).color))

## Water gauge (bottom-left): rest level at the bottom, overflow line at the top.
func _draw_gauge(vs: Vector2, water: Water) -> void:
	var g := Rect2(50, vs.y - 380, 70, 280)
	var f := clampf(water.fill_frac(), 0.0, 1.15)
	root.draw_rect(g.grow(6), INK)
	root.draw_rect(g, Color(0.92, 0.95, 1.0))
	var fh := g.size.y * minf(f, 1.0)
	var wc := Color(0.25, 0.6, 1.0).lerp(Color(1.0, 0.25, 0.2), clampf((f - 0.55) / 0.45, 0.0, 1.0))
	root.draw_rect(Rect2(g.position.x, g.end.y - fh, g.size.x, fh), wc)
	root.draw_line(Vector2(g.position.x - 14, g.position.y), Vector2(g.end.x + 14, g.position.y), Color(1, 0.2, 0.15), 6.0)
	# rising arrows next to the gauge: more arrows = faster rise
	var rise := water.rise_rate()
	if rise > 0.0:
		var n := 1 + int(clampf((rise - float(Cfg.c.water.rise_min)) / maxf(float(Cfg.c.water.rise_max) - float(Cfg.c.water.rise_min), 1.0), 0.0, 1.0) * 2.0 + 0.5)
		var bob := fmod(Time.get_ticks_msec() * 0.001 * 2.0, 1.0) * 14.0
		for i in n:
			var tip := Vector2(g.end.x + 34, g.end.y - fh - 10 - i * 26 - bob)
			root.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-14, 18), tip + Vector2(14, 18)]), Color(1, 0.3, 0.2, 0.9))
	_text(Vector2(g.position.x + 35, g.end.y + 46), Loc.t("WATER"), 30, Color.WHITE, true)

## FLUSH button: charge pips on top, the meter as a ring, grey when no charge is stored.
func _draw_flush_button() -> void:
	if not game:
		return
	var water: Water = game.water
	var c := flush_button.size * 0.5 + Vector2(0, 12)
	var r := 100.0
	var ready: bool = game.can_flush()
	var pressed := flush_button.is_pressed()
	var pulse := exp(-_flash_t * 4.0) * sin(_flash_t * 30.0) * 10.0 if _flash_t < 1.0 else 0.0
	flush_button.draw_circle(c + Vector2(0, 10), r, Color(INK, 0.45))
	flush_button.draw_circle(c, r + 8 + pulse, Color(0.8, 0.1, 0.1) if _flash_bad and _flash_t < 0.6 else INK)
	flush_button.draw_circle(c, r, Color(0.84, 0.88, 0.94))
	var royal_mode: bool = game.state == Game.State.ROYAL_READY
	var inner := Color(0.2, 0.62, 1.0) if ready else Color(0.55, 0.6, 0.68)
	if royal_mode:
		var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		inner = GOLD.lerp(Color(1, 0.95, 0.6), glow) if ready else Color(0.7, 0.6, 0.35)
		flush_button.draw_circle(c, r + 18 + 10 * glow, Color(GOLD, 0.35 * glow))
	if water.flushing():
		inner = Color(0.35, 0.8, 1.0).lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03))
	flush_button.draw_circle(c + (Vector2(0, 5) if pressed else Vector2.ZERO), r * 0.72, inner)
	if royal_mode:
		for i in 2:
			var line: String = [Loc.t("ROYAL"), Loc.t("FLUSH!")][i]
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
			var lp := c + Vector2(-lw * 0.5, -6 + i * 42)
			flush_button.draw_string_outline(font, lp, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 12, INK)
			flush_button.draw_string(font, lp, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
		return
	# meter ring (progress to the next charge)
	flush_button.draw_arc(c, r - 4, 0, TAU, 48, Color(INK, 0.25), 10.0)
	if game.meter > 0.0:
		flush_button.draw_arc(c, r - 4, -PI * 0.5, -PI * 0.5 + TAU * game.meter, 48, Color(0.3, 0.85, 1.0), 10.0)
	# charge pips
	var maxc: int = Cfg.c.meter.max_charges
	for i in maxc:
		var p := c + Vector2((i - (maxc - 1) * 0.5) * 46.0, -r - 22.0)
		flush_button.draw_circle(p, 17.0, INK)
		flush_button.draw_circle(p, 12.0, Color(0.3, 0.85, 1.0) if i < game.charges else Color(0.35, 0.38, 0.45))
	var s := Loc.t("FLUSH")
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	flush_button.draw_string_outline(font, c + Vector2(-w * 0.5, 16), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 12, INK)
	flush_button.draw_string(font, c + Vector2(-w * 0.5, 16), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color.WHITE)

## SHAKE button (TOILET SHAKE bonus): the hand icon, its meter as a ring, a pip per stored shake; grey until earned.
func _draw_shake_button() -> void:
	if not game:
		return
	var c := Vector2(95, 88)
	var r := 74.0
	var ready: bool = game.can_shake()
	var pulse := exp(-_shake_flash_t * 4.0) * sin(_shake_flash_t * 30.0) * 8.0 if _shake_flash_t < 1.0 else 0.0
	var bad := _shake_flash_bad and _shake_flash_t < 0.6
	shake_button.draw_circle(c + Vector2(0, 8), r, Color(INK, 0.45))
	shake_button.draw_circle(c, r + 7 + pulse, Color(0.8, 0.1, 0.1) if bad else INK)
	var inner := Color(0.98, 0.6, 0.2) if ready else Color(0.55, 0.58, 0.64)
	if ready:
		inner = inner.lerp(Color(1, 0.85, 0.5), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
	shake_button.draw_circle(c, r, inner)
	if _shake_icon:
		var h := r * 1.25
		var sz := Vector2(_shake_icon.get_width() * h / _shake_icon.get_height(), h)
		var wob := sin(Time.get_ticks_msec() * 0.03) * 0.12 if ready else 0.0
		shake_button.draw_set_transform(c + Vector2(0, -6), wob, Vector2.ONE)
		shake_button.draw_texture_rect(_shake_icon, Rect2(-sz * 0.5, sz), false, Color.WHITE if ready else Color(1, 1, 1, 0.45))
		shake_button.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	shake_button.draw_arc(c, r - 3, 0, TAU, 40, Color(INK, 0.25), 8.0)
	if game.shake_meter > 0.0:
		shake_button.draw_arc(c, r - 3, -PI * 0.5, -PI * 0.5 + TAU * minf(game.shake_meter, 1.0), 40, Color(1.0, 0.85, 0.3), 8.0)
	var maxc: int = Cfg.c.shake.max_charges
	for i in maxc:
		var p := c + Vector2((i - (maxc - 1) * 0.5) * 34.0, -r - 16.0)
		shake_button.draw_circle(p, 13.0, INK)
		shake_button.draw_circle(p, 9.0, Color(1.0, 0.7, 0.2) if i < game.shake_charges else Color(0.35, 0.38, 0.45))
	var label := Loc.t("SHAKE!")
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	shake_button.draw_string_outline(font, c + Vector2(-w * 0.5, r + 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 10, INK)
	shake_button.draw_string(font, c + Vector2(-w * 0.5, r + 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)

## Cascade label: pops on every update, wobbles while it lasts, fades after cascade.label_hold s.
func _draw_combo(vs: Vector2) -> void:
	var hold: float = Cfg.c.cascade.label_hold
	if _combo_t > hold + 0.4 or _combo_text == "" or _panel_t >= 0.0 or game.showcase.active():
		return
	var a := clampf((hold + 0.4 - _combo_t) / 0.4, 0.0, 1.0)
	var pop := 1.0 + 0.45 * exp(-_combo_t * 9.0)
	var y := 410.0
	var wob := sin(_combo_t * 11.0) * 4.0 * exp(-_combo_t * 2.0)
	_text_fit(Vector2(vs.x * 0.5, y + wob), _combo_text, int(84 * pop), vs.x - 80.0, Color(_combo_col, a), 18)
	if _combo_n >= 2:
		_text(Vector2(vs.x * 0.5, y + 64), Loc.t("CHAIN x%d") % _combo_n, int(50 * (1.0 + 0.3 * exp(-_combo_t * 12.0))), Color(1, 1, 1, a), true, 12)
