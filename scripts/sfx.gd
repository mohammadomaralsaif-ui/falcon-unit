extends Node
## Procedurally generated sound effects (no audio files needed).

const RATE := 22050
var streams := {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	streams["rifle"] = _shot(0.22, 1.0, 140.0)
	streams["pistol"] = _shot(0.16, 0.8, 180.0)
	streams["far"] = _shot(0.3, 0.45, 90.0, true)
	streams["boom"] = _shot(1.2, 1.0, 55.0, true)
	streams["click"] = _tone(0.04, 1800.0, 1200.0, 0.4, true)
	streams["beep"] = _tone(0.12, 1400.0, 1400.0, 0.35, true)
	streams["hit"] = _tone(0.05, 1600.0, 1400.0, 0.4, true)
	streams["cuff"] = _tone(0.15, 2200.0, 1700.0, 0.3, true)
	streams["siren"] = _siren()
	streams["engine"] = _engine()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	for p in _pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return

func play_at(name: String, pos: Vector3, listener: Vector3, base_db := 0.0) -> void:
	var d := pos.distance_to(listener)
	var db := base_db - d * 0.35
	if db > -40.0:
		play(name, db, randf_range(0.9, 1.1))

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _shot(dur: float, vol: float, thump: float, muffled := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * (6.0 if muffled else 18.0))
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * (0.12 if muffled else 0.55)
		var body := sin(TAU * thump * t * (1.0 - t)) * exp(-t * 9.0)
		s[i] = (lp * env * 0.9 + body * 0.7) * vol
	return _wav(s)

func _tone(dur: float, f0: float, f1: float, vol: float, square := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * lerp(f0, f1, k) / RATE
		var v := sin(ph)
		if square:
			v = sign(v)
		s[i] = v * vol * (1.0 - k)
	return _wav(s)

func _siren() -> AudioStreamWAV:
	var n := RATE * 3
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 900.0 + 400.0 * sin(TAU * t / 3.0)
		ph += TAU * f / RATE
		s[i] = (abs(fmod(ph / TAU, 1.0) * 2.0 - 1.0) * 2.0 - 1.0) * 0.25
	return _wav(s, true)

func _engine() -> AudioStreamWAV:
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var saw := fmod(t * 50.0, 1.0) * 2.0 - 1.0
		var saw2 := fmod(t * 100.0, 1.0) * 2.0 - 1.0
		lp += ((saw * 0.6 + saw2 * 0.3 + (randf() - 0.5) * 0.2) - lp) * 0.15
		s[i] = lp * 0.5
	return _wav(s, true)
