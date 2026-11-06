extends Node
## Autoload `Sfx`: sound effects. The small ones are synthesised in code at start-up (pop, splash, launch, ...); the
## bigger ones are Sonilo clips in assets/audio/*.ogg (emergency flush, drain gulp, clog clear, cascade stings, royal
## fanfare, game-over sting, the rising-water loop). A small player pool plays one-shots; `set_danger()` drives the
## rising-water loop volume and a procedural danger tick that speeds up as the water nears the overflow line.

const RATE := 22050
var streams := {}
var players: Array[AudioStreamPlayer] = []
var muted := false
var _loop: AudioStreamPlayer
var _tick_t := 0.0
var _danger := 0.0
var _cascade: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams.pop = _make(0.16, func(t, u): return sin(TAU * (330.0 + 900.0 * u) * t) * (1.0 - u) * 0.7)
	streams.plop = _make(0.12, func(t, u): return sin(TAU * (520.0 - 300.0 * u) * t) * (1.0 - u) * 0.6)
	streams.splash = _make(0.35, func(t, u): return _noise() * pow(1.0 - u, 2.2) * 0.55)
	streams.launch = _make(0.14, func(t, u): return (sin(TAU * (180.0 + 500.0 * u) * t) * 0.5 + _noise() * 0.15) * (1.0 - u))
	streams.flush = _make(2.6, func(t, u): return _noise() * 0.45 * sin(PI * u) * (0.75 + 0.25 * sin(TAU * 7.0 * t)) + sin(TAU * (90.0 - 40.0 * u) * t) * 0.15 * sin(PI * u))
	streams.gurgle = _make(0.5, func(t, u): return sin(TAU * (140.0 + 60.0 * sin(TAU * 18.0 * t)) * t) * (1.0 - u) * 0.5)
	streams.squeeze = _make(0.6, func(t, u): return sin(TAU * (260.0 - 200.0 * u) * t + 3.0 * sin(TAU * 30.0 * t)) * (1.0 - u) * 0.6)
	streams.clunk = _make(0.18, func(t, u): return (sin(TAU * 95.0 * t) + _noise() * 0.3) * pow(1.0 - u, 3.0) * 0.6)
	streams.alarm = _make(0.25, func(t, u): return (1.0 if sin(TAU * 880.0 * t) > 0.0 else -1.0) * 0.18 * (1.0 if u < 0.8 else 0.0))
	streams.gameover = _make(1.2, func(t, u): return sin(TAU * (300.0 - 220.0 * u) * t) * (1.0 - u) * 0.5)
	streams.tick = _make(0.07, func(t, u): return sin(TAU * 1250.0 * t) * pow(1.0 - u, 2.0) * 0.35)
	# PoC 4 presentation cards (closed-form phases so the glides stay clean)
	streams.boing = _make(0.5, func(t, u): return sin(TAU * (170.0 * t + 640.0 * t * t / 1.0) + 2.5 * sin(TAU * 11.0 * t)) * pow(1.0 - u, 1.4) * 0.5 \
		+ (sin(TAU * 1318.0 * t) + 0.5 * sin(TAU * 1976.0 * t)) * exp(-maxf(t - 0.18, 0.0) * 9.0) * (0.22 if t > 0.18 else 0.0))
	streams.drumroll = _make(1.05, func(t, u): return (_noise() * pow(0.5 + 0.5 * sin(TAU * 31.0 * t), 2.0) * 0.5 + sin(TAU * 72.0 * t) * 0.12) * (0.2 + 0.8 * u))
	streams.rattle = _make(1.4, func(t, u): return (_noise() * (1.0 if sin(TAU * 17.0 * t) > 0.0 else 0.25) * 0.3 + sin(TAU * (120.0 * t) + 4.0 * sin(TAU * 9.0 * t)) * 0.12) * (0.3 + 0.7 * u))
	streams.slide_down = _make(1.3, func(t, u): return sin(TAU * (1500.0 * (1.0 - exp(-1.8 * t)) / 1.8 + 110.0 * t)) * pow(sin(PI * u), 0.5) * 0.32)
	streams.whoosh = _make(0.3, func(t, u): return _noise() * sin(PI * u) * 0.3)
	for f in DirAccess.get_files_at("res://assets/audio/"):
		var n := f.trim_suffix(".import")
		if n.ends_with(".ogg") and not streams.has(n.get_basename()):
			streams[n.get_basename()] = load("res://assets/audio/" + n)
	_cascade = AudioStreamPlayer.new()
	add_child(_cascade)
	_loop = AudioStreamPlayer.new()
	_loop.volume_db = -80.0
	add_child(_loop)
	if streams.has("water_rising"):
		var st: AudioStreamOggVorbis = streams.water_rising
		st.loop = true
		_loop.stream = st

func play(id: String, pitch := 1.0, volume_db := 0.0) -> void:
	if muted or not streams.has(id):
		return
	for p in players:
		if not p.playing:
			p.stream = streams[id]
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			return

## Cascade sting: the bigger the chain, the bigger the sting (and a little higher each step). Restarts, never stacks.
func cascade(chain: int, triple := false) -> void:
	if muted:
		return
	var id := "cascade_1"
	if chain >= 6:
		id = "cascade_3"
	elif chain >= 4 or triple:
		id = "cascade_2"
	if not streams.has(id):
		play("pop", 1.4)
		return
	_cascade.stream = streams[id]
	_cascade.pitch_scale = 1.0 + 0.06 * clampi(chain - (6 if chain >= 6 else (4 if chain >= 4 else 2)), 0, 4)
	_cascade.volume_db = -3.0
	_cascade.play()

## 0 = calm, 1 = about to overflow. `rising` = the water is currently going up.
func set_danger(level: float, rising: bool) -> void:
	_danger = clampf(level, 0.0, 1.2)
	if not _loop.stream:
		return
	var target := -80.0
	if rising and not muted:
		target = lerpf(-22.0, -4.0, clampf(_danger, 0.0, 1.0))
	if target > -79.0 and not _loop.playing:
		_loop.play()
	_loop.volume_db = lerpf(_loop.volume_db, target, 0.08)
	if _loop.volume_db < -70.0 and _loop.playing and target < -79.0:
		_loop.stop()

func stop_danger() -> void:
	_danger = 0.0
	if _loop:
		_loop.stop()
		_loop.volume_db = -80.0

func _process(dt: float) -> void:
	# procedural danger tick: from 60 % full it ticks, faster and higher as the water climbs
	if _danger < 0.6 or muted:
		_tick_t = 0.0
		return
	_tick_t -= dt
	if _tick_t <= 0.0:
		var k := clampf((_danger - 0.6) / 0.4, 0.0, 1.0)
		_tick_t = lerpf(0.9, 0.18, k)
		play("tick", 1.0 + 0.5 * k, lerpf(-10.0, -2.0, k))

func _noise() -> float:
	return randf() * 2.0 - 1.0

func _make(length: float, f: Callable) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(f.call(t, float(i) / n), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s
