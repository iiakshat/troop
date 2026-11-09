extends Node
## Sound effects and music.
##
## Sounds: Sfx.play("id"). Files live in res://assets/audio/<id>.ogg; extra takes are
## <id>2.ogg, <id>3.ogg... A numbered file only counts as a take when <id>.ogg exists, so
## star1/star2/star3 stay separate ids. Takes play in a shuffled round robin (never the same
## take twice in a row) with a small, even pitch spread, so repeats sound alive but
## consistent. Each id is rate-limited so 60 guns don't turn into noise. Ids without a file
## fall back to a sound synthesised on first use; unknown ids are silent.
##
## Safe to call at any time: before _ready (players are made on first use), outside the
## scene tree (headless test scripts) or with no audio files at all. It never errors.
##
## Music: Sfx.play_music("menu" | "level" | "boss") crossfades between looping tracks
## (music_<mode>.ogg). The old bool form still works: true = level, false = menu.

const DIR := "res://assets/audio/"
const RATE := 22050
const VOICES := 18
const SILENT_DB := -60.0
const MUSIC_FADE := 1.2  # seconds for a crossfade between tracks
const DUCK_DB := -18.0   # music drop while something (an ad popup) asks for quiet
const MUSIC_DB := {"menu": -8.0, "level": -10.0, "boss": -9.0}

## Old ids that callers still use -> the current id.
const ALIASES := {"strike": "boom", "crash": "boom"}
## One call that plays several sounds: [id, delay s, extra dB]. "glass" is the old finale
## call; it now gets the shatter plus falling shards.
const COMBOS := {"glass": [["glass_break", 0.0, 0.0], ["glass_tinkle", 0.16, -3.0]]}

## Most copies of one id sounding at once. A new play over the cap is dropped, so a full
## squad firing reads as a steady volley, not a wall of noise. Default 3.
const MAX_SAME := {
	"knife": 3, "shot": 4, "shot_big": 3, "shot_rifle": 3, "hit": 3, "punch": 3, "die": 3,
	"coin": 4, "spin_tick": 2, "tick": 2, "glass_break": 3, "glass_tinkle": 2, "boom": 2,
	"tap": 2, "hurt": 2, "boss_roar": 1, "fire": 2,
}
## Minimum seconds between two plays of the same id.
const MIN_GAP := {
	"knife": 0.06, "shot": 0.05, "shot_big": 0.08, "shot_rifle": 0.06, "shot_sniper": 0.25,
	"shot_shotgun": 0.12, "launcher": 0.2, "blast": 0.3, "boom": 0.12, "hit": 0.06,
	"punch": 0.07, "die": 0.09, "hurt": 0.12, "tick": 0.05, "spin_tick": 0.03, "clink": 0.12,
	"coin": 0.05, "glass_break": 0.05, "glass_tinkle": 0.1, "thunk": 0.08, "pothole": 0.25,
	"fire": 0.2, "snipe": 0.2, "boss_roar": 1.5, "build": 0.15, "recruit": 0.08,
	"gate_good": 0.08, "gate_bad": 0.08, "blocked": 0.08, "collect": 0.08,
}
## Pitch spread per id (+/- fraction). Default 0.03. Musical sounds get none, so they stay
## in tune with each other (star1-3 are a chord).
const PITCH_SPREAD := {
	"knife": 0.0, "shot": 0.04, "shot_big": 0.03, "shot_rifle": 0.03, "hit": 0.05,
	"punch": 0.05, "die": 0.04, "hurt": 0.03, "glass_break": 0.04, "glass_tinkle": 0.05,
	"coin": 0.0, "coin_bag": 0.0, "win": 0.0, "lose": 0.0, "upgrade": 0.0, "banner": 0.0,
	"rank_up": 0.0, "gate_good": 0.0, "gate_bad": 0.0, "star1": 0.0, "star2": 0.0,
	"star3": 0.0, "spin_win": 0.0, "daily_claim": 0.0, "mission_done": 0.0, "unlock": 0.0,
	"build_done": 0.0, "chest_open": 0.0, "collect": 0.0, "recruit": 0.0, "tap": 0.0,
	"error": 0.0, "flip": 0.0, "tick": 0.0, "spin_tick": 0.02, "boss_roar": 0.0,
}
## Mix trim per id in dB, added to the caller's volume. tools/make_sfx.py levels every file
## it builds (loudest 50 ms: big hits -11..-13, weapons and bodies -12..-16, rewards -13..-16,
## ticks -20). The older Kenney / rubberduck files below were louder than that, so they are
## trimmed onto the same plan here: UI and rewards never sit above the gameplay hits.
const TRIM_DB := {
	"upgrade": -6.5, "win": -3.5, "lose": -6.0, "banner": -4.5, "error": -3.5,
	"recruit": -3.0, "gate_good": -4.0, "flip": -4.5, "tick": -4.0, "clink": -3.5,
	"blast": -1.5, "tap": -8.0, "swoosh": -3.0,
}
const _PITCH_STEPS := [0.0, 0.6, -0.6, 1.0, -1.0, 0.3, -0.3]

var _players: Array[AudioStreamPlayer] = []
var _player_id: PackedStringArray = []  # id each voice played last
var _next := 0
var _variants: Dictionary = {}  # id -> Array[AudioStream] (from files)
var _synth: Dictionary = {}     # id -> AudioStream synthesised on first use
var _order: Dictionary = {}     # id -> Array[int] shuffled take order still to play
var _last_take: Dictionary = {} # id -> index of the take played last
var _step: Dictionary = {}      # id -> pitch step counter
var _last_play: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_cur := 0
var _music_mode := ""
var _music_tween: Tween
var _ducked := false
var _setup_done := false


func _ready() -> void:
	# Keep sounding while the tree is paused (ad popup, pause menu): its taps need sound.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup()
	if _music_mode != "":  # play_music() was asked for before the tree was ready
		play_music(_music_mode)


## Makes the voices and loads the files once. Called lazily, so Sfx works before _ready.
func _setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
		_player_id.append("")
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Master"
		m.volume_db = SILENT_DB
		add_child(m)
		_music.append(m)
	_load_files()


# ---------------------------------------------------------------- sounds

func play(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	_setup()
	# Outside the scene tree (test scripts, before boot) nothing can sound: stay silent.
	if not is_inside_tree() or not _sound_on():
		return
	if COMBOS.has(id):
		for part in COMBOS[id]:
			_play_later(str(part[0]), float(part[1]), volume_db + float(part[2]), pitch)
		return
	id = ALIASES.get(id, id)
	var stream := _stream_for(id)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(id, -1.0)) < float(MIN_GAP.get(id, 0.0)):
		return
	if _playing_count(id) >= int(MAX_SAME.get(id, 3)):
		return
	_last_play[id] = now
	var p := _free_player()
	_player_id[_players.find(p)] = id
	p.stream = stream
	p.volume_db = volume_db + float(TRIM_DB.get(id, 0.0))
	var spread := float(PITCH_SPREAD.get(id, 0.03))
	var k := int(_step.get(id, 0))
	_step[id] = k + 1
	p.pitch_scale = maxf(0.05, pitch * (1.0 + spread * float(_PITCH_STEPS[k % _PITCH_STEPS.size()])))
	p.play()


## True if the id makes a sound (a file, a synth fallback, an alias or a combo).
func has_sound(id: String) -> bool:
	if COMBOS.has(id):
		return true
	id = ALIASES.get(id, id)
	_setup()
	return _variants.has(id) or _synth.has(id) or _SYNTH.has(id)


func _sound_on() -> bool:
	var g: Node = get_node_or_null("/root/Game")
	if g == null or not (g.get("save") is Dictionary):
		return true
	return bool((g.get("save") as Dictionary).get("sound", true))


func _music_on() -> bool:
	var g: Node = get_node_or_null("/root/Game")
	if g == null or not (g.get("save") is Dictionary):
		return true
	return bool((g.get("save") as Dictionary).get("music", true))


func _playing_count(id: String) -> int:
	var n := 0
	for i in _players.size():
		if _player_id[i] == id and _players[i].playing:
			n += 1
	return n


func _play_later(id: String, delay: float, volume_db: float, pitch: float) -> void:
	if delay <= 0.0:
		play(id, volume_db, pitch)
		return
	get_tree().create_timer(delay, true, false, true).timeout.connect(play.bind(id, volume_db, pitch))


func _stream_for(id: String) -> AudioStream:
	if _variants.has(id):
		var takes: Array = _variants[id]
		if takes.size() == 1:
			return takes[0]
		var order: Array = _order.get(id, [])
		if order.is_empty():
			order = range(takes.size())
			order.shuffle()
			if int(order[0]) == int(_last_take.get(id, -1)):
				order.push_back(order.pop_front())
			_order[id] = order
		var i := int(order.pop_front())
		_last_take[id] = i
		return takes[i]
	if not _synth.has(id) and _SYNTH.has(id):
		_synth[id] = _build_synth(id)
	return _synth.get(id)


func _free_player() -> AudioStreamPlayer:
	for i in VOICES:
		var p := _players[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	var oldest := _players[_next]  # all busy: steal the one started longest ago
	_next = (_next + 1) % VOICES
	return oldest


func _load_files() -> void:
	var names := PackedStringArray()
	for f in _list_dir(DIR):
		if f.ends_with(".ogg") and not f.begins_with("music_"):
			names.append(f.get_basename())
	var groups := group_files(names)
	for id in groups:
		var takes: Array = []
		for file_id in groups[id]:
			var s: AudioStream = load(DIR + file_id + ".ogg")
			if s != null:
				takes.append(s)
		if not takes.is_empty():
			_variants[id] = takes


## Sound file names (no extension) -> {id: [file names in take order]}. "glass_break2" is a
## take of "glass_break" only if "glass_break" exists; otherwise it is its own id.
static func group_files(names: PackedStringArray) -> Dictionary:
	var have := {}
	for n in names:
		have[n] = true
	var keyed := {}  # id -> [[take number, file name]]
	for n in names:
		var base := n.rstrip("0123456789")
		var id := base if (base != n and base != "" and have.has(base)) else n
		if not keyed.has(id):
			keyed[id] = []
		(keyed[id] as Array).append([1 if n == id else int(n.substr(id.length())), n])
	var out := {}
	for id in keyed:
		var pairs: Array = keyed[id]
		pairs.sort()
		out[id] = pairs.map(func(p): return p[1])
	return out


## Files in a res:// folder, also in exported builds (where only .import/.remap files list).
static func _list_dir(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not out.has(file):
			out.append(file)
	return out


# ---------------------------------------------------------------- music

## mode: "menu" | "level" | "boss" (a bool also works: true = level, false = menu).
func play_music(mode: Variant = "menu") -> void:
	_setup()
	var m := _music_mode_of(mode)
	_music_mode = m
	if not is_inside_tree():  # _ready starts it
		return
	var cur := _music[_music_cur]
	if not _music_on():
		_fade_music(cur, SILENT_DB, 0.3, true)
		_fade_music(_music[1 - _music_cur], SILENT_DB, 0.3, true)
		return
	var stream := _music_stream(m)
	if stream == null:
		return
	var target := _music_target(m)
	if cur.playing and cur.stream == stream:
		_fade_music(cur, target, 0.5, false)
		return
	var nxt := _music[1 - _music_cur]
	if _music_tween:
		_music_tween.kill()
	nxt.stream = stream
	nxt.volume_db = SILENT_DB
	nxt.play()
	_music_tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
	_music_tween.tween_property(nxt, "volume_db", target, MUSIC_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if cur.playing:
		_music_tween.tween_property(cur, "volume_db", SILENT_DB, MUSIC_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.chain().tween_callback(cur.stop)
	_music_cur = 1 - _music_cur


## The settings toggle changed: start or stop the current track.
func music_changed() -> void:
	play_music(_music_mode if _music_mode != "" else "menu")


## Lower the music (e.g. while an ad popup is up) or bring it back.
func duck_music(on: bool) -> void:
	if _ducked == on:
		return
	_ducked = on
	if not is_inside_tree() or _music.is_empty():
		return
	var cur := _music[_music_cur]
	if cur.playing:
		_fade_music(cur, _music_target(_music_mode), 0.25, false)


func music_mode() -> String:
	return _music_mode


func _music_mode_of(mode: Variant) -> String:
	if typeof(mode) == TYPE_BOOL:
		return "level" if mode else "menu"
	var m := str(mode)
	return m if MUSIC_DB.has(m) else "menu"


func _music_target(mode: String) -> float:
	return float(MUSIC_DB.get(mode, -10.0)) + (DUCK_DB if _ducked else 0.0)


func _music_stream(mode: String) -> AudioStream:
	# A missing track borrows a neighbour so music never just stops.
	for m in [mode, "level", "menu", "boss"]:
		var path: String = DIR + "music_" + m + ".ogg"
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			if s != null:
				return s
	return null


func _fade_music(p: AudioStreamPlayer, db: float, time: float, stop_after: bool) -> void:
	if _music_tween:
		_music_tween.kill()
	if not p.playing:
		return
	_music_tween = create_tween().set_ignore_time_scale(true)
	_music_tween.tween_property(p, "volume_db", db, time)
	if stop_after:
		_music_tween.tween_callback(p.stop)


# ---------------------------------------------------------------- synth fallbacks
# Only used for ids that have no file (and for old ids nobody recorded yet).

const _SYNTH := {
	"knife": true, "shot": true, "hit": true, "die": true, "clink": true, "tick": true,
	"gate_good": true, "gate_bad": true, "flip": true, "recruit": true, "boom": true,
	"shield": true, "blocked": true, "hurt": true, "coin": true, "win": true, "lose": true,
	"tap": true, "swoosh": true,
}


func _build_synth(id: String) -> AudioStream:
	match id:
		"knife":
			var lp := [0.0, 0.0]
			return _make(0.15, func(t, d):
				var x: float = t / d
				var k: float = 0.04 + 0.42 * sin(PI * x)
				lp[0] += (_noise() - lp[0]) * k
				lp[1] += (lp[0] - lp[1]) * k
				return (lp[0] - lp[1]) * sin(PI * pow(x, 0.7)) * 1.6)
		"shot":
			return _make(0.12, func(t, d): return (_noise() * 0.6 + sin(TAU * 110.0 * t) * 0.6) * exp(-t * 38.0) * 0.55)
		"hit":
			return _make(0.05, func(t, d): return _noise() * exp(-t * 90.0) * 0.3)
		"die":
			return _make(0.09, func(t, d): return sin(TAU * (520.0 - 3000.0 * t) * t) * exp(-t * 30.0) * 0.32)
		"clink":
			return _make(0.18, func(t, d): return (sin(TAU * 2400.0 * t) + sin(TAU * 3700.0 * t) * 0.5) * exp(-t * 26.0) * 0.22)
		"tick":
			return _make(0.07, func(t, d): return sin(TAU * 1300.0 * t) * exp(-t * 50.0) * 0.3)
		"gate_good":
			return _make(0.42, func(t, d): return _arp(t, [523.25, 659.25, 783.99, 1046.5], 0.09) * 0.38)
		"gate_bad":
			return _make(0.36, func(t, d): return _square(TAU * (300.0 - 250.0 * t) * t) * _env(t, d, 0.01) * 0.18)
		"flip":
			return _make(0.5, func(t, d): return sin(TAU * (600.0 + 1400.0 * t) * t) * _env(t, d, 0.01) * 0.3 + _arp(t, [783.99, 1046.5, 1318.5], 0.1) * 0.2)
		"recruit":
			return _make(0.3, func(t, d): return _arp(t, [392.0, 587.33, 783.99], 0.07) * 0.34)
		"boom":
			return _make(0.8, func(t, d): return (_noise() * 0.8 + sin(TAU * 55.0 * t) * 0.8) * exp(-t * 5.0) * 0.6)
		"shield":
			return _make(0.6, func(t, d): return (sin(TAU * 440.0 * t) + sin(TAU * 660.0 * t + sin(TAU * 6.0 * t))) * _env(t, d, 0.05) * 0.2)
		"blocked":
			return _make(0.12, func(t, d): return sin(TAU * 900.0 * t) * exp(-t * 30.0) * 0.25)
		"hurt":
			return _make(0.2, func(t, d): return sin(TAU * (220.0 - 300.0 * t) * t) * exp(-t * 12.0) * 0.4)
		"coin":
			return _make(0.16, func(t, d): return (sin(TAU * 1567.98 * t) + sin(TAU * 2093.0 * t) * (1.0 if t > 0.05 else 0.0)) * exp(-t * 14.0) * 0.25)
		"win":
			return _make(1.1, func(t, d): return _arp(t, [523.25, 659.25, 783.99, 1046.5, 1318.5], 0.13) * 0.4)
		"lose":
			return _make(1.0, func(t, d): return _square(TAU * (330.0 - 120.0 * t) * t) * _env(t, d, 0.02) * 0.16)
		"tap":
			return _make(0.06, func(t, d): return sin(TAU * 880.0 * t) * exp(-t * 60.0) * 0.3)
		"swoosh":
			return _make(0.18, func(t, d): return _noise() * sin(PI * t / d) * 0.25)
	return null


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
