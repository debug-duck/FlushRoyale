class_name LevelSelect
extends Control
## LEVEL SELECT (1.0.1): one card per entry of Cfg.levels (nothing per level is hand-made), in a scroll list so it fits any
## phone. A card shows the location's room (thumbnail), number, name, tagline, how many of its objects were discovered,
## and its final object: a silhouette until the location is completed, then the real thing with a FLUSHED badge.
## Locked cards are dark with a padlock. Tapping an unlocked card starts it (Title.start); BACK returns to the menu.
## Unlock rules live in Game.level_unlocked / Game.progress_of (save file, compatible with pre-1.0.1 saves).

signal chosen(level: int)
signal back

const INK := Color(0.1, 0.1, 0.18)
const GOLD := Color(1.0, 0.82, 0.3)

var save := {}
var cards: Array[Button] = []
var back_button: Button
var font: Font
var _thumbs: Array = []         # Texture2D or null per level (held: never load inside _draw)
var _finals: Array = []
var _lock: Texture2D
var _done: Texture2D
var _plunger: Texture2D
var _t := 0.0
var _scroll: ScrollContainer

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP           # nothing behind it reacts while it is open
	_lock = _tex("res://assets/processed/ui/icon_lock.png")
	_done = _tex("res://assets/processed/ui/icon_done.png")
	_plunger = _tex("res://assets/processed/ui/icon_plunger.png")
	for lv in Cfg.levels:
		_thumbs.append(_tex("res://assets/processed/ui/thumb_%s.jpg" % lv.id))
		_finals.append(_tex("res://assets/processed/" + str(lv.tiers[-1].sprite)))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_top = 210
	_scroll.offset_bottom = -190
	_scroll.offset_left = 40
	_scroll.offset_right = -40
	add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 22)
	_scroll.add_child(list)
	for i in Cfg.level_count():
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 236)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_PASS        # drags still scroll the list
		b.pressed.connect(func(): _pick(i))
		b.draw.connect(func(): _draw_card(b, i))
		list.add_child(b)
		cards.append(b)
	back_button = Button.new()
	back_button.flat = true
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.anchor_left = 0.5
	back_button.anchor_right = 0.5
	back_button.anchor_top = 1.0
	back_button.anchor_bottom = 1.0
	back_button.offset_left = -200
	back_button.offset_right = 200
	back_button.offset_top = -160
	back_button.offset_bottom = -40
	back_button.pressed.connect(func(): back.emit())
	back_button.draw.connect(_draw_back)
	add_child(back_button)

func _tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null

func unlocked(i: int) -> bool:
	return Game.level_unlocked(save, i)

func completed(i: int) -> bool:
	return Game.progress_of(save).completed.has(str(Cfg.levels[i].id))

func _pick(i: int) -> void:
	if unlocked(i):
		chosen.emit(i)
	else:
		Sfx.play("clunk", 0.8, -4.0)
		cards[i].set_meta("shake", 1.0)

func _process(dt: float) -> void:
	_t += dt
	for b in cards:
		if b.has_meta("shake"):
			var k: float = maxf(0.0, float(b.get_meta("shake")) - dt * 3.0)
			b.set_meta("shake", k)
			if k <= 0.0:
				b.remove_meta("shake")
		b.queue_redraw()
	queue_redraw()
	back_button.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.16, 0.86))
	_text(self, Vector2(size.x * 0.5, 110), Loc.t("LEVEL SELECT"), 84, GOLD, 18)
	_text(self, Vector2(size.x * 0.5, 172), Loc.t("Choose your next toilet"), 38, Color(1, 1, 1, 0.85), 10)

func _draw_card(b: Button, i: int) -> void:
	var lv: Dictionary = Cfg.levels[i]
	var open := unlocked(i)
	var done := completed(i)
	var shake := sin(_t * 60.0) * 10.0 * float(b.get_meta("shake", 0.0))
	var r := Rect2(Vector2(shake, 0), b.size)
	var pressed := b.is_pressed() and open
	if pressed:
		r = r.grow(-6)
	# room thumbnail, cropped to the card (cover)
	var inner := r.grow(-8)
	var th: Texture2D = _thumbs[i]
	if th:
		var ts := th.get_size()
		var k := maxf(inner.size.x / ts.x, inner.size.y / ts.y)
		var src := Rect2((ts - inner.size / k) * 0.5, inner.size / k)
		b.draw_texture_rect_region(th, inner, src, Color.WHITE if open else Color(0.35, 0.35, 0.42))
	else:
		b.draw_rect(inner, Color(0.2, 0.3, 0.5))
	# dark band on the left for the text
	var band := PackedVector2Array([inner.position, inner.position + Vector2(inner.size.x * 0.78, 0),
		inner.position + Vector2(inner.size.x * 0.62, inner.size.y), inner.position + Vector2(0, inner.size.y)])
	b.draw_colored_polygon(band, Color(0.03, 0.05, 0.12, 0.62))
	if not open:
		b.draw_rect(inner, Color(0.02, 0.03, 0.08, 0.45))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(8)
	frame.border_color = GOLD if done else INK
	frame.set_corner_radius_all(26)
	frame.expand_margin_left = 2
	frame.expand_margin_right = 2
	frame.expand_margin_top = 2
	frame.expand_margin_bottom = 2
	b.draw_style_box(frame, r)
	# number badge + name + tagline + discovered objects
	var p := inner.position
	b.draw_circle(p + Vector2(58, 62), 38, INK)
	b.draw_circle(p + Vector2(58, 62), 31, GOLD if open else Color(0.45, 0.47, 0.55))
	_text(b, p + Vector2(58, 77), str(i + 1), 42, INK, 0)
	var name_s := Loc.t(str(lv.name))
	_text_left(b, p + Vector2(112, 80), name_s, 50, Color.WHITE if open else Color(0.75, 0.77, 0.85), inner.size.x * 0.62)
	_text_left(b, p + Vector2(112, 128), Loc.t(str(lv.get("tagline", ""))), 30, GOLD if open else Color(0.6, 0.6, 0.65), inner.size.x * 0.62)
	if open:
		var seen := int(save.get("seen", {}).get(str(lv.id), 0)) if save.get("seen", {}) is Dictionary else 0
		var line := Loc.t("FLUSHED!") if done else Loc.t("OBJECTS FOUND: %d/%d") % [seen, lv.tiers.size()]
		_text_left(b, p + Vector2(34, 196), line, 32, Color(0.55, 1.0, 0.6) if done else Color(1, 1, 1, 0.9), inner.size.x * 0.6)
	else:
		_text_left(b, p + Vector2(34, 196), Loc.t("LOCKED: FLUSH %s FIRST") % Loc.t(str(Cfg.levels[i - 1].name)), 26,
			Color(1, 0.75, 0.6), inner.size.x * 0.62)
	# the final object (silhouette until completed), padlock or done badge
	var c := Vector2(inner.end.x - 120, inner.get_center().y)
	var fin: Texture2D = _finals[i]
	if fin:
		var s := 170.0 / maxf(fin.get_width(), fin.get_height())
		var sz := fin.get_size() * s
		var bob := sin(_t * 2.0 + i) * 4.0 if open else 0.0
		b.draw_texture_rect(fin, Rect2(c - sz * 0.5 + Vector2(0, bob), sz), false,
			Color.WHITE if done else Color(0.05, 0.05, 0.12, 0.92 if open else 0.6))
		if open and not done:
			_text(b, c + Vector2(0, 26), "?", 72, Color(1, 1, 1, 0.9), 12)
	if not open and _lock:
		var ls := 120.0 / _lock.get_height()
		b.draw_texture_rect(_lock, Rect2(c - _lock.get_size() * ls * 0.5, _lock.get_size() * ls), false)
	if done and _done:
		var ds := 84.0 / _done.get_height()
		b.draw_texture_rect(_done, Rect2(c + Vector2(30, -110), _done.get_size() * ds), false)

func _draw_back() -> void:
	var r := Rect2(Vector2.ZERO, back_button.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.62, 1.0).darkened(0.2 if back_button.is_pressed() else 0.0)
	sb.set_corner_radius_all(48)
	sb.set_border_width_all(8)
	sb.border_color = INK
	back_button.draw_style_box(sb, r)
	if _plunger:
		var s := 90.0 / _plunger.get_height()
		back_button.draw_texture_rect(_plunger, Rect2(Vector2(40, 15), _plunger.get_size() * s), false)
	_text(back_button, Vector2(r.size.x * 0.5 + 34, 78), Loc.t("BACK"), 56, Color.WHITE, 14)

func _text(ci: CanvasItem, p: Vector2, s: String, size: int, col: Color, outline: int) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if outline > 0:
		ci.draw_string_outline(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	ci.draw_string(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## Left-aligned, shrunk to fit max_w.
func _text_left(ci: CanvasItem, p: Vector2, s: String, size: int, col: Color, max_w: float) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w > max_w:
		size = int(size * max_w / w)
	ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, INK)
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
