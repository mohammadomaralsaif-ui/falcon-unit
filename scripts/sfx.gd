extends Node
## Procedurally generated sound effects (no audio files needed).

const RATE := 22050
var streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []

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
	streams["screech"] = _screech()
	streams["crash"] = _crash(1.0)
	streams["crash_small"] = _crash(0.45)
	streams["horn"] = _horn()
	streams["step"] = _step()
	streams["flesh"] = _flesh()
	streams["reload"] = _reload()
	streams["ambience"] = _ambience()
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 10:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 120.0
		add_child(p3)
		_pool3d.append(p3)

## Positional one-shot (panned + attenuated by the engine).
func play_3d(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	for p in _pool3d:
		if not p.playing:
			p.stream = streams[name]
			p.global_position = pos
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return

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
	## V6-ish rumble: firing pulses at 3x the crank frequency + exhaust noise. 1 s loop of whole cycles.
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var crank := 30.0
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t * crank * 3.0, 1.0)
		var pulse := exp(-ph * 9.0) * (1.0 if int(t * crank * 3.0) % 3 != 1 else 0.8)
		var hum := sin(TAU * crank * t) * 0.35 + sin(TAU * crank * 2.0 * t) * 0.2
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.08
		lp2 += ((pulse * 1.2 + hum + lp * 0.5) - lp2) * 0.25
		s[i] = lp2 * 0.55
	return _wav(s, true)

func _screech() -> AudioStreamWAV:
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 2100.0 + sin(TAU * 7.0 * t) * 160.0 + sin(TAU * 13.0 * t) * 90.0
		ph += TAU * f / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.5
		s[i] = (sin(ph) * 0.45 + lp * 0.25) * (0.8 + 0.2 * sin(TAU * 3.0 * t))
	return _wav(s, true)

func _crash(power: float) -> AudioStreamWAV:
	## metal crunch: noise burst + inharmonic clangs + glass tinkle
	var dur := 0.6 + power * 0.9
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var freqs := [143.0, 271.0, 389.0, 617.0, 1033.0]
	for i in n:
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.35
		var v := lp * exp(-t * 7.0) * 1.1
		v += sin(TAU * 55.0 * t) * exp(-t * 12.0) * 0.9 * power
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t + k) * exp(-t * (5.0 + k * 2.0)) * 0.18
		if t > 0.08 and randf() < 0.004 * power:
			v += randf_range(-0.6, 0.6)
		s[i] = v * 0.8
	return _wav(s)

func _horn() -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t * 40.0, 1.0) * minf((0.55 - t) * 30.0, 1.0)
		var a := signf(sin(TAU * 420.0 * t)) * 0.5 + signf(sin(TAU * 525.0 * t)) * 0.5
		s[i] = a * 0.22 * env
	return _wav(s)

func _step() -> AudioStreamWAV:
	var n := int(0.09 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.25
		s[i] = lp * exp(-t * 60.0) * 0.8
	return _wav(s)

func _flesh() -> AudioStreamWAV:
	var n := int(0.16 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.12
		s[i] = (lp * 1.4 + sin(TAU * 90.0 * t) * 0.6) * exp(-t * 28.0)
	return _wav(s)

func _reload() -> AudioStreamWAV:
	var n := int(1.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for c in [0.05, 0.45, 0.95, 1.05]:
		var st := int(c * RATE)
		for i in int(0.05 * RATE):
			if st + i < n:
				var t := float(i) / RATE
				s[st + i] += (sin(TAU * 2400.0 * t) * 0.5 + (randf() - 0.5)) * exp(-t * 90.0) * 0.6
	return _wav(s)

func _ambience() -> AudioStreamWAV:
	## distant city: low traffic rumble with the odd far-away horn and bird chirp. 8 s loop.
	var n := RATE * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.02
		lp2 += (lp - lp2) * 0.3
		var v := lp2 * 2.2
		var hp := fmod(t, 8.0)
		if hp > 2.0 and hp < 2.35:
			v += signf(sin(TAU * 380.0 * t)) * 0.03
		if hp > 5.1 and hp < 5.3:
			v += sin(TAU * (3200.0 + 900.0 * sin(TAU * 12.0 * t)) * t) * 0.025 * sin(PI * (hp - 5.1) / 0.2)
		s[i] = v
	return _wav(s, true)
