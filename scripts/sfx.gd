extends Node
## Procedurally generated sound effects (no audio files needed).

const RATE := 22050
var streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []

const BAKED := "res://assets/sfx/"

## Sounds are synthesised once on a PC (tools: tests/bake_sfx.tscn) and shipped as resources, so the
## phone doesn't spend seconds generating audio at start-up. Missing files are generated on the spot.
func _make(name: String) -> AudioStream:
	match name:
		"rifle": return _shot(0.22, 1.0, 140.0)
		"pistol": return _shot(0.16, 0.8, 180.0)
		"far": return _shot(0.3, 0.45, 90.0, true)
		"boom": return _shot(1.2, 1.0, 55.0, true)
		"click": return _tone(0.04, 1800.0, 1200.0, 0.4, true)
		"beep": return _tone(0.12, 1400.0, 1400.0, 0.35, true)
		"hit": return _tone(0.05, 1600.0, 1400.0, 0.4, true)
		"cuff": return _tone(0.15, 2200.0, 1700.0, 0.3, true)
		"siren": return _siren()
		"engine": return _engine()
		"screech": return _screech()
		"crash": return _crash(1.0)
		"crash_small": return _crash(0.45)
		"horn": return _horn()
		"step": return _step()
		"flesh": return _flesh()
		"reload": return _reload()
		"radio": return _radio()
		"ring": return _ring()
		"sniper": return _shot(0.9, 1.0, 95.0)
		"bolt": return _bolt()
		"sputter": return _sputter()
		"glass": return _glass()
		"ambience": return _ambience(false)
		"ambience_night": return _ambience(true)
	return null

const NAMES := ["rifle", "pistol", "far", "boom", "click", "beep", "hit", "cuff", "siren", "engine", "screech", "crash", "crash_small", "horn", "step", "flesh", "reload", "radio", "ring", "sniper", "bolt", "sputter", "glass"]

func _get_stream(name: String) -> AudioStream:
	var path := BAKED + name + ".res"
	if ResourceLoader.exists(path):
		return load(path)
	return _make(name)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# everything except dialogue goes through the "SFX" bus, which is turned down while someone speaks
	if AudioServer.get_bus_index("SFX") < 0:
		var bi := AudioServer.bus_count
		AudioServer.add_bus(bi)
		AudioServer.set_bus_name(bi, "SFX")
		AudioServer.set_bus_send(bi, "Master")
	for n in NAMES:
		streams[n] = _get_stream(n)
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in 10:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 120.0
		p3.bus = "SFX"
		add_child(p3)
		_pool3d.append(p3)

var _duck := 0.0

## Called every frame by the HUD: world sounds dip while a voice line is playing so speech stays clear.
func duck(speaking: bool, dt: float) -> void:
	_duck = move_toward(_duck, 1.0 if speaking else 0.0, dt * (6.0 if speaking else 1.5))
	var bi := AudioServer.get_bus_index("SFX")
	if bi >= 0:
		AudioServer.set_bus_volume_db(bi, -13.0 * _duck)

## City background loop, generated on first use (it is the biggest procedural sound).
func ambience(night: bool) -> AudioStreamWAV:
	var k := "ambience_night" if night else "ambience"
	if not streams.has(k):
		streams[k] = _get_stream(k)
	return streams[k]

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
	## V8-ish: firing pulses at 120 Hz with strong mid harmonics (phone speakers can't play deep bass),
	## exhaust rasp and intake hiss. 1 s loop of whole cycles so it loops without a click.
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var hp_prev := 0.0
	var crank := 30.0
	for i in n:
		var t := float(i) / RATE
		var fire := t * crank * 4.0
		var ph := fmod(fire, 1.0)
		var cyl := int(fire) % 4
		var pulse: float = exp(-ph * 6.0) * float([1.0, 0.82, 0.93, 0.76][cyl])
		var harm := sin(TAU * 120.0 * t) * 0.45 + sin(TAU * 240.0 * t) * 0.32 + sin(TAU * 360.0 * t + 0.6) * 0.22 + sin(TAU * 480.0 * t) * 0.14 + sin(TAU * 600.0 * t + 1.1) * 0.08
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.3
		var rasp: float = (lp - hp_prev) * pulse
		hp_prev = lp
		s[i] = clampf(harm * (0.45 + pulse * 0.7) * 0.55 + rasp * 0.5 + lp * 0.05, -1.0, 1.0) * 0.85
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

func _ambience(night := false) -> AudioStreamWAV:
	## city bed: cars swishing past, distant horns, a dog, birds by day / crickets at night. 12 s loop.
	var n := RATE * 12
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var bp := 0.0
	var bp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 if not night else 5
	var passes := []
	for k in (4 if night else 7):
		passes.append([rng.randf_range(0.0, 12.0), rng.randf_range(2.5, 4.5), rng.randf_range(0.5, 1.0)])
	var horns := [[2.3, 0.35, 380.0], [7.6, 0.22, 450.0], [9.1, 0.5, 410.0]]
	for i in n:
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.06
		bp += (noise - bp) * 0.35
		bp2 += (bp - bp2) * 0.08
		var band := bp - bp2          # 300 Hz – 3 kHz hiss: what tyres on asphalt sound like
		var v := lp * 0.5
		for ps in passes:
			var dt: float = fposmod(t - ps[0], 12.0)
			if dt < ps[1]:
				var e: float = sin(PI * dt / ps[1])
				v += band * e * e * 0.9 * ps[2]
		for h in (horns if not night else [horns[1]]):
			var dh: float = t - h[0]
			if dh > 0.0 and dh < h[1]:
				v += (signf(sin(TAU * h[2] * t)) * 0.5 + signf(sin(TAU * h[2] * 1.25 * t)) * 0.5) * 0.05
		if not night:
			for b in [1.2, 1.45, 5.3, 5.5, 5.7, 10.4]:
				var db: float = t - b
				if db > 0.0 and db < 0.12:
					v += sin(TAU * (3400.0 + 1600.0 * sin(TAU * 18.0 * db)) * db) * 0.05 * sin(PI * db / 0.12)
		else:
			var cr := fmod(t * 3.1, 1.0)
			if cr < 0.35:
				v += sin(TAU * 4300.0 * t) * 0.025 * (0.5 + 0.5 * sin(TAU * 32.0 * t))
		for d in [3.9, 4.25]:
			var dd: float = t - d
			if dd > 0.0 and dd < 0.18:
				v += sin(TAU * (520.0 - dd * 900.0) * dd) * 0.07 * exp(-dd * 14.0) + band * 0.05 * exp(-dd * 20.0)
		s[i] = clampf(v * 1.6, -1.0, 1.0)
	return _wav(s, true)

func _ring() -> AudioStreamWAV:
	## desk phone: two bursts of a warbling bell
	var n := int(1.6 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var on := (t < 0.5) or (t > 0.8 and t < 1.3)
		if on:
			var f := 950.0 if fmod(t * 22.0, 1.0) < 0.5 else 1250.0
			s[i] = sin(TAU * f * t) * 0.35
	return _wav(s)

func _radio() -> AudioStreamWAV:
	## push-to-talk: click + short band-limited static
	var n := int(0.22 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		a += (noise - a) * 0.5
		b += (a - b) * 0.1
		var v := (a - b) * 0.5 * (1.0 if t < 0.18 else (0.22 - t) / 0.04)
		if t < 0.012:
			v += sin(TAU * 1700.0 * t) * 0.6
		s[i] = v
	return _wav(s)

func _bolt() -> AudioStreamWAV:
	var n := int(0.7 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for c in [0.0, 0.18, 0.42, 0.55]:
		var st := int(c * RATE)
		for i in int(0.06 * RATE):
			if st + i < n:
				var t := float(i) / RATE
				s[st + i] += (sin(TAU * 1700.0 * t) * 0.4 + (randf() - 0.5) * 0.9) * exp(-t * 70.0) * 0.7
	return _wav(s)

func _sputter() -> AudioStreamWAV:
	## dying engine: irregular backfire pops
	var n := int(1.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for c in [0.0, 0.21, 0.29, 0.55, 0.9, 0.97]:
		var st := int(c * RATE)
		for i in int(0.1 * RATE):
			if st + i < n:
				var t := float(i) / RATE
				s[st + i] += ((randf() * 2.0 - 1.0) * 0.8 + sin(TAU * 140.0 * t) * 0.8) * exp(-t * 35.0)
	return _wav(s)

func _glass() -> AudioStreamWAV:
	var n := int(0.8 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in 26:
		var st := int(randf_range(0.0, 0.5) * RATE)
		var f := randf_range(2500.0, 6500.0)
		for i in int(0.08 * RATE):
			if st + i < n:
				var t := float(i) / RATE
				s[st + i] += sin(TAU * f * t) * exp(-t * 60.0) * 0.18
	return _wav(s)
