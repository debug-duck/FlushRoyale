class_name Hud
extends CanvasLayer
## Minimal UI, all drawn in code: score, level title, NEXT preview, discovery strip (the level's 9 objects, unknown
## ones as silhouettes), FLUSH button (stored charges + meter ring), water gauge, warnings, banners (level start,
## ROYAL FLUSH) and the end panels (level flushed / victory / flooded) with one button.

signal flush_pressed
signal restart_pressed

const INK := Color(0.1, 0.1, 0.18)
const GOLD := Color(1.0, 0.82, 0.3)

var game: Node
var root: Control
var flush_button: Button
var restart_button: Button
var font: Font
var _panel_t := -1.0
var _panel_state := 0
var _banner := ""
var _banner_t := 0.0
var _banner_len := 0.0
var _banner_royal := false
var _flash_t := 9.0
var _flash_bad := false
var _reveal := {}                 # tier -> seconds since revealed

func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_hud)
	add_child(root)
	flush_button = Button.new()
	flush_button.flat = true
	flush_button.focus_mode = Control.FOCUS_NONE
	flush_button.custom_minimum_size = Vector2(250, 250)
	_place(flush_button, Vector2(1, 1), Rect2(-300, -320, 250, 250))
	flush_button.button_down.connect(func(): flush_pressed.emit())
	flush_button.draw.connect(_draw_flush_button)
	root.add_child(flush_button)
	restart_button = Button.new()
	restart_button.text = "RESTART"
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

func banner(text: String, seconds: float, royal := false) -> void:
	_banner = text
	_banner_t = 0.0
	_banner_len = seconds
	_banner_royal = royal

func reveal(tier: int) -> void:
	_reveal[tier] = 0.0

## Pulse the FLUSH button: a new charge (good) or a press without charges (bad).
func flash_flush(bad := false) -> void:
	_flash_t = 0.0
	_flash_bad = bad

func show_panel(state: int) -> void:
	_panel_t = 0.0
	_panel_state = state
	restart_button.visible = true
	match state:
		Game.State.LEVEL_DONE:
			restart_button.text = "NEXT LEVEL"
		Game.State.VICTORY:
			restart_button.text = "PLAY AGAIN"
		_:
			restart_button.text = "RETRY LEVEL"

## Compatibility with PoC 1 callers/tests.
func show_game_over() -> void:
	show_panel(Game.State.GAME_OVER)

func _process(dt: float) -> void:
	if _panel_t >= 0.0:
		_panel_t += dt
	_banner_t += dt
	_flash_t += dt
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
	_text(Vector2(44, 168), "BEST %d" % game.best, 40, Color(1, 1, 1, 0.85))
	_text(Vector2(cx, 62), "LEVEL %d/%d" % [Cfg.level + 1, Cfg.level_count()], 34, Color(1, 1, 1, 0.9), true, 12)
	_text(Vector2(cx, 110), str(Cfg.level_def().name), 44, GOLD, true, 14)
	# next preview
	var box := Rect2(vs.x - 230, 30, 190, 190)
	root.draw_rect(box, Color(1, 1, 1, 0.75))
	root.draw_rect(box, INK, false, 6.0)
	_text(box.position + Vector2(95, 44), "NEXT", 36, Color(0.15, 0.2, 0.3), true, 0)
	_icon(game.next_tier, box.position + Vector2(95, 118), 112.0, true)
	_draw_strip(vs)
	_draw_gauge(vs, water)
	# warnings
	if game.state == Game.State.PLAY:
		if game.over_t > 0.0:
			var left: float = float(Cfg.c.overflow.grace_time) - game.over_t
			var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
			_text(Vector2(cx, vs.y * 0.37), "OVERFLOWING! %.1f" % maxf(left, 0.0), 80, Color(1, 0.3 + 0.4 * flash, 0.2), true)
		elif water.blockage > 0.75:
			_text(Vector2(cx, vs.y * 0.37), "CLOGGED!", 64, Color(1, 0.75, 0.3), true)
	# banner (not over an end panel)
	if _banner_t < _banner_len and _panel_t < 0.0:
		var a := clampf(minf(_banner_t * 4.0, (_banner_len - _banner_t) * 2.0), 0.0, 1.0)
		var pop := 1.0 + 0.25 * exp(-_banner_t * 6.0)
		if _banner_royal:
			var size := int(150 * pop)
			var wob := sin(_banner_t * 9.0) * 6.0
			_text(Vector2(cx, vs.y * 0.33 + wob), _banner, size, Color(GOLD, a), true, 24)
			_text(Vector2(cx, vs.y * 0.33 + 90), "EVERYTHING MUST GO!", 54, Color(1, 1, 1, a), true)
		else:
			_text(Vector2(cx, vs.y * 0.33), _banner, int(70 * pop), Color(1, 1, 1, a), true, 18)
	# end panels
	if _panel_t >= 0.0:
		var a := clampf(_panel_t * 2.0, 0.0, 0.72)
		root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.08, 0.15, a))
		var y := vs.y * 0.5
		match _panel_state:
			Game.State.LEVEL_DONE:
				_text(Vector2(cx, y - 320), str(Cfg.level_def().name), 64, GOLD, true)
				_text(Vector2(cx, y - 150), "FLUSHED!", 140, Color(0.6, 0.9, 1.0), true)
				_text(Vector2(cx, y - 40), "LEVEL SCORE %d" % (game.score - game.level_start_score), 60, Color.WHITE, true)
				_text(Vector2(cx, y + 50), "TOTAL %d" % game.score, 50, Color(1, 1, 1, 0.85), true)
				_text(Vector2(cx, y + 120), "NEXT: %s" % str(Cfg.levels[Cfg.level + 1].name), 44, GOLD, true)
			Game.State.VICTORY:
				_text(Vector2(cx, y - 240), "ALL HAIL", 80, Color.WHITE, true)
				_text(Vector2(cx, y - 120), "THE FLUSH KING!", 110, GOLD, true)
				_text(Vector2(cx, y - 10), "SCORE %d" % game.score, 80, Color.WHITE, true)
				_text(Vector2(cx, y + 80), "BEST %d" % game.best, 54, GOLD, true)
			_:
				_text(Vector2(cx, y - 220), "FLOODED!", 140, Color(0.6, 0.85, 1.0), true)
				_text(Vector2(cx, y - 80), "SCORE %d" % game.score, 80, Color.WHITE, true)
				_text(Vector2(cx, y + 10), "BEST %d" % game.best, 54, GOLD, true)

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
	_text(Vector2(g.position.x + 35, g.end.y + 46), "WATER", 30, Color.WHITE, true)

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
	var inner := Color(0.2, 0.62, 1.0) if ready else Color(0.55, 0.6, 0.68)
	if water.flushing():
		inner = Color(0.35, 0.8, 1.0).lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03))
	flush_button.draw_circle(c + (Vector2(0, 5) if pressed else Vector2.ZERO), r * 0.72, inner)
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
	var s := "FLUSH"
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	flush_button.draw_string_outline(font, c + Vector2(-w * 0.5, 16), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 12, INK)
	flush_button.draw_string(font, c + Vector2(-w * 0.5, 16), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color.WHITE)
