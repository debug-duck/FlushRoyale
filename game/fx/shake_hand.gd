class_name ShakeHand
extends Node2D
## TOILET SHAKE bonus (earned by merges, see Game.add_shake): a giant cut-out engraving hand (Layer art, absurd 1970s collage
## animation style, moving in 12 fps stop-motion steps) comes down, grabs the bowl's rim and shakes the whole toilet.
## Physics: the bowl is jerked left/right `freq` times a second; in the bowl's frame everything inside lurches the other way:
## each object gets a velocity jolt per beat (sideways + an upward hop, with its own random share, so neighbours rub
## against each other -> new contacts -> merges) and a random spin; anything stuck in the drain is kicked up (unclogs). The camera shakes
## and tilts with it, the water sloshes. Numbers: config `shake`.

enum Phase { IDLE, REACH, GRAB, SHAKE, LIFT }

var game: Node
var phase := Phase.IDLE
var _t := 0.0                    # seconds in the current phase
var _shake_t := 0.0
var _beat := 0.0
var _dir := 1.0
var _cfg: Dictionary
var _open: Texture2D
var _grip: Texture2D
var _grip_at := Vector2(1000, 745)
var _draw_pos := Vector2.ZERO    # stop-motion: updated in steps only
var _draw_rot := 0.0
var _step_t := 0.0
var _jit := {}                   # object -> random 0..1 (phase/amplitude jitter)
var moved := {}                  # object -> max distance from where the shake found it (tests)
var _start_pos := {}
var _span := {}                  # texture -> Vector2(x0, x1) of the sleeve on its top row

func _ready() -> void:
	_cfg = Cfg.c.shake
	z_index = 25
	for n in ["hand_open", "hand_grip"]:
		var p := "res://assets/processed/ui/%s.png" % n
		if ResourceLoader.exists(p):
			if n == "hand_open":
				_open = load(p)
			else:
				_grip = load(p)
	_grip_at = Vector2(1080.0 - float(Cfg.bowl.inner_left[0][0]) + float(_cfg.grip_dx), float(Cfg.bowl.rim_y))
	for t in [_open, _grip]:
		if t:
			_span[t] = _sleeve_span(t)
	visible = false

func active() -> bool:
	return phase != Phase.IDLE

func start() -> void:
	if active():
		return
	phase = Phase.REACH
	_t = 0.0
	_shake_t = 0.0
	_beat = 0.0
	_jit.clear()
	moved.clear()
	_start_pos.clear()
	visible = true
	Sfx.play("whoosh", 0.7, -2.0)

func _physics_process(dt: float) -> void:
	if phase == Phase.IDLE:
		return
	_t += dt
	match phase:
		Phase.REACH:
			if _t >= float(_cfg.reach_time):
				_next(Phase.GRAB)
				Sfx.play("clunk", 0.6, 2.0)
				game.fx.text(Vector2(540, 640), Loc.t("TOILET SHAKE!"), Color(1.0, 0.75, 0.3), 96)
		Phase.GRAB:
			if _t >= float(_cfg.grab_pause):
				_next(Phase.SHAKE)
				Sfx.play("rattle", 1.15, 2.0)
				for o in game.objects:
					_start_pos[o] = o.global_position
		Phase.SHAKE:
			_shake(dt)
			if _t >= float(_cfg.duration):
				_next(Phase.LIFT)
				_camera(Vector2.ZERO, 0.0)
				Sfx.play("whoosh", 0.9, -4.0)
		Phase.LIFT:
			if _t >= float(_cfg.lift_time):
				phase = Phase.IDLE
				visible = false
	_update_visual(dt)

func _next(p: Phase) -> void:
	phase = p
	_t = 0.0

## One physics tick of shaking: pseudo-forces of a moving bowl on every free object.
func _shake(dt: float) -> void:
	var dur: float = _cfg.duration
	var k := clampf(_t / dur, 0.0, 1.0)
	var env := pow(sin(PI * k), 0.35)                 # quick ramp in and out
	var w := TAU * float(_cfg.freq)
	var kx: float = _cfg.kick_x
	var ky: float = _cfg.kick_y
	var jit: float = _cfg.jitter
	var spin: float = _cfg.spin
	var drain_y: float = float(Cfg.bowl.throat_y) - float(_cfg.unplug_above)
	_beat -= dt
	var beat := _beat <= 0.0
	if beat:
		_beat = 0.5 / float(_cfg.freq)
		_dir = -_dir
	for o in game.objects:
		if o.held or o.passing or not is_instance_valid(o):
			continue
		if not _jit.has(o):
			_jit[o] = randf()
			_start_pos[o] = o.global_position
		o.sleeping = false
		if beat:    # the bowl jerks one way: everything inside lurches the other way (and hops), each a bit differently
			var amp := 1.0 + randf_range(-jit, jit)
			o.linear_velocity = o.linear_velocity * float(_cfg.keep) + Vector2(_dir * kx * amp + randf_range(-0.35, 0.35) * kx, -ky * randf_range(0.35, 1.0)) * env
			o.angular_velocity += randf_range(-1.0, 1.0) * spin * env
		if beat and o.global_position.y > drain_y:    # stuck in the funnel / drain: knock it loose, upward
			var up: float = _cfg.unplug_speed
			o.linear_velocity = Vector2(randf_range(-0.4, 0.4) * up, minf(o.linear_velocity.y, -up * randf_range(0.7, 1.0)))
		var d: float = o.global_position.distance_to(_start_pos.get(o, o.global_position))
		moved[o] = maxf(float(moved.get(o, 0.0)), d)
	if beat:
		game.water.disturb(randf_range(250.0, 830.0), float(_cfg.slosh) * env)
		if randf() < 0.5:
			Sfx.play("clunk", randf_range(1.3, 1.9), -12.0)
	var cs: float = _cfg.camera_shake
	_camera(Vector2(sin(_t * w) * cs, absf(sin(_t * w * 2.0)) * cs * -0.5) * env, sin(_t * w) * float(_cfg.camera_tilt) * env)

func _camera(off: Vector2, rot: float) -> void:
	var cam: Camera2D = game.camera
	if not cam:
		return
	cam.ignore_rotation = false
	cam.offset = off
	cam.rotation = rot

## Stop-motion: the hand only moves on 12 fps steps (cut-out animation), snapping between poses.
func _update_visual(dt: float) -> void:
	_step_t -= dt
	if _step_t > 0.0:
		return
	_step_t = 1.0 / float(_cfg.anim_fps)
	var top := _grip_at + Vector2(60, -1500)
	match phase:
		Phase.REACH:
			var k := clampf(_t / float(_cfg.reach_time), 0.0, 1.0)
			_draw_pos = top.lerp(_grip_at, 1.0 - pow(1.0 - k, 2.0))
			_draw_rot = -0.12 * (1.0 - k)
		Phase.GRAB:
			_draw_pos = _grip_at + Vector2(0, 8)
			_draw_rot = 0.03
		Phase.SHAKE:
			var w := TAU * float(_cfg.freq)
			_draw_pos = _grip_at + Vector2(sin(_t * w) * 26.0, absf(sin(_t * w * 2.0)) * -14.0)
			_draw_rot = sin(_t * w) * 0.08
		Phase.LIFT:
			var k := clampf(_t / float(_cfg.lift_time), 0.0, 1.0)
			_draw_pos = _grip_at.lerp(top, k * k)
			_draw_rot = 0.1 * k
	queue_redraw()

func _draw() -> void:
	if phase == Phase.IDLE:
		return
	var gripping := phase == Phase.GRAB or phase == Phase.SHAKE
	var tex: Texture2D = _grip if gripping else _open
	if not tex:
		return
	var s: float = float(_cfg.hand_height) / tex.get_height()
	var size := tex.get_size() * s
	# the fist (or the fingertips) at the grip point, the sleeve going up out of the screen
	var anchor := Vector2(0.42, 0.8) if gripping else Vector2(0.45, 0.97)
	draw_set_transform(_draw_pos, _draw_rot, Vector2.ONE)
	var r := Rect2(-size * anchor, size)
	var sp: Vector2 = _span.get(tex, Vector2(0, tex.get_width()))    # the sleeve's top edge, stretched upward off-screen
	var sleeve := Rect2(Vector2(r.position.x + sp.x * s, r.position.y - 2400.0), Vector2((sp.y - sp.x) * s, 2404.0))
	draw_texture_rect_region(tex, sleeve, Rect2(Vector2(sp.x, 3), Vector2(sp.y - sp.x, 3)))
	draw_texture_rect(tex, r, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Opaque horizontal extent of the sleeve (a few px below the top edge), inset past its white paper border.
func _sleeve_span(tex: Texture2D) -> Vector2:
	var img := tex.get_image()
	if not img:
		return Vector2(0, tex.get_width())
	var y := 4
	var x0 := -1
	var x1 := -1
	for x in img.get_width():
		if img.get_pixel(x, y).a > 0.5:
			if x0 < 0:
				x0 = x
			x1 = x
	if x0 < 0:
		return Vector2(0, tex.get_width())
	return Vector2(x0 + 8, x1 - 8)
