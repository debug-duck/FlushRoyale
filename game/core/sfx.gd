extends Node
## Autoload `Sfx`: tiny code-generated sound effects (no audio assets in the PoC). Each sound is synthesised once
## into an AudioStreamWAV at start-up; a small player pool plays them with optional pitch variation.

const RATE := 22050
var streams := {}
var players: Array[AudioStreamPlayer] = []
var muted := false

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
