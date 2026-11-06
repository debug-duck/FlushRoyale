class_name Fx
extends Node2D
## Procedural effects drawn in one node: floating score text, merge pop rings, water droplets. Nothing pooled beyond a
## capped array - the PoC never has more than a few dozen at once.

const MAX_TEXTS := 8
const MAX_SPARKS := 240             # cascade bursts + confetti, capped (cheap on phones)
var sparks: Array = []
var texts: Array = []
var rings: Array = []
var drops: Array = []
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font

func text(pos: Vector2, s: String, col := Color.WHITE, size := 54) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.pop_front()
	texts.append({"p": pos, "s": s, "c": col, "size": size, "t": 0.0})

func pop(pos: Vector2, radius: float, col: Color) -> void:
	rings.append({"p": pos, "r": radius, "c": col, "t": 0.0})
	for i in 10:
		var a := TAU * i / 10.0 + randf() * 0.3
		drops.append({"p": pos + Vector2.from_angle(a) * radius * 0.6, "v": Vector2.from_angle(a) * randf_range(250, 520), "c": col.lightened(0.3), "r": randf_range(6, 11), "t": 0.0, "g": 900.0})

## Cascade burst: stars and sparks flying out of a merge, more and faster for bigger cascades.
func burst(pos: Vector2, count: int, col: Color, speed := 520.0) -> void:
	for i in count:
		if sparks.size() >= MAX_SPARKS:
			sparks.pop_front()
		var a := randf() * TAU
		var c := col.lerp(Color.WHITE, randf() * 0.5) if randf() < 0.7 else Color(1, 0.95, 0.6)
		sparks.append({"p": pos, "v": Vector2.from_angle(a) * randf_range(0.35, 1.0) * speed, "c": c, "r": randf_range(7, 15),
			"t": 0.0, "life": randf_range(0.6, 1.1), "spin": randf_range(-9, 9), "g": 700.0, "star": randf() < 0.55})

## Exceptional cascade: confetti raining over the visible area.
func confetti(area: Rect2, count: int) -> void:
	var cols := [Color(1, 0.3, 0.4), Color(1, 0.85, 0.2), Color(0.3, 0.8, 1), Color(0.5, 1, 0.5), Color(1, 0.5, 1)]
	for i in count:
		if sparks.size() >= MAX_SPARKS:
			sparks.pop_front()
		sparks.append({"p": Vector2(randf_range(area.position.x, area.end.x), area.position.y - randf_range(0, 300)),
			"v": Vector2(randf_range(-80, 80), randf_range(250, 520)), "c": cols.pick_random(), "r": randf_range(8, 13),
			"t": 0.0, "life": randf_range(1.8, 2.6), "spin": randf_range(-8, 8), "g": 60.0, "star": false, "confetti": true})

func splash(pos: Vector2, power: float) -> void:
	var n := clampi(int(power / 40.0), 3, 16)
	for i in n:
		var v := Vector2(randf_range(-260, 260), -randf_range(250, 380 + power * 0.8))
		drops.append({"p": pos + Vector2(randf_range(-30, 30), -4), "v": v, "c": Color(0.75, 0.9, 1.0, 0.9), "r": randf_range(5, 10), "t": 0.0, "g": 1600.0})

func _process(dt: float) -> void:
	for x in texts:
		x.t += dt
		x.p.y -= 90.0 * dt
	for x in rings:
		x.t += dt
	for d in drops:
		d.t += dt
		d.v.y += d.g * dt
		d.p += d.v * dt
	for sp in sparks:
		sp.t += dt
		sp.v.y += sp.g * dt
		sp.v *= 1.0 - 1.2 * dt if not sp.has("confetti") else 1.0
		sp.p += sp.v * dt
	sparks = sparks.filter(func(x): return x.t < x.life)
	texts = texts.filter(func(x): return x.t < 1.3)
	rings = rings.filter(func(x): return x.t < 0.35)
	drops = drops.filter(func(x): return x.t < 1.0)
	queue_redraw()

func _draw() -> void:
	for x in rings:
		var f: float = x.t / 0.35
		draw_arc(x.p, x.r * (0.8 + f * 0.9), 0, TAU, 40, Color(x.c, 1.0 - f), 14.0 * (1.0 - f) + 2.0)
	for d in drops:
		draw_circle(d.p, d.r * (1.0 - d.t * 0.6), Color(d.c, d.c.a * (1.0 - d.t)))
	for sp in sparks:
		var k: float = sp.t / sp.life
		var col := Color(sp.c, 1.0 - k * k)
		if sp.star:
			var pts := PackedVector2Array()
			var rot: float = sp.spin * sp.t
			for i in 8:
				var rr: float = sp.r * (1.0 - 0.5 * k) * (1.0 if i % 2 == 0 else 0.42)
				pts.append(sp.p + Vector2.from_angle(rot + TAU * i / 8.0) * rr)
			draw_colored_polygon(pts, col)
		elif sp.has("confetti"):
			var ang: float = sp.spin * sp.t
			var w: Vector2 = Vector2.from_angle(ang) * sp.r
			var h: Vector2 = Vector2.from_angle(ang + PI * 0.5) * sp.r * 0.45 * absf(sin(sp.t * 7.0 + sp.r))
			draw_colored_polygon(PackedVector2Array([sp.p - w - h, sp.p + w - h, sp.p + w + h, sp.p - w + h]), col)
		else:
			draw_circle(sp.p, sp.r * (1.0 - 0.6 * k), col)
	for x in texts:
		var a: float = clampf(1.6 - x.t * 1.3, 0.0, 1.0)
		var s := 1.0 + 0.35 * exp(-x.t * 10.0)
		var size := int(x.size * s)
		var w := font.get_string_size(x.s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var p: Vector2 = x.p - Vector2(w * 0.5, 0)
		draw_string_outline(font, p, x.s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, Color(0.1, 0.1, 0.18, a))
		draw_string(font, p, x.s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(x.c, a))
