class_name Fx
extends Node2D
## Procedural effects drawn in one node: floating score text, merge pop rings, water droplets. Nothing pooled beyond a
## capped array - the PoC never has more than a few dozen at once.

const MAX_TEXTS := 8
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
	for x in texts:
		var a: float = clampf(1.6 - x.t * 1.3, 0.0, 1.0)
		var s := 1.0 + 0.35 * exp(-x.t * 10.0)
		var size := int(x.size * s)
		var w := font.get_string_size(x.s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var p: Vector2 = x.p - Vector2(w * 0.5, 0)
		draw_string_outline(font, p, x.s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, Color(0.1, 0.1, 0.18, a))
		draw_string(font, p, x.s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(x.c, a))
