class_name Hud
extends CanvasLayer
## Minimal UI, all drawn in code: score, next-object preview, FLUSH button (with tank-refill ring), overflow gauge
## (+ countdown while the water is over the line), clog/overflow warnings, game-over panel with RESTART.

signal flush_pressed
signal restart_pressed

var game: Node
var root: Control
var flush_button: Button
var restart_button: Button
var font: Font
var _panel_t := -1.0

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
	restart_button.add_theme_font_size_override("font_size", 64)
	restart_button.custom_minimum_size = Vector2(440, 150)
	_place(restart_button, Vector2(0.5, 0.5), Rect2(-220, 140, 440, 150))
	restart_button.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.62, 1.0)
	sb.set_corner_radius_all(40)
	sb.set_border_width_all(8)
	sb.border_color = Color(0.1, 0.1, 0.18)
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

func show_game_over() -> void:
	_panel_t = 0.0
	restart_button.visible = true

func _process(dt: float) -> void:
	if _panel_t >= 0.0:
		_panel_t += dt
	root.queue_redraw()
	flush_button.queue_redraw()

func _text(p: Vector2, s: String, size: int, col := Color.WHITE, center := false) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var q := p - Vector2(w * 0.5, 0) if center else p
	root.draw_string_outline(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color(0.1, 0.1, 0.18))
	root.draw_string(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_hud() -> void:
	if not game:
		return
	var vs := root.size
	var water: Water = game.water
	# score + best
	_text(Vector2(40, 110), str(game.score), 92)
	_text(Vector2(44, 168), "BEST %d" % game.best, 40, Color(1, 1, 1, 0.85))
	# next preview
	var box := Rect2(vs.x - 230, 30, 190, 190)
	root.draw_rect(box, Color(1, 1, 1, 0.75))
	root.draw_rect(box, Color(0.1, 0.1, 0.18), false, 6.0)
	_text(box.position + Vector2(95, 44), "NEXT", 36, Color(0.15, 0.2, 0.3), true)
	var tex: Texture2D = game.tier_texture(game.next_tier)
	if tex:
		var s := 120.0 / maxf(tex.get_width(), tex.get_height())
		var sz := tex.get_size() * s
		root.draw_texture_rect(tex, Rect2(box.position + Vector2(95, 115) - sz * 0.5, sz), false)
	else:
		root.draw_circle(box.position + Vector2(95, 115), 40, Color(Cfg.tier(game.next_tier).color))
	# overflow gauge (bottom-left): rest level at the bottom, overflow line at the top
	var g := Rect2(50, vs.y - 380, 70, 280)
	var f := clampf(water.fill_frac(), 0.0, 1.15)
	root.draw_rect(g.grow(6), Color(0.1, 0.1, 0.18))
	root.draw_rect(g, Color(0.92, 0.95, 1.0))
	var fh := g.size.y * minf(f, 1.0)
	var wc := Color(0.25, 0.6, 1.0).lerp(Color(1.0, 0.25, 0.2), clampf((f - 0.55) / 0.45, 0.0, 1.0))
	root.draw_rect(Rect2(g.position.x, g.end.y - fh, g.size.x, fh), wc)
	root.draw_line(Vector2(g.position.x - 14, g.position.y), Vector2(g.end.x + 14, g.position.y), Color(1, 0.2, 0.15), 6.0)
	_text(Vector2(g.position.x + 35, g.end.y + 46), "WATER", 30, Color.WHITE, true)
	if game.over_t > 0.0 and not game.game_over:
		var left: float = float(Cfg.c.overflow.grace_time) - game.over_t
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		_text(Vector2(vs.x * 0.5, vs.y * 0.36), "OVERFLOWING! %.1f" % maxf(left, 0.0), 80, Color(1, 0.3 + 0.4 * flash, 0.2), true)
	elif water.blockage > 0.75 and not game.game_over:
		_text(Vector2(vs.x * 0.5, vs.y * 0.36), "CLOGGED!", 64, Color(1, 0.75, 0.3), true)
	if game.game_over:
		var a := clampf(_panel_t * 2.0, 0.0, 0.7)
		root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.08, 0.15, a))
		_text(Vector2(vs.x * 0.5, vs.y * 0.5 - 220), "FLOODED!", 140, Color(0.6, 0.85, 1.0), true)
		_text(Vector2(vs.x * 0.5, vs.y * 0.5 - 80), "SCORE %d" % game.score, 80, Color.WHITE, true)
		_text(Vector2(vs.x * 0.5, vs.y * 0.5 + 10), "BEST %d" % game.best, 54, Color(1, 0.9, 0.5), true)

func _draw_flush_button() -> void:
	if not game:
		return
	var water: Water = game.water
	var c := flush_button.size * 0.5
	var r := 110.0
	var ready: bool = water.can_flush() and not game.game_over
	var pressed := flush_button.is_pressed()
	flush_button.draw_circle(c + Vector2(0, 10), r, Color(0.1, 0.1, 0.18, 0.45))
	flush_button.draw_circle(c, r + 8, Color(0.1, 0.1, 0.18))
	flush_button.draw_circle(c, r, Color(0.84, 0.88, 0.94))
	var inner := Color(0.2, 0.62, 1.0) if ready else Color(0.55, 0.6, 0.68)
	if water.flushing():
		inner = Color(0.35, 0.8, 1.0).lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03))
	flush_button.draw_circle(c + (Vector2(0, 5) if pressed else Vector2.ZERO), r * 0.72, inner)
	var fr := water.flush_ready_frac()
	if fr < 1.0:
		flush_button.draw_arc(c, r - 4, -PI * 0.5, -PI * 0.5 + TAU * fr, 48, Color(0.2, 0.62, 1.0), 10.0)
	var s := "FLUSH"
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 50).x
	flush_button.draw_string_outline(font, c + Vector2(-w * 0.5, 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, 12, Color(0.1, 0.1, 0.18))
	flush_button.draw_string(font, c + Vector2(-w * 0.5, 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
