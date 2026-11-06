class_name Showcase
extends Node2D
## PoC 4 "A Little Story Before the Flush": ONE presentation card, drawn in WORLD space (above the bowl, below the HUD) so
## that it can be sucked into the real drain.
## * INTRO: the first discovery (ever, saved by Game) of an object with an `intro` line in data/levels.json. Game queues it
##   until the cascade is over; the card pauses the game, pops in elastically (letters bounce in one by one, procedural
##   boing + chime), and leaves after `showcase.intro_time` real seconds or on a tap, flying into its slot in the strip.
## * REVEAL: the level's last object, on every completion, when the royal flush arms (the cascade has finished): drumroll
##   over a silhouette, then the object, its name and its `reveal` line. It stays until the player presses ROYAL FLUSH.
## * FLUSHING: flush_away() - the card shakes, tilts and shrinks during the royal slow-mo, then breaks into its pieces
##   (panel chunks with their bit of frame, ribbon, picture, every letter of the name, every word of the comment, stars),
##   which spiral into the drain one after another. `gone` fires when the last piece is swallowed.
## Tweens drive the card (entrance / exit), the pieces are procedural. Runs on REAL time (slow-mo and pause proof).

signal gone

enum Mode { NONE, INTRO, REVEAL, FLUSHING }

const INK := Color(0.1, 0.1, 0.18)
const GOLD := Color(1.0, 0.82, 0.3)
const COLS := 4
const ROWS := 5

var game: Node
var mode := Mode.NONE
var tier := 0
var card_scale := 0.0          # tweened
var card_rot := 0.0            # tweened
var card_pos := Vector2.ZERO   # tweened
var dim := 0.0                 # tweened: darkens the bowl behind the card
var paused_game := false       # INTRO pauses the SceneTree; REVEAL does not (the HUD button must work)
var font: Font
var _cfg: Dictionary
var _center := Vector2(540, 830)
var _size := Vector2(820, 880)
var _parts: Array = []
var _t := 0.0                  # real seconds since the card appeared
var _flush_t := -1.0           # real seconds since flush_away()
var _shake_time := 1.4
var _order: Array = []         # parts in the order they tear off
var _detach_next := 0.0
var _gulp_t := 0.0
var _closing := false
var _revealed := false         # REVEAL: the drumroll is over
var _flash := 0.0
var _drain := Vector2.ZERO
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	font = ThemeDB.fallback_font
	_cfg = Cfg.c.showcase
	_center = Vector2(float(_cfg.card_center[0]), float(_cfg.card_center[1]))
	_size = Vector2(float(_cfg.card_size[0]), float(_cfg.card_size[1]))

func active() -> bool:
	return mode != Mode.NONE

func has_reveal() -> bool:
	return mode == Mode.REVEAL

# ------------------------------------------------------------------ the three entry points

## Introduce tier `t` of the current level (its def must have an `intro` line). Pauses the game while shown.
func intro(t: int) -> void:
	var def := Cfg.tier(t)
	_open(Mode.INTRO, t, Loc.t("NEW DISCOVERY!"), Loc.t(str(def.get("intro", ""))), Loc.t("TAP TO CONTINUE"))
	paused_game = true
	get_tree().paused = true
	if game:
		game.hud.root.queue_redraw()     # the HUD is paused too: redraw it once without its banner
	_tween = _new_tween()
	_tween.tween_property(self, "card_scale", 1.0, 0.6).from(0.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "card_rot", 0.0, 0.5).from(-0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "card_pos", _center, 0.45).from(_center + Vector2(0, 320)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "dim", 0.45, 0.25).from(0.0)
	Sfx.play("boing", randf_range(0.95, 1.1), -2.0)

## The grand reveal of the level's last object. Stays until flush_away().
func reveal(t: int) -> void:
	var def := Cfg.tier(t)
	_open(Mode.REVEAL, t, Loc.t("THE GRAND FINALE!"), Loc.t(str(def.get("reveal", ""))), Loc.t("PRESS ROYAL FLUSH!"))
	_revealed = false
	_tween = _new_tween()
	_tween.tween_property(self, "card_scale", 1.0, 0.7).from(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "card_rot", 0.0, 0.7).from(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "card_pos", _center, 0.01).from(_center)
	_tween.tween_property(self, "dim", 0.55, 0.4).from(0.0)
	Sfx.play("drumroll", 1.0, -1.0)

## ROYAL FLUSH pressed: shake for `shake_time` real seconds, then tear apart into the drain at `drain` (world).
func flush_away(drain: Vector2, shake_time: float) -> void:
	if mode != Mode.REVEAL:
		return
	if not _revealed:
		_finish_drumroll()
	if _tween:
		_tween.kill()
	card_scale = 1.0
	card_rot = 0.0
	card_pos = _center
	mode = Mode.FLUSHING
	_drain = drain
	_shake_time = shake_time
	_flush_t = 0.0
	_detach_next = 0.0
	for p in _parts:
		if p.kind == "footer":
			p.text = Loc.t("UH-OH.")
	_order = _tear_order()
	Sfx.play("rattle", 1.0, -2.0)

## INTRO: close now (a tap). The game resumes at once; the card flies into its slot in the discovery strip.
func dismiss() -> void:
	if mode != Mode.INTRO or _closing:
		return
	_closing = true
	if paused_game:
		get_tree().paused = false
		paused_game = false
	if _tween:
		_tween.kill()
	var to := _strip_slot(tier)
	_tween = _new_tween()
	_tween.tween_property(self, "card_scale", 0.06, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "card_rot", 0.5, 0.32).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "card_pos", to, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "dim", 0.0, 0.25)
	_tween.chain().tween_callback(_close_done)
	Sfx.play("whoosh", 1.2, -6.0)

func _close_done() -> void:
	mode = Mode.NONE
	_parts.clear()
	_closing = false
	queue_redraw()
	gone.emit()

func _new_tween() -> Tween:
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tw

# ------------------------------------------------------------------ building the card out of pieces

func _open(m: Mode, t: int, kicker: String, comment: String, footer: String) -> void:
	mode = m
	tier = t
	_t = 0.0
	_flush_t = -1.0
	_flash = 0.0
	_closing = false
	card_scale = 0.0
	card_pos = _center
	_parts.clear()
	var royal := m == Mode.REVEAL
	var w := _size.x
	var h := _size.y
	var top := -h * 0.5
	var start := (float(_cfg.drumroll) + 0.1) if royal else 0.25    # letters/words start bouncing in here
	# panel = COLS x ROWS chunks, each with its share of the rounded frame (the card looks whole until it tears)
	var bg := Color(1.0, 0.91, 0.62) if royal else Color(1.0, 0.98, 0.92)
	var cw := w / COLS
	var ch := h / ROWS
	for j in ROWS:
		for i in COLS:
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.border_color = INK
			sb.border_width_left = 12 if i == 0 else 0
			sb.border_width_right = 12 if i == COLS - 1 else 0
			sb.border_width_top = 12 if j == 0 else 0
			sb.border_width_bottom = 12 if j == ROWS - 1 else 0
			sb.expand_margin_left = 0.0 if i == 0 else 1.5
			sb.expand_margin_right = 0.0 if i == COLS - 1 else 1.5
			sb.expand_margin_top = 0.0 if j == 0 else 1.5
			sb.expand_margin_bottom = 0.0 if j == ROWS - 1 else 1.5
			sb.corner_radius_top_left = 48 if i == 0 and j == 0 else 0
			sb.corner_radius_top_right = 48 if i == COLS - 1 and j == 0 else 0
			sb.corner_radius_bottom_left = 48 if i == 0 and j == ROWS - 1 else 0
			sb.corner_radius_bottom_right = 48 if i == COLS - 1 and j == ROWS - 1 else 0
			_add({"kind": "chunk", "pos": Vector2(-w * 0.5 + cw * (i + 0.5), top + ch * (j + 0.5)), "size": Vector2(cw, ch), "sb": sb})
	# the object, enlarged (reuses its sprite)
	var tex: Texture2D = game.tier_texture(t) if game else null
	var pic_box := Vector2(w - 260, 330)
	var pic_y := top + 90 + pic_box.y * 0.5
	var pic_size := pic_box
	if tex:
		var s := minf(pic_box.x / tex.get_width(), pic_box.y / tex.get_height())
		pic_size = tex.get_size() * s
	_add({"kind": "pic", "pos": Vector2(0, pic_y), "size": pic_size, "tex": tex, "color": Color(Cfg.tier(t).color), "delay": 0.0})
	# name: one line if it fits at a readable size, else two balanced lines; every letter is its own piece
	var y := pic_y + pic_box.y * 0.5 + 24
	var name_lines := _fit_lines(Loc.t(str(Cfg.tier(t).name)).to_upper(), w - 100, 84, 62)
	var nsize: int = name_lines[0]
	var gi := 0
	for line in name_lines[1]:
		y += nsize * 0.95
		var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x
		var x := -lw * 0.5
		for k in line.length():
			var c: String = line[k]
			var cw2 := font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x
			if c != " ":
				_add({"kind": "glyph", "text": c, "fsize": nsize, "pos": Vector2(x + cw2 * 0.5, y - nsize * 0.35),
					"half": cw2 * 0.5, "color": Color(0.86, 0.14, 0.2) if royal else Color(1.0, 0.5, 0.12), "delay": start + gi * 0.025})
				gi += 1
			x = -lw * 0.5 + font.get_string_size(line.substr(0, k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x
	# comment: word wrapped, every word is its own piece
	y += 22
	var cl := _fit_lines(comment, w - 100, 44, 34, 3)
	var csize: int = cl[0]
	var wi := 0
	for line in cl[1]:
		y += csize * 1.12
		var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, csize).x
		var x := -lw * 0.5
		var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, csize).x
		for word in line.split(" "):
			var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, csize).x
			_add({"kind": "word", "text": word, "fsize": csize, "pos": Vector2(x + ww * 0.5, y - csize * 0.35), "half": ww * 0.5,
				"color": INK, "delay": start + 0.2 + wi * 0.035})
			wi += 1
			x += ww + space
	_add({"kind": "footer", "text": footer, "fsize": 32, "pos": Vector2(0, h * 0.5 - 38), "color": Color(INK, 0.6), "delay": start + 0.5})
	# ribbon with the kicker across the top edge
	_add({"kind": "ribbon", "text": kicker, "pos": Vector2(0, top + 6), "size": Vector2(minf(w - 120, 620), 104),
		"color": Color(0.82, 0.12, 0.2) if royal else Color(0.2, 0.62, 1.0), "delay": 0.0})
	# stars on the frame
	var stars := [Vector2(-w * 0.5 + 20, top + 40), Vector2(w * 0.5 - 20, top + 40), Vector2(-w * 0.5 - 6, h * 0.5 - 90),
		Vector2(w * 0.5 + 6, h * 0.5 - 90), Vector2(-w * 0.5 + 120, h * 0.5 + 4), Vector2(w * 0.5 - 120, h * 0.5 + 4)]
	for i in stars.size():
		_add({"kind": "star", "pos": stars[i], "r": 34.0 if i < 2 else 26.0, "color": GOLD, "delay": 0.2 + i * 0.06,
			"spin": (1.0 if i % 2 == 0 else -1.0) * randf_range(0.6, 1.2)})
	queue_redraw()

func _add(p: Dictionary) -> void:
	p.merge({"rot": 0.0, "delay": 0.0, "detached": false, "jit": Vector2.ZERO})
	_parts.append(p)

## [font size, lines]: the biggest size in [min_size, size] whose word-wrapped text needs <= max_lines lines.
func _fit_lines(s: String, max_w: float, size: int, min_size: int, max_lines := 2) -> Array:
	var sz := size
	while true:
		var lines := _wrap(s, max_w, sz)
		var widest := 0.0
		for l in lines:
			widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
		if (lines.size() <= max_lines and widest <= max_w) or sz <= min_size:
			if lines.size() == 1 and sz < size and max_lines >= 2:     # prefer two big lines over one tiny line
				var two := _wrap(s, max_w * 0.62, size)
				if two.size() == 2:
					return [size, two]
			return [sz, lines]
		sz -= 2
	return [sz, [s]]

func _wrap(s: String, max_w: float, size: int) -> Array:
	var lines: Array = []
	var cur := ""
	for word in s.split(" ", false):
		var test := word if cur == "" else cur + " " + word
		if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			lines.append(cur)
			cur = word
		else:
			cur = test
	if cur != "":
		lines.append(cur)
	return lines if not lines.is_empty() else [""]

## Tear-off order: decorations and text first, then the frame, the picture (the object itself) last.
func _tear_order() -> Array:
	var by: Dictionary = {"star": [], "footer": [], "word": [], "glyph": [], "ribbon": [], "chunk": [], "pic": []}
	for p in _parts:
		by[p.kind].append(p)
	var words: Array = by.word
	words.reverse()
	var glyphs: Array = by.glyph
	glyphs.shuffle()
	var chunks: Array = by.chunk
	chunks.sort_custom(func(a, b): return a.pos.distance_to(Vector2.ZERO) > b.pos.distance_to(Vector2.ZERO))
	return by.star + by.footer + words + glyphs + by.ribbon + chunks + by.pic

# ------------------------------------------------------------------ animation

func _process(dt: float) -> void:
	if mode == Mode.NONE:
		return
	var rdt := dt / maxf(Engine.time_scale, 0.001)    # real time: slow-mo and pause proof
	_t += rdt
	_flash = maxf(0.0, _flash - rdt * 2.5)
	if mode == Mode.INTRO and not _closing and _t >= float(_cfg.intro_time):
		dismiss()
	if mode == Mode.REVEAL and not _revealed and _t >= float(_cfg.drumroll):
		_finish_drumroll()
	if mode == Mode.FLUSHING:
		_update_flush(rdt)
	queue_redraw()

func _finish_drumroll() -> void:
	_revealed = true
	_flash = 1.0
	Sfx.cascade(6)

func _update_flush(rdt: float) -> void:
	_flush_t += rdt
	var k := clampf(_flush_t / maxf(_shake_time, 0.01), 0.0, 1.0)
	var tear := maxf(0.0, _flush_t - _shake_time)
	# the remaining card shakes, tilts, shrinks and drifts toward the drain (more and more once it tears)
	var pull := k * 0.08 + minf(tear * 0.25, 0.6)
	card_pos = _center.lerp(_drain, pull) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (4.0 + 20.0 * k)
	card_rot = sin(_flush_t * 23.0) * 0.10 * k + k * 0.12 + tear * 0.8
	card_scale = 1.0 - 0.12 * k - minf(tear * 0.2, 0.5)
	dim = 0.55 * (1.0 - k * 0.6) * maxf(0.0, 1.0 - tear)
	for p in _parts:
		if not p.detached:
			p.jit = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 5.0 * k
	if _flush_t >= _shake_time:
		_detach_next -= rdt
		while _detach_next <= 0.0 and not _order.is_empty():
			_detach(_order.pop_front())
			_detach_next += float(_cfg.break_stagger)
	_gulp_t -= rdt
	var left := 0
	for p in _parts:
		if not p.detached:
			left += 1
			continue
		var w: Dictionary = p.w
		if w.k >= 1.0:
			continue
		w.k = minf(1.0, w.k + rdt / w.life)
		if w.k >= 1.0 and _gulp_t <= 0.0:
			_gulp_t = 0.07
			Sfx.play("plop", randf_range(0.7, 1.6), -9.0)
		if w.k < 1.0:
			left += 1
	if left == 0 and _order.is_empty():
		mode = Mode.NONE
		_parts.clear()
		queue_redraw()
		gone.emit()

## A piece tears off: from now on it spirals into the drain on its own.
func _detach(p: Dictionary) -> void:
	var xf := _card_xf() * Transform2D(p.rot, p.pos)
	var wp := xf.origin
	var d := wp - _drain
	var st: Array = _cfg.suck_time
	var tu: Array = _cfg.turns
	p.detached = true
	p.w = {"p0": wp, "rot0": xf.get_rotation(), "s0": xf.get_scale().x, "r0": d.length(), "a0": atan2(d.y, d.x), "k": 0.0,
		"life": randf_range(float(st[0]), float(st[1])), "turns": randf_range(float(tu[0]), float(tu[1])),
		"spin": randf_range(-9.0, 9.0), "kick": (wp - card_pos).normalized() * randf_range(30.0, 90.0)}
	if p.kind == "pic":
		Sfx.play("slide_down", 1.0, -2.0)
	elif p.kind == "chunk" and randf() < 0.4:
		Sfx.play("clunk", randf_range(1.1, 1.6), -10.0)

## Where a detached piece is now: an accelerating whirlpool spiral (radius shrinks, angle speeds up, flattens like the
## vortex seen from the side) plus a little outward kick when it tears off.
func _piece_xf(p: Dictionary) -> Transform2D:
	var w: Dictionary = p.w
	var e: float = w.k * w.k
	var r: float = w.r0 * (1.0 - e)
	var a: float = w.a0 + w.turns * TAU * e
	var off := Vector2(cos(a) * lerpf(1.0, 0.55, e), sin(a) * lerpf(1.0, 0.35, e)) * r
	var kick: Vector2 = w.kick * sin(PI * minf(w.k / 0.3, 1.0)) * (1.0 - e)
	var s: float = w.s0 * (1.0 - 0.88 * e)
	return Transform2D(w.rot0 + w.spin * w.k, Vector2(s, s), 0.0, _drain + off + kick)

func _card_xf() -> Transform2D:
	return Transform2D(card_rot, Vector2(card_scale, card_scale), 0.0, card_pos)

## The discovery strip slot of tier t, in world coordinates (the HUD is screen space).
func _strip_slot(t: int) -> Vector2:
	var vs := get_viewport_rect().size
	var n: int = Cfg.max_tier()
	var step := minf(104.0, (vs.x - 80.0) / n)
	var screen := Vector2(vs.x * 0.5 - step * (n - 1) * 0.5 + (t - 1) * step, 272.0)
	return get_canvas_transform().affine_inverse() * screen

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if mode == Mode.NONE:
		return
	if dim > 0.0:
		draw_rect(Rect2(-1400, -2200, 3880, 6400), Color(0.03, 0.04, 0.1, dim))
	var card := _card_xf()
	var torn := _flush_t >= _shake_time
	if (mode == Mode.REVEAL or mode == Mode.FLUSHING) and _revealed and not torn:    # light rays behind the card
		draw_set_transform_matrix(card)
		var spin := _t * 0.35
		for i in 16:
			var a0 := spin + TAU * i / 16.0
			var pts := PackedVector2Array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * 1100.0, Vector2(cos(a0 + 0.17), sin(a0 + 0.17)) * 1100.0])
			draw_colored_polygon(pts, Color(1.0, 0.85, 0.35, 0.22 if i % 2 == 0 else 0.1))
	if not torn:    # drop shadow
		var sh := card * Transform2D(0.0, Vector2(0, 16))
		draw_set_transform_matrix(sh)
		var s2 := StyleBoxFlat.new()
		s2.bg_color = Color(0, 0, 0, 0.35)
		s2.set_corner_radius_all(48)
		draw_style_box(s2, Rect2(-_size * 0.5, _size))
	for p in _parts:
		var xf: Transform2D
		var alpha := 1.0
		if p.detached:
			xf = _piece_xf(p)
			alpha = clampf((1.0 - p.w.k) / 0.18, 0.0, 1.0)
			if alpha <= 0.0:
				continue
		else:
			var ps := _appear(p)
			if ps <= 0.0:
				continue
			var wob := 0.0
			if p.kind == "glyph":
				wob = sin(_t * 6.0 + p.pos.x * 0.05) * 0.06
			elif p.kind == "star":
				wob = _t * p.spin
			var sq := Vector2(ps, ps)
			if p.kind == "pic":    # the object squashes a little as it lands (and again on the reveal flash)
				var bounce := sin(_t * 9.0) * exp(-_t * 2.5) * 0.12 + _flash * 0.15
				sq = Vector2(1.0 + bounce, 1.0 - bounce) * ps
			xf = card * Transform2D(p.rot + wob, sq, 0.0, p.pos + p.jit)
		draw_set_transform_matrix(xf)
		_draw_part(p, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flash > 0.0:
		draw_rect(Rect2(-1400, -2200, 3880, 6400), Color(1, 1, 0.9, _flash * 0.6))

## Pop-in scale of a piece (0 = not there yet): a quick overshoot after its delay.
func _appear(p: Dictionary) -> float:
	var k := clampf((_t - float(p.delay)) / 0.3, 0.0, 1.0)
	if k <= 0.0:
		return 0.0
	var c1 := 2.4
	return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)

func _draw_part(p: Dictionary, alpha: float) -> void:
	match p.kind:
		"chunk":
			var sb: StyleBoxFlat = p.sb
			var r := Rect2(-p.size * 0.5, p.size)
			if alpha < 1.0:
				sb = sb.duplicate()
				sb.bg_color.a = alpha
				sb.border_color.a = alpha
			draw_style_box(sb, r)
		"pic":
			var r := Rect2(-p.size * 0.5, p.size)
			var dark := mode == Mode.REVEAL and not _revealed
			var col := Color(0.06, 0.06, 0.12, alpha) if dark else Color(1, 1, 1, alpha)
			if p.tex:
				draw_texture_rect(p.tex, r, false, col)
			else:
				draw_circle(Vector2.ZERO, p.size.y * 0.4, Color(p.color, alpha))
			if dark:
				_str("?", Vector2.ZERO, 150, Color(1, 1, 1, 0.85), 18)
		"glyph", "word":
			_str(p.text, Vector2.ZERO, p.fsize, Color(p.color, alpha), 12 if p.kind == "glyph" else 0)
		"footer":
			var a := alpha * (0.6 + 0.4 * sin(_t * 5.0)) if mode != Mode.INTRO else alpha
			_str(p.text, Vector2.ZERO, p.fsize, Color(p.color, p.color.a * a), 0)
		"ribbon":
			var r := Rect2(-p.size * 0.5, p.size)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(p.color, alpha)
			sb.border_color = Color(INK, alpha)
			sb.set_border_width_all(9)
			sb.set_corner_radius_all(30)
			draw_style_box(sb, r)
			var size := 54
			var tw := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if tw > p.size.x - 50:
				size = int(size * (p.size.x - 50) / tw)
			_str(p.text, Vector2(0, 0), size, Color(1, 1, 1, alpha), 12)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var rr: float = p.r if i % 2 == 0 else p.r * 0.45
				var a := -PI * 0.5 + TAU * i / 10.0
				pts.append(Vector2(cos(a), sin(a)) * rr)
			var outline := PackedVector2Array()
			for v in pts:
				outline.append(v * 1.25)
			draw_colored_polygon(outline, Color(INK, alpha))
			draw_colored_polygon(pts, Color(p.color, alpha))

## Text centred on c (vertically by its cap height).
func _str(s: String, c: Vector2, size: int, col: Color, outline: int) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var q := c + Vector2(-w * 0.5, size * 0.35)
	if outline > 0:
		draw_string_outline(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(INK, col.a))
	draw_string(font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.INTRO or _closing:
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if tap:
		get_viewport().set_input_as_handled()
		dismiss()
