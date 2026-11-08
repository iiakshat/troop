extends Node
## Sound effects and music. Recorded CC0 files in assets/audio win (variants like
## glass2/glass3 are picked at random); anything without a file falls back to a sound
## synthesised at startup. Call Sfx.play("id"). Each id is rate-limited so 60 guns
## don't turn into noise.

const RATE := 22050
const VOICES := 14

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_play: Dictionary = {}
var _min_gap := {"knife": 0.06, "shot": 0.045, "hit": 0.05, "die": 0.035, "tick": 0.05, "clink": 0.12, "coin": 0.05, "punch": 0.07}
var _variants: Dictionary = {}   # id -> Array of streams
var _jitter := {"knife": 0.015, "glass": 0.03}  # random pitch range per id (default 0.06)
var _music: AudioStreamPlayer


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build()
	_load_files()
	_music = AudioStreamPlayer.new()
	add_child(_music)
	var m: AudioStream = load("res://assets/audio/music_fight.ogg")
	if m is AudioStreamOggVorbis:
		(m as AudioStreamOggVorbis).loop = true
	_music.stream = m


func play_music(in_level: bool) -> void:
	_music.volume_db = -9.0 if in_level else -15.0
	if bool(Game.save.get("music", true)):
		if not _music.playing:
			_music.play()
	else:
		_music.stop()


func music_changed() -> void:
	play_music(_music.volume_db > -12.0)


func _load_files() -> void:
	var dir := "res://assets/audio/"
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".import")
		if not file.ends_with(".ogg") or file.begins_with("music_"):
			continue
		var stream: AudioStream = load(dir + file)
		if stream == null:
			continue
		var id := file.get_basename()
		var base := id.rstrip("0123456789")
		if not _variants.has(base):
			_variants[base] = []
		if not (_variants[base] as Array).has(stream):
			(_variants[base] as Array).append(stream)


func play(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not bool(Game.save.get("sound", true)) or not (_streams.has(id) or _variants.has(id)):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(id, -1.0)) < float(_min_gap.get(id, 0.0)):
		return
	_last_play[id] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = (_variants[id] as Array).pick_random() if _variants.has(id) else _streams[id]
	p.volume_db = volume_db
	var j := float(_jitter.get(id, 0.06))
	p.pitch_scale = pitch * randf_range(1.0 - j, 1.0 + j)
	p.play()


# ---------------------------------------------------------------- synthesis

func _build() -> void:
	# Knife throw: a short "fwip" (noise through a filter that opens and closes).
	var lp := [0.0, 0.0]
	_streams["knife"] = _make(0.15, func(t, d):
		var x: float = t / d
		var k: float = 0.04 + 0.42 * sin(PI * x)
		lp[0] += (_noise() - lp[0]) * k
		lp[1] += (lp[0] - lp[1]) * k
		return (lp[0] - lp[1]) * sin(PI * pow(x, 0.7)) * 1.6)
	_streams["shot"] = _make(0.12, func(t, d): return (_noise() * 0.6 + sin(TAU * 110.0 * t) * 0.6) * exp(-t * 38.0) * 0.55)
	_streams["hit"] = _make(0.05, func(t, d): return _noise() * exp(-t * 90.0) * 0.3)
	_streams["die"] = _make(0.09, func(t, d): return sin(TAU * (520.0 - 3000.0 * t) * t) * exp(-t * 30.0) * 0.32)
	_streams["clink"] = _make(0.18, func(t, d): return (sin(TAU * 2400.0 * t) + sin(TAU * 3700.0 * t) * 0.5) * exp(-t * 26.0) * 0.22)
	_streams["tick"] = _make(0.07, func(t, d): return sin(TAU * 1300.0 * t) * exp(-t * 50.0) * 0.3)
	_streams["gate_good"] = _make(0.42, func(t, d): return _arp(t, [523.25, 659.25, 783.99, 1046.5], 0.09) * 0.38)
	_streams["gate_bad"] = _make(0.36, func(t, d): return _square(TAU * (300.0 - 250.0 * t) * t) * _env(t, d, 0.01) * 0.18)
	_streams["flip"] = _make(0.5, func(t, d): return sin(TAU * (600.0 + 1400.0 * t) * t) * _env(t, d, 0.01) * 0.3 + _arp(t, [783.99, 1046.5, 1318.5], 0.1) * 0.2)
	_streams["recruit"] = _make(0.3, func(t, d): return _arp(t, [392.0, 587.33, 783.99], 0.07) * 0.34)
	_streams["boom"] = _make(0.8, func(t, d): return (_noise() * 0.8 + sin(TAU * 55.0 * t) * 0.8) * exp(-t * 5.0) * 0.6)
	_streams["shield"] = _make(0.6, func(t, d): return (sin(TAU * 440.0 * t) + sin(TAU * 660.0 * t + sin(TAU * 6.0 * t))) * _env(t, d, 0.05) * 0.2)
	_streams["blocked"] = _make(0.12, func(t, d): return sin(TAU * 900.0 * t) * exp(-t * 30.0) * 0.25)
	_streams["hurt"] = _make(0.2, func(t, d): return sin(TAU * (220.0 - 300.0 * t) * t) * exp(-t * 12.0) * 0.4)
	_streams["coin"] = _make(0.16, func(t, d): return (sin(TAU * 1567.98 * t) + sin(TAU * 2093.0 * t) * (1.0 if t > 0.05 else 0.0)) * exp(-t * 14.0) * 0.25)
	_streams["win"] = _make(1.1, func(t, d): return _arp(t, [523.25, 659.25, 783.99, 1046.5, 1318.5], 0.13) * 0.4)
	_streams["lose"] = _make(1.0, func(t, d): return _square(TAU * (330.0 - 120.0 * t) * t) * _env(t, d, 0.02) * 0.16)
	_streams["tap"] = _make(0.06, func(t, d): return sin(TAU * 880.0 * t) * exp(-t * 60.0) * 0.3)
	_streams["swoosh"] = _make(0.18, func(t, d): return _noise() * sin(PI * t / d) * 0.25)
	_streams["strike"] = _make(0.5, func(t, d): return (_noise() * exp(-t * 9.0) + sin(TAU * 80.0 * t) * exp(-t * 6.0)) * 0.55)


func _make(dur: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := clampf(float(f.call(t, dur)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _env(t: float, d: float, attack: float) -> float:
	return minf(t / attack, 1.0) * clampf(1.0 - t / d, 0.0, 1.0)


func _square(phase: float) -> float:
	return 1.0 if sin(phase) >= 0.0 else -1.0


func _arp(t: float, notes: Array, step: float) -> float:
	var i := mini(int(t / step), notes.size() - 1)
	var lt := t - i * step
	return sin(TAU * float(notes[i]) * t) * exp(-lt * 9.0)
