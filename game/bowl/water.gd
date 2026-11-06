class_name Water
extends Node2D
## The toilet water as a gameplay system (no fluid simulation):
## * `volume` = water area in the bowl (px^2). Surface height = level_for_volume(volume + displaced area of submerged
##   objects), so sunken junk visibly raises the water.
## * ARCADE PRESSURE (PoC 3): `obstruction` = smoothed coverage of the drain region. Above `rise_from` the water RISES
##   (faster the worse the clog) - the water level is the game's timer; below it the water recovers toward rest.
## * EMERGENCY FLUSH: strong vortex; the drain removes `outflow_rate * (1 - blockage)` down to a floor under rest, so a
##   cleared drain empties fast. Whatever reaches the outlet is lost (no points). Afterwards the tank refills to rest.
## * Blockage = how much of the funnel/outlet cross-section objects cover (physics point queries on horizontal lines).
##   A single object covering a line is the PLUG: flush pressure (higher when the water is high) fills its squeeze
##   gauge; at 100 % it is squeezed through the outlet (pressure-based passage: every tier is flushable).
## * Per object: buoyancy + drag on each submerged sample point, vortex suction + swirl during a flush.

signal squeezed(obj: FlushObject)
signal cleared                         # the drain went from clogged to clear (sound + small cue)
signal splashed(pos: Vector2, strength: float)

var geo: BowlGeometry
var bowl: Bowl
var game: Node
var cfg: Dictionary
var fl: Dictionary
var dr: Dictionary
var volume := 0.0
var rest_volume := 0.0
var displaced := 0.0
var level_y := 0.0
var rest_y := 0.0
var overflow_y := 0.0
var flush_t := -1.0
var _dur := 3.0                       # vortex length of the current flush (the royal flush is longer)
var cooldown := 0.0
var blockage := 0.0
var obstruction := 0.0                 # smoothed 0..1 obstruction of the drain region: drives the rising water
var frozen := false                    # royal finale: the water never rises
var _clogged := false
var pressure := 0.0
var plug: FlushObject
var flushes := 0
var _cols := PackedFloat32Array()
var _colv := PackedFloat32Array()
var _col_x0 := 60.0
var _col_x1 := 1020.0
var _swirl := 0.0
var _bubbles: Array = []
var _gate_wait := 0.0
var _query := PhysicsPointQueryParameters2D.new()

func _ready() -> void:
	geo = Cfg.geo
	cfg = Cfg.c.water
	fl = Cfg.c.flush
	dr = Cfg.c.drain
	rest_y = Cfg.bowl.rest_level_y
	overflow_y = Cfg.bowl.overflow_y
	rest_volume = geo.volume_at_level(rest_y)
	volume = rest_volume
	level_y = rest_y
	var n: int = cfg.ripple_columns
	_cols.resize(n)
	_colv.resize(n)
	_query.collision_mask = Cfg.LAYER_OBJECTS
	_query.collide_with_areas = false

# ------------------------------------------------------------------ flush API

func flushing() -> bool:
	return flush_t >= 0.0

func can_flush() -> bool:
	return not flushing() and cooldown <= 0.0

## 0..1 readiness for the HUD button.
func flush_ready_frac() -> float:
	if flushing():
		return 0.0
	return 1.0 - clampf(cooldown / maxf(fl.cooldown, 0.01), 0.0, 1.0)

## Rising speed now (px^2/s of water, 0 when not rising).
func rise_rate() -> float:
	if frozen or flushing():
		return 0.0
	var f: float = cfg.rise_from
	if obstruction <= f:
		return 0.0
	var x := clampf((obstruction - f) / (1.0 - f), 0.0, 1.0)
	return lerpf(float(cfg.rise_min), float(cfg.rise_max), pow(x, float(cfg.rise_curve)))

## A sacrificed object (lost down the drain in an emergency flush) takes water with it: the bowl drops noticeably.
func drain_for_sacrifice(area: float) -> void:
	volume = maxf(geo.volume_at_level(rest_y + float(fl.floor_below_rest)), volume - minf(area * float(cfg.sacrifice_drain), float(cfg.sacrifice_drain_max)))

## The royal flush may interrupt an emergency flush.
func stop_flush() -> void:
	flush_t = -1.0
	cooldown = 0.0

func start_flush(duration := -1.0) -> bool:
	if not can_flush():
		return false
	_dur = duration if duration > 0.0 else float(fl.duration)
	flush_t = 0.0
	flushes += 1
	bowl.set_gate_open(true)
	pass   # sound chosen by the caller (emergency flush vs royal flush)
	return true

## Siphon in the outlet: runs a little longer than the vortex so whatever reached the pipe is carried away.
func siphon() -> float:
	if not flushing():
		return 0.0
	return clampf(minf(flush_t / float(fl.ramp_in), (_dur + float(fl.siphon_tail) - flush_t) / 0.3), 0.0, 1.0)

func strength() -> float:
	if not flushing() or flush_t > _dur:
		return 0.0
	var d: float = _dur
	if flush_t < fl.ramp_in:
		return flush_t / fl.ramp_in
	if flush_t > d - fl.ramp_out:
		return clampf((d - flush_t) / fl.ramp_out, 0.0, 1.0)
	return 1.0

## Where the water surface physically is: the level, but never above the rim (above it the water spills over).
func surface_level() -> float:
	return maxf(level_y, geo.rim_y - 12.0)

## 0 at rest level, 1 at the overflow line.
func fill_frac() -> float:
	return (rest_y - level_y) / (rest_y - overflow_y)

func surface_y(x: float) -> float:
	var f := clampf((x - _col_x0) / (_col_x1 - _col_x0), 0.0, 1.0) * (_cols.size() - 1)
	var i := int(f)
	var h := lerpf(_cols[i], _cols[mini(i + 1, _cols.size() - 1)], f - i)
	var dip := strength() * 70.0 * exp(-pow((x - geo.cx) / 210.0, 2.0))
	return surface_level() + h + dip

# ------------------------------------------------------------------ simulation

func _physics_process(dt: float) -> void:
	_update_flow(dt)
	volume = minf(volume, geo.volume_at_level(geo.rim_y - 40.0))   # anything more spills onto the floor
	_apply_forces(dt)
	var target := geo.level_for_volume(volume + displaced)
	level_y = lerpf(level_y, target, 1.0 - exp(-float(cfg.level_smoothing) * dt))
	_update_blockage()
	_update_squeeze(dt)
	_update_gate(dt)
	_update_ripples(dt)
	queue_redraw()

func _update_flow(dt: float) -> void:
	if flushing():
		if flush_t < fl.inflow_time and float(fl.inflow_total) > 0.0:
			volume += float(fl.inflow_total) / float(fl.inflow_time) * dt
		if flush_t < _dur:
			var floor_v := geo.volume_at_level(rest_y + float(fl.floor_below_rest))
			if volume > floor_v:
				volume = maxf(floor_v, volume - float(fl.outflow_rate) * (1.0 - blockage * (1.0 - float(fl.leak_past_plug))) * dt)
		flush_t += dt
		if flush_t >= _dur + float(fl.siphon_tail):
			flush_t = -1.0
			cooldown = fl.cooldown
		return
	cooldown = maxf(0.0, cooldown - dt)
	var rise := rise_rate()
	if rise > 0.0:
		volume += rise * dt
	elif volume < rest_volume:
		volume = minf(rest_volume, volume + float(cfg.refill_rate) * dt)
	elif volume > rest_volume:
		volume = maxf(rest_volume, volume - float(cfg.recover_rate) * dt)

func _apply_forces(_dt: float) -> void:
	var g: float = ProjectSettings.get_setting("physics/2d/default_gravity")
	var rho: float = cfg.density
	var surface := surface_level()
	var s := strength()
	var sip := siphon()
	var drain := Vector2(geo.cx, geo.throat_y - 10.0)
	var disp := 0.0
	for o: FlushObject in game.objects:
		if o.held or not is_instance_valid(o):
			continue
		var xf := o.global_transform
		var n := o.samples.size()
		var a_i := o.area / n
		var w_i := rho * a_i / 1000.0      # mass of the displaced water: currents push volume, like buoyancy
		var sub := 0
		for lp in o.samples:
			var p := xf * lp
			if p.y <= surface or p.y > geo.outlet_bottom:
				continue
			sub += 1
			var f := Vector2(0.0, -rho * g * a_i / 1000.0)
			if sip > 0.0 and not o.passing:
				if p.y < geo.throat_y:
					var k := 1.0 / (1.0 + p.distance_to(drain) / float(fl.falloff))
					var dx := p.x - geo.cx
					var down := float(fl.radial) * (0.4 + 0.6 * exp(-pow(dx / float(fl.axis_width), 2.0)))
					var side := -dx * float(fl.center_pull) + float(fl.tangential) * sin(_swirl * float(fl.swirl_speed) + o.swirl_phase)
					f += Vector2(side, down) * k * s * w_i
				else:
					f += Vector2((geo.cx - p.x) * 6.0, float(fl.outlet_pull)) * sip * w_i
			o.apply_force(f, p - o.global_position)
		var frac := float(sub) / n
		o.sub_frac = frac
		if o.global_position.y < geo.throat_y:
			disp += o.area * frac
		if frac > 0.0:
			o.apply_central_force(-o.linear_velocity * float(cfg.linear_drag) * o.mass * frac)
			var inertia := o.mass * o.area / TAU
			o.apply_torque(-o.angular_velocity * float(cfg.angular_drag) * inertia * frac)
			if s > 0.0 and not o.passing:   # the whirlpool tumbles everything in it
				o.apply_torque(float(fl.spin_torque) * float(cfg.angular_drag) * inertia * frac * s)
		if o.passing:
			var want := Vector2((geo.cx - o.global_position.x) * 5.0, float(dr.pass_speed))
			o.apply_central_force((want - o.linear_velocity) * 8.0 * o.mass)
		var under := o.global_position.y > surface
		if under and not o.was_under and o.linear_velocity.y > float(cfg.splash_speed):
			_splash(o.global_position.x, o.linear_velocity.y * sqrt(o.mass) * 0.02)
		o.was_under = under
	displaced = disp

func _splash(x: float, power: float) -> void:
	var f := clampf((x - _col_x0) / (_col_x1 - _col_x0), 0.0, 1.0) * (_cols.size() - 1)
	var i := int(round(f))
	var p := clampf(power, 40.0, 900.0)
	for j in range(-2, 3):
		var k := i + j
		if k >= 0 and k < _cols.size():
			_colv[k] += p * (1.0 - absf(j) * 0.35)
	splashed.emit(Vector2(x, surface_level()), p)

func _update_blockage() -> void:
	var space := get_world_2d().direct_space_state
	var n: int = dr.samples
	var ys: Array[float] = []
	var y: float = dr.check_from_y
	while y < geo.throat_y:
		ys.append(y)
		y += float(dr.check_step)
	ys.append(geo.throat_y + 40.0)
	ys.append(geo.throat_y + 95.0)
	var worst := 0.0
	var low_cover: Array[float] = []      # coverage of the lines near the throat (the real bottleneck)
	var best_plug: FlushObject = null
	var best_plug_cover := 0.0
	var line_cover := {}
	for ly in ys:
		var xl := geo.x_left(ly) + 4.0
		var xr := geo.x_right(ly) - 4.0
		var covered := 0
		var per := {}
		for i in n:
			_query.position = Vector2(lerpf(xl, xr, (i + 0.5) / n), ly)
			var hits := space.intersect_point(_query, 1)
			if hits.size() > 0:
				covered += 1
				var c = hits[0].collider
				per[c] = per.get(c, 0) + 1
		worst = maxf(worst, float(covered) / n)
		if ly >= geo.throat_y - float(dr.obstruct_above):
			low_cover.append(float(covered) / n)
		for c in per:
			var cov := float(per[c]) / n
			line_cover[c] = maxf(line_cover.get(c, 0.0), cov)
			if c is FlushObject and not c.passing and cov >= float(dr.plug_cover) and cov >= best_plug_cover:
				best_plug = c
				best_plug_cover = cov
	# a resting object too wide for the drain that spans much of a funnel line is wedged: it seals the funnel even
	# where the sample line slips past its contact points
	if best_plug == null:
		var lowest := -INF
		for c in line_cover:
			if c is FlushObject and not c.passing and line_cover[c] >= float(dr.plug_line_cover) \
					and c.extent_x() > geo.drain_w and c.linear_velocity.length() < float(dr.plug_max_speed) and c.global_position.y > lowest:
				best_plug = c
				lowest = c.global_position.y
	plug = best_plug
	blockage = maxf(worst, float(dr.plug_seal)) if plug else worst
	var raw := 0.0
	for c in low_cover:
		raw += c / maxf(low_cover.size(), 1.0)
	if plug:   # a wedged plug: the wider it is compared to the drain, the worse (textbook = partial, university = severe)
		var k := clampf(plug.extent_x() / (geo.drain_w * float(dr.plug_full_width)), float(dr.plug_min_share), 1.0)
		raw = maxf(raw, float(dr.plug_seal) * k)
	var dt := get_physics_process_delta_time()
	obstruction = lerpf(obstruction, raw, 1.0 - exp(-dt / float(dr.obstruct_tau)))
	if obstruction > float(dr.clog_above):
		_clogged = true
	elif _clogged and obstruction < float(dr.clear_below):
		_clogged = false
		volume = maxf(rest_volume, volume - float(cfg.clear_drop))   # the plug is gone: the water gulps away at once
		cleared.emit()

func _update_squeeze(dt: float) -> void:
	var s := strength()
	pressure = s * (1.0 + float(dr.max_pressure_bonus) * clampf(fill_frac(), 0.0, 1.0))
	for o: FlushObject in game.objects:
		if o.passing:
			continue
		# the sealing plug, or anything too wide for the drain that the current holds against the throat
		var stuck := o == plug and o.linear_velocity.length() < float(dr.plug_max_speed) * 1.5
		stuck = stuck or (s > 0.0 and _lodged(o))
		o.is_plug = o == plug or (stuck and s > 0.0)
		if s > 0.0 and stuck:
			o.squeeze += dt * pressure / float(o.def.resistance)
			if o.squeeze >= 1.0:
				o.squeeze = 1.0
				o.start_passing()
				squeezed.emit(o)
				if o == plug:
					plug = null
		else:
			o.squeeze = maxf(0.0, o.squeeze - float(dr.squeeze_decay) * dt)

## Held at the throat by the flush current: near the drain, wider than it, not flying past.
func _lodged(o: FlushObject) -> bool:
	var p := o.global_position
	return p.y > geo.throat_y - float(dr.lodge_zone) and p.y < geo.throat_y + 60.0 and absf(p.x - geo.cx) < geo.drain_w \
		and o.extent_x() > geo.drain_w * 0.95 and o.linear_velocity.length() < float(dr.lodge_max_speed)

func _update_gate(dt: float) -> void:
	if flushing() or not bowl.gate_open():
		_gate_wait = 0.0
		return
	# close the water seal only when nothing straddles it (no object gets trapped in the bar)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(geo.drain_w + 20.0, 60.0)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, Vector2(geo.cx, bowl.gate_y + 15.0))
	q.collision_mask = Cfg.LAYER_OBJECTS
	_gate_wait += dt
	if get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty() or _gate_wait > 6.0:
		bowl.set_gate_open(false)

func _update_ripples(dt: float) -> void:
	var n := _cols.size()
	var k: float = cfg.ripple_stiffness
	var damp: float = cfg.ripple_damping
	var spread: float = cfg.ripple_spread
	var steps := 2
	var h := dt / steps
	for _s in steps:
		for i in n:
			var l := _cols[maxi(i - 1, 0)]
			var r := _cols[mini(i + 1, n - 1)]
			var a := -k * _cols[i] - damp * _colv[i] + spread * k * 4.0 * (l + r - 2.0 * _cols[i])
			_colv[i] += a * h
		for i in n:
			_cols[i] = clampf(_cols[i] + _colv[i] * h, -34.0, 34.0)
	var s := strength()
	if rise_rate() > 0.0 and randf() < 0.25 + obstruction * 0.5:
		_bubbles.append({"p": Vector2(geo.cx + randf_range(-50, 50), geo.throat_y - randf_range(10, 60)), "r": randf_range(4, 10), "t": 0.0})
	if s > 0.0:
		_swirl += dt * s
		for i in n:  # churning surface during a flush
			_colv[i] += sin(_swirl * 10.0 + i * 0.7) * 40.0 * s * dt * 10.0
		if randf() < s * 0.6:
			_bubbles.append({"p": Vector2(geo.cx + randf_range(-60, 60), geo.throat_y - randf_range(0, 120)), "r": randf_range(5, 13), "t": 0.0})
	for b in _bubbles:
		b.t += dt
		b.p += Vector2(sin(b.t * 9.0) * 30.0 * dt, -160.0 * dt)
	_bubbles = _bubbles.filter(func(b): return b.t < 1.6 and b.p.y > level_y + 6.0)

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var top := surface_level()
	var surf := PackedVector2Array()
	var xl := geo.x_left(top)
	var xr := geo.x_right(top)
	var steps := maxi(8, int((xr - xl) / 18.0))
	for i in steps + 1:
		var x := lerpf(xl, xr, float(i) / steps)
		var edge := minf(1.0, minf(x - xl, xr - x) / 40.0)  # ripples fade into the walls
		surf.append(Vector2(x, lerpf(top, surface_y(x), edge)))
	var poly := surf.duplicate()
	for p in geo.right:
		if p.y > top + 2.0:
			poly.append(p)
	var floor_y: float = Cfg.bowl.floor_y
	poly.append(Vector2(geo.cx + geo.drain_w * 0.5, floor_y))
	poly.append(Vector2(geo.cx - geo.drain_w * 0.5, floor_y))
	for i in range(geo.left.size() - 1, -1, -1):
		if geo.left[i].y > top + 2.0:
			poly.append(geo.left[i])
	var col := Color(0.22, 0.58, 0.96, 0.42).lerp(Color(0.45, 0.5, 0.3, 0.5), clampf(obstruction - 0.3, 0.0, 0.6))
	if Geometry2D.triangulate_polygon(poly).size() > 0:
		draw_colored_polygon(poly, col)
	draw_polyline(surf, Color(0.9, 0.97, 1.0, 0.95), 6.0, true)
	var under := PackedVector2Array()
	for p in surf:
		under.append(p + Vector2(0, 14))
	draw_polyline(under, Color(1, 1, 1, 0.18), 10.0, true)
	var s := strength()
	if s > 0.02:
		_draw_swirl(s)
	for b in _bubbles:
		draw_arc(b.p, b.r, 0, TAU, 12, Color(1, 1, 1, 0.6 * (1.0 - b.t / 1.6)), 2.5)
	if level_y < geo.rim_y:   # spilling over the rim on both sides
		var amt := clampf((geo.rim_y - level_y) / 60.0, 0.25, 1.0)
		var t := Time.get_ticks_msec() * 0.001
		for side in [-1.0, 1.0]:
			var x0 := geo.x_left(geo.rim_y) if side < 0.0 else geo.x_right(geo.rim_y)
			var pts := PackedVector2Array()
			for j in 14:
				var y := geo.rim_y - 50.0 + j * 70.0
				pts.append(Vector2(x0 + side * (40.0 + 30.0 * sin(j * 0.9 - t * 9.0) * 0.3 + j * 3.0), y))
			draw_polyline(pts, Color(0.35, 0.65, 1.0, 0.75), 26.0 * amt, true)
			draw_polyline(pts, Color(0.85, 0.95, 1.0, 0.8), 8.0 * amt, true)
	# overflow line (dashed) - brighter as the water approaches it
	var near := clampf(fill_frac(), 0.0, 1.0)
	var oc := Color(1.0, 0.2, 0.15, 0.25 + 0.6 * near * near)
	var x := geo.x_left(overflow_y) + 6.0
	while x < geo.x_right(overflow_y) - 6.0:
		draw_line(Vector2(x, overflow_y), Vector2(minf(x + 26.0, geo.x_right(overflow_y)), overflow_y), oc, 5.0)
		x += 44.0
	# subtle clog cue at the drain: a dark murky glow that grows with the obstruction and pulses while the water rises
	if obstruction > 0.2:
		var k := clampf((obstruction - 0.2) / 0.8, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.004 + 0.01 * k))
		var r := 55.0 + 45.0 * k + 12.0 * pulse * k
		draw_circle(Vector2(geo.cx, geo.throat_y - 10.0), r, Color(0.35, 0.22, 0.12, 0.10 + 0.22 * k))
		if rise_rate() > 0.0:
			draw_arc(Vector2(geo.cx, geo.throat_y - 10.0), r + 6.0, 0, TAU, 32, Color(1.0, 0.35, 0.2, 0.15 + 0.25 * pulse * k), 5.0)

func _draw_swirl(s: float) -> void:
	var c := Vector2(geo.cx, geo.throat_y - 30.0)
	var arms := 7
	for k in arms:
		var line := PackedVector2Array()
		for j in 26:
			var f := j / 25.0
			var ang := -_swirl * 5.6 + k * TAU / arms + f * 3.4
			var rad := lerpf(430.0, 18.0, f)
			var p := c + Vector2(cos(ang) * rad * 1.15, sin(ang) * rad * 0.5 - rad * 0.35)
			if p.y > level_y + 8.0 and geo.inside(p):
				line.append(p)
			elif line.size() > 1:
				draw_polyline(line, Color(1, 1, 1, 0.35 * s), 4.0, true)
				line = PackedVector2Array()
			else:
				line = PackedVector2Array()
		if line.size() > 1:
			draw_polyline(line, Color(1, 1, 1, 0.35 * s), 4.0, true)
