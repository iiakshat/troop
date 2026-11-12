class_name LevelView
extends Node3D
## Plays one level: steps LevelSim at a fixed rate and turns its state and events into
## people, gates, bullets, numbers and sound. Also handles lane input.
## `demo` mode (lobby backdrop): the squad just jogs down an empty street.

signal hint(ev: Dictionary)
signal banner(text: String, color: Color)
signal squad_changed(total: int)
signal charges_changed(charges: Dictionary)
signal strike_ready
signal tutorial(active: bool)
signal finished(result: Dictionary)
signal rank_joined(unit: String, first_time: bool)

const LANE_X := [-2.8, 0.0, 2.8]
const ALLY_CAP := 72
const HORDE_CAP := 180
const DT := 1.0 / 60.0
const ENEMY_KINDS := ["thug", "knifer", "gunman", "brute", "riot", "biker", "boss",
	"molotov", "sniper_foe", "grenadier"]
const ALLY_KINDS := ["hero", "constable", "sergeant", "inspector", "swat", "sniper", "commando"]
## Blob order, front to back: the hero leads, the heavy hitters next, constables behind.
const ALLY_ORDER := {"hero": 0, "sniper": 1, "commando": 2, "swat": 3, "inspector": 4, "sergeant": 5, "constable": 6}
## Figures each enemy crowd can draw at once (all gangs of that kind together, plus bodies).
## Small specialist gangs need far fewer than the mobs.
const ENEMY_CAP := {"boss": 4, "sniper_foe": 120, "molotov": 240, "grenadier": 240}
## Gun sound per rank (spec ids first; the second one plays until AUDIO ships the first).
const ALLY_SFX := {
	"constable": ["shot", "shot", -11.0], "sergeant": ["shot_shotgun", "shot_big", -9.0],
	"inspector": ["shot_big", "shot_big", -9.0], "swat": ["shot_rifle", "shot_rifle", -10.0],
	"sniper": ["shot_sniper", "shot_rifle", -6.0], "commando": ["launcher", "boom", -12.0],
}
const CHAR_H := 1.85            # baked character height (config/characters.json)
const BOSS_SCALE := 3.2         # bosses are drawn this much bigger than a thug (imposing at the 40 m halt)
const BOSS_FAR_SCALE := 1.6     # a far boss is drawn up to this much bigger again (boss_grow)
const BOSS_RIM := 0.3           # extra rim light on the boss: his dark suit never melts into the stash
## Spec v2.1 §1.3: the lieutenant is the boss's rig, smaller (BOSS_SCALE's convention), in a cream
## suit and black shirt (the Kingpin wears black and red), under a smaller bar with a silver crown.
const LT_SCALE := 2.4
const LT_BAR := 0.72
const LT_COLORS := {Color("151515"): Color("e9e1cd"), Color("b3282d"): Color("1c1c22")}
const LT_CROWN := Color(0.78, 0.84, 0.95)
## Spec v2.1 §1.1: incoming fire reads at a glance: at most this many tracers per event, and the
## red -N over the squad sums what is lost within MINUS_WINDOW s (shown MINUS_HOLD s).
const TRACERS_PER_EVENT := 8
const MINUS_WINDOW := 0.3
const MINUS_HOLD := 0.9
const MINUS_RED := Color("ff3b3b")
## Spec v2.1 §1.2-1.3: a telegraph marks its lane where the squad stands, in its kind's colour,
## while its countdown sweeps towards the squad (on the street's clock, so it is honest).
const ZONE_SIZE := Vector2(2.4, 7.0)
const ZONE_Z := -0.4             # from 3.9 m ahead of the hero back under the squad
const SPOT_Z := -2.0             # where a grenade, bottle or sniper round lands: just ahead of the hero
const THREAT_TINT := {"snipe": Color(1.0, 0.1, 0.1), "grenade": Color(1.0, 0.4, 0.06),
	"firebomb": Color(1.0, 0.58, 0.05), "barrage": Color(1.0, 0.06, 0.18), "lt_barrage": Color(1.0, 0.16, 0.5)}
const SHELLS := {"barrage": 5, "lt_barrage": 3}
const ZONE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float fill = 0.0;    // share of the warning gone: the honest countdown
uniform float pulse = 0.0;
uniform float flash = 0.0;   // the landing
uniform vec2 size = vec2(2.4, 7.0);
void fragment() {
	vec2 m = UV * size;
	float e = min(min(m.x, size.x - m.x), min(m.y, size.y - m.y));
	float border = 1.0 - smoothstep(0.12, 0.2, e);
	float stripe = step(0.5, fract((m.x + m.y) * 1.1));
	float swept = step(UV.y, fill);   // from the far end towards the squad
	float inner = (0.1 + 0.22 * stripe) * (0.35 + 0.65 * swept);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.92, 0.75), flash * 0.7);
	ALPHA = clamp(max(border * (0.65 + 0.35 * pulse), inner) + flash * 0.3, 0.0, 1.0) * tint.a;
}
"""
const INK_W := 0.028            # crowd ink outline width (crowd_outline.gdshader default)
const INK_W_PACKED := 0.012     # a full squad's followers: thinner ink, no grey-purple smudge
const DEPTH_SPREAD := 1.3       # a full squad's rows open up this much in depth (view only; smudge fix)
const ENEMY_SCALE := 1.3        # gang members are drawn bigger than troops so far fights read
const BOSS_BEAT_Z := -35.0      # a boss closer than this pulls the camera in (World.beat)
const CAM_FOLLOW := 0.5         # the camera follows the squad sideways by this share
const LASER_POOL := 6           # sniper telegraph beams on screen at once
const STEER_PER_SCREEN := 14.0   # metres of squad travel for a full-width finger drag
const LANE_SLACK := 0.35         # metres past the midpoint before the lane flips (no flicker)
const STEER_EASE := 16.0         # how quickly the squad catches the finger

var sim: LevelSim
var world: World
var fx: Fx
var font: Font
var level_id := 1
var _level: Dictionary = {}    # the level config (pre-warm reads its gates and icons)
var _places: Dictionary = {}   # squad size -> formation place per slot (see _place_of)
var district := 1
var demo := false
var paused := false
var input_enabled := true      # false under --autoplay so stray clicks can't interfere
var hold := false              # a first-run tutorial (Tutorial) freezes the street until the player acts
var perf_on := false           # perf=1: main.gd logs these markers next to each frame time
var perf_marks: Array[String] = []
const PERF_EVENTS := ["rank_join", "row_pass", "horde_spawn", "bomb", "barrel_boom", "obstacle_hit",
	"obstacle_broken", "finish", "revive", "lost", "melee_start", "telegraph", "attack_land", "boss_shot"]
var slow := false              # unused since spec v2 §3 (time never slows); kept for Tutorial

var _crowds: Dictionary = {}
var _allies: Array = []        # {kind, pos, slot, phase, flash, fire_t}
var _dying: Array = []         # {kind, pos, t, basis}
var _charging: Array = []      # {kind, pos, target, flip}
var _hordes: Dictionary = {}   # id -> {h, kind, offs, per, label, sub, flash}
var _rows: Dictionary = {}     # id -> GateRowView
var _squad_x := 0.0
var _acc := 0.0
var _last_traveled := 0.0
var _time_scale := 1.0
var _tut_row := -1
var _tut_done: Dictionary = {}
var _state := "play"           # play | strike | striking | done
var _end_t := 0.0
var _squad_label: Label3D
var _label_pop := 0.0
var _shield_fx: ShieldBubble   # the squad's shield bubble (src/game/shield_bubble.gd)
var _finish: Node3D
var _finish_live := false      # the finish was spawned (it is built hidden at load to pre-warm)
const WARM_FRAMES := 3         # spec v2 §3: every crowd, effect, obstacle, gate and the stash
var _warm: Array[Node3D] = []  # draws out of sight for the first frames, so their shaders
var _warm_stash_at := Vector3.ZERO   # where the warm Bottle Shot stash stands (prewarm)
var _warm_left := 0            # compile during loading and not when a rank joins
var _warm_at := Vector3(0, -8, -16)
var _hq: Node3D
var _hq_fill: MeshInstance3D
var finale: BottleShot = null
var _finale_warm: BottleShot = null   # this level's finale, built at load and resting (prewarm)
var item_card: NewItemCard = null   # v2 §11: the "this is new" card + gold outline (new_item_card())
var _hero_throw_t := -1.0
var _bomb_throw_t := -1.0          # seconds into the hero's bomb throw (-1: none; spec v2 §12.5)
var _bomb_launch: Dictionary = {}  # the bomb in his hand until the release: {id, to, t, windup, arc}
var _bomb_speed := 1.0             # the throw clip's speed for the bomb (bomb_clip_speed)
var _bomb_mark: MeshInstance3D     # the ring on the road where the bomb will land (blast radius)
var _bomb_mark_mat: StandardMaterial3D
var _last_tap_s := -100.0          # when the last fire tap landed (the power buttons' guard)
var _last_tap_pos := Vector2(-1e9, -1e9)   # and where (screen px; touch taps only)
var _rf_sfx_t := 0.0               # return fire plays its shot sound at most this often
var _hero_knife_t := 9.0         # seconds since the hero's last in-level knife throw
var _spotlight := 0.0            # seconds of new-rank spotlight left (real time)
var _spot_kind := ""             # the rank in the spotlight
var _spot_ring: MeshInstance3D = null
var _danger_ring: MeshInstance3D = null
var _danger_t := 0.0             # seconds the death-cause marker stays up
var _danger_at := Vector3.ZERO
var _was_standoff := false
var _boss_step := 0.0            # boss footfall clock (camera thump, dust)
var _touching := false
var _touch: TouchClassifier = null   # tap vs swipe per finger (spec v2 §2)
var _steer_id := -1              # the finger that steers (-1: none)
var _flick_t := 9.0              # seconds since the last tap (the hero's hand flick)
var taps := 0                    # hero taps this level (analytics: taps per minute)
const FLICK_S := 0.14            # the flick's length (s)
var _heat_ring: MeshInstance3D   # spec v2 §2: the tap-heat arc at the hero's feet
var _heat_mat: ShaderMaterial
var _heat_local := 0.0           # visual heat while the sim has no tap_heat (before CORE's merge)
const HEAT_COLD := Color("5ab4ff")
const HEAT_WARM := Color("ffd23f")
const HEAT_HOT := Color("ff4a24")
var _drag_from_x := 0.0          # finger x when the drag (re)started
var _steer_from := 0.0           # squad target x at that moment
var _steer_x := 0.0              # where the finger wants the squad
var _last_total := 1
var _shown_banner: Dictionary = {}
var _obstacles: Dictionary = {}  # id -> {ob, node, label, cracks, hp_shown, chip_t}
var _cages: Dictionary = {}      # v2.1 Rescue: cage id -> {cage, view: CageView}
var _riding: Array = []        # passed obstacle nodes riding the road off screen
var _falling: Array = []       # {kind, pos, t, spin}: troops dropping into a pothole
var _death_style := ""         # "fall" while a pothole takes troops
var _death_at := Vector3.ZERO
var _lasers: Array[MeshInstance3D] = []
var _laser_mat: StandardMaterial3D
var _threats: Array = []       # pending telegraphs: {kind, lane, src, from, start, land, points}
var _zones: Array = []         # per lane {node, mat, fill, flash}: the telegraph's lane mark
var _impacts: Array = []       # incoming shots in the air: {at, lost, blocked, points (x by the squad)}
var _pending_lost := 0         # troops the sim took whose shots have not landed on screen yet
var _minus_label: Label3D      # the red -N over the squad
var _minus_n := 0
var _minus_t0 := -10.0         # when the current -N window opened (_anim_t)
var _minus_last := -10.0       # the last loss added to it
var _minus_pop := 0.0
var _hit_sfx_t := 0.0          # the squad's hurt sound plays at most this often
var _shown_count: Dictionary = {}  # ally kind -> figures drawn (updated on squad changes)
var _boss_music := false
var _key_light: OmniLight3D = null
var _anim_t := 0.0             # animation clock (seconds)
var _meshes: Dictionary = {}            # size -> BoxMesh / name -> Mesh, shared by this level's obstacles
var _mats: Dictionary = {}              # colour -> StandardMaterial3D
## Debug arg `events=1`: print each sim event with its frame (to aim screenshots).
static var _log_events := OS.get_cmdline_user_args().has("events=1")

const RUN_SPEED := 1.7         # the baked walk cycle played faster reads as a run
const CORPSE_CAP := 260        # bodies lying on the road (oldest go first)
const FALL_TIME := 0.32        # seconds to topple flat
const BODY_TIME := 1.1         # seconds a body lies on the road before dissolving


func setup(level: Dictionary, upgrades: Dictionary, w: World, f: Fx, fnt: Font, is_demo := false) -> LevelView:
	world = w
	fx = f
	font = fnt
	demo = is_demo
	level_id = int(level.get("id", 1))
	_level = level
	district = district_of(level)
	sim = LevelSim.new(level, Game.units, upgrades)
	fx.scroll_speed = 0.0
	return self


## The level's city district (street theme): its "district" key, else 10 levels each.
static func district_of(level: Dictionary) -> int:
	if level.has("district"):
		return clampi(int(level["district"]), 1, 5)
	return clampi(ceili(int(level.get("id", 1)) / 10.0), 1, 5)


func _ready() -> void:
	world.set_theme(district, String(_level.get("look", "")))   # v2.1: night / storm / rush looks
	for k in ALLY_KINDS + ENEMY_KINDS:
		var cap := 0
		if k in ALLY_KINDS:
			cap = ALLY_CAP + CORPSE_CAP
		else:
			cap = int(ENEMY_CAP.get(k, HORDE_CAP * 3)) + (8 if k == "boss" else CORPSE_CAP)
		var c := Crowd.new().setup(k, cap, "constable" if k in ALLY_KINDS else "thug")
		add_child(c)
		_crowds[k] = c
		# Stronger rim light keeps figures off the road, more so at dusk and night.
		(c.material_override as ShaderMaterial).set_shader_parameter("rim_strength",
			(0.4 if k in ALLY_KINDS else 0.3) + (0.2 if district >= 4 else 0.0) + (BOSS_RIM if k == "boss" else 0.0))
	if JSON.stringify(_level.get("events", [])).contains("lieutenant"):
		_lieutenant_crowd()   # at load, so his recoloured mesh never costs a frame mid-level
	_build_lasers()
	if district >= 4:
		# Dusk and night: a soft key light rides with the squad so it never sinks into the road.
		_key_light = OmniLight3D.new()
		_key_light.omni_range = 10.0
		_key_light.light_energy = 1.6 if district >= 5 else 1.0
		_key_light.light_color = Color(1.0, 0.95, 0.85)
		_key_light.shadow_enabled = false
		add_child(_key_light)
	_squad_label = GateRowView._label(font, 120, 0.011)
	_squad_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_squad_label.no_depth_test = true
	_squad_label.render_priority = 8
	_squad_label.outline_render_priority = 7
	_squad_label.modulate = Color("8fd0ff")
	add_child(_squad_label)
	_minus_label = GateRowView._label(font, 110, 0.011)
	_minus_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_minus_label.no_depth_test = true
	_minus_label.render_priority = 9
	_minus_label.outline_render_priority = 8
	_minus_label.modulate = MINUS_RED
	_minus_label.visible = false
	add_child(_minus_label)
	_build_shield()
	_build_heat_ring()
	_prewarm()
	var outfit := Game.outfit()
	var hc: Dictionary = Game.economy["hero_colors"]
	(_crowds["hero"] as Crowd).recolor({Color(String(hc["shirt"])): Color(String(outfit["shirt"])),
		Color(String(hc["pants"])): Color(String(outfit["pants"]))})
	HeroAccessory.attach(_crowds["hero"] as Crowd, outfit)   # v2: the outfit's head accessory
	WeaponLook.apply_to_crowds(_crowds, Game.save)           # v2: Armory tier colours
	var ks := Game.knife_skin()
	fx.set_knife_skin(Color(String(ks["blade"])), String(ks["trail"]))
	_sync_allies(Vector3(0, 0, 2))
	_squad_label.visible = false
	charges_changed.emit(sim.charges)
	squad_changed.emit(sim.squad.total())


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	# The steering finger can lift while the game is paused or the squad is down: let go of it
	# anyway, or a revive starts with the squad parked between lanes on a stale anchor.
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).index == _steer_id:
		_reset_steer()
	if demo or paused or _state != "play" or not input_enabled:
		return
	# Spec v2 §2: a short still touch in the lower half is a tap (powers the hero, never
	# steers); a touch that moves is a swipe (steers 1:1 anywhere on screen, never fires).
	if _touch == null:
		_touch = TouchClassifier.new(Game.units.get("input", {}), touch_density())
	var now := Time.get_ticks_msec() / 1000.0
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch.press(t.index, t.position, now)
			return
		var from: Variant = _touch.origin(t.index)
		var r := _touch.release(t.index, t.position, now)
		if r == "tap" and from != null and _touch.in_zone(from, get_viewport().get_visible_rect().size):
			tap()
			_last_tap_pos = from
		if t.index == _steer_id:
			_steer_id = -1
			_touching = false
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touch.move(d.index, d.position, now) != "steer":
			return
		if _steer_id < 0:
			# The swipe starts where the finger went down, so the first few pixels count too.
			_steer_id = d.index
			_touching = true
			_drag_from_x = (_touch.origin(d.index) as Vector2).x
			_steer_from = _squad_x
			_steer_x = _squad_x
		if d.index != _steer_id:
			return
		var w := get_viewport().get_visible_rect().size.x
		_steer_x = clampf(_steer_from + (d.position.x - _drag_from_x) / w * STEER_PER_SCREEN,
			LANE_X[0], LANE_X[2])
		# Finger went past the edge: re-anchor so dragging back responds at once.
		if _steer_x == LANE_X[0] or _steer_x == LANE_X[2]:
			_drag_from_x = d.position.x
			_steer_from = _steer_x
		var lane := sim.lane
		var half := (LANE_X[1] - LANE_X[0]) * 0.5 + LANE_SLACK
		if _steer_x > LANE_X[lane] + half:
			_move(1)
		elif _steer_x < LANE_X[lane] - half:
			_move(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT or k == KEY_A:
			_move(-1)
		elif k == KEY_RIGHT or k == KEY_D:
			_move(1)
		elif k == KEY_S:
			use_power("shield")
		elif k == KEY_B:
			use_power("bomb")
		elif k == KEY_SPACE:
			tap()


## Screen density for the tap threshold: the OS scale, or dots per inch over 160 (Android dp).
static func touch_density() -> float:
	return maxf(DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi() / 160.0)


func _reset_steer() -> void:
	_steer_id = -1
	_touching = false


## One tap: the hero's heat rises (LevelSim.tap, spec v2 §2) and his hand flicks.
func tap() -> void:
	if paused or _state != "play":
		return
	taps += 1
	_last_tap_s = Time.get_ticks_msec() / 1000.0
	_last_tap_pos = Vector2(-1e9, -1e9)
	Analytics.note_tap(level_id, sim.time)  # spec v2 §2: taps per 10 s of each level (tap fatigue)
	if sim.has_method("tap"):
		sim.call("tap")
	else:
		var tc: Dictionary = Game.units.get("hero", {}).get("tap", {})
		_heat_local = minf(_heat_local + float(tc.get("per_tap", 0.3)), 1.0)
	_flick_t = 0.0
	# The flick: a pinch of sparks off his throwing hand.
	if not _allies.is_empty() and _allies[0]["kind"] == "hero" and sim.squad.hero_alive():
		fx.burst((_allies[0]["pos"] as Vector3) + Vector3(0.32, 1.35, -0.25), Color(1.0, 0.9, 0.6), 3, 2.2, 0.07, 0.16, 1.0, 0.0)


## The hero's tap heat 0..1 (LevelSim.tap_heat; the view's own estimate until the sim has it).
func tap_heat() -> float:
	var h: Variant = sim.get("tap_heat") if sim else null
	return float(h) if h != null else _heat_local


func _build_heat_ring() -> void:
	_heat_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.9, 1.9)
	_heat_ring.mesh = pm
	_heat_mat = ShaderMaterial.new()
	_heat_mat.shader = GateRowView.ARC
	_heat_mat.set_shader_parameter("track", Color(HEAT_COLD, 0.3))
	_heat_mat.set_shader_parameter("inner", 0.74)
	_heat_mat.set_shader_parameter("outer", 0.92)
	_heat_ring.material_override = _heat_mat
	_heat_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_heat_ring)


## The heat arc follows the hero's feet: it fills and warms (blue, gold, red-hot) with tapping.
func _update_heat_ring(d: float) -> void:
	_flick_t += d
	if sim.get("tap_heat") == null:
		var tc: Dictionary = Game.units.get("hero", {}).get("tap", {})
		_heat_local = maxf(_heat_local - d / maxf(float(tc.get("decay_s", 1.0)), 0.05), 0.0)
	var show: bool = not demo and _state == "play" and not _allies.is_empty() \
		and _allies[0]["kind"] == "hero" and sim.squad.hero_alive()
	_heat_ring.visible = show
	if not show:
		return
	var h := clampf(tap_heat(), 0.0, 1.0)
	_heat_ring.position = (_allies[0]["pos"] as Vector3) + Vector3(0, 0.05, 0)
	_heat_mat.set_shader_parameter("fill", h)
	var c := HEAT_COLD.lerp(HEAT_WARM, h * 2.0) if h < 0.5 else HEAT_WARM.lerp(HEAT_HOT, h * 2.0 - 1.0)
	_heat_mat.set_shader_parameter("color", c)


## The hero's fire-rate multiplier from the heat (1 until the sim has it).
func hero_mult() -> float:
	return float(sim.call("hero_rate_mult")) if sim and sim.has_method("hero_rate_mult") else 1.0


## The level's "this is new" card (spec v2 §11), made on first use.
func new_item_card() -> NewItemCard:
	if item_card == null:
		item_card = NewItemCard.new().setup(self)
		add_child(item_card)
	return item_card


func _move(dir: int) -> void:
	var before := sim.lane
	sim.set_lane(sim.lane + dir)
	if sim.lane != before:
		Sfx.play("swoosh", -6.0)
		if _tut_row >= 0:
			_tut_done[_tut_row] = true
			_tut_row = -1
			tutorial.emit(false)


## Near-miss revive (after the loss screen's rewarded ad): the squad bursts back.
func revive(troops: int) -> bool:
	if not sim.revive(troops):
		return false
	_handle_events(sim.drain())
	return true


## A power button press. Ignored (nothing spent) while the street is frozen (pause, a first-run
## lesson's hold), and when it comes within input.power_guard_s of a fire tap that landed right
## next to `button` (screen rect): a thumb tapping fast that slid onto the button. A press with
## the other thumb while tapping still works. The sim also takes one bomb at a time.
func use_power(id: String, button := Rect2()) -> bool:
	if paused or _state != "play" or hold or _time_scale <= 0.0:
		return false
	var guard := float(Game.units.get("input", {}).get("power_guard_s", 0.0))
	if guard > 0.0 and button.has_area() and Time.get_ticks_msec() / 1000.0 - _last_tap_s < guard 			and button.grow(button.size.x * 0.5).has_point(_last_tap_pos):
		return false
	var ok := sim.use_power(id)
	if ok:
		charges_changed.emit(sim.charges)
		_handle_events(sim.drain())
	return ok


## A first-run lesson's charge comes back (Tutorial): the lesson used it, so the player still
## has the power for this level and no recharge starts for it.
func refund_power(id: String) -> void:
	sim.charges[id] = int(sim.charges.get(id, 0)) + 1
	charges_changed.emit(sim.charges)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if not demo:
		# Effects run on the street's clock: a bomb in the air waits for a pause or a lesson.
		fx.time_scale = 0.0 if paused else (_time_scale if _state == "play" else 1.0)
	if paused:
		return
	if demo:
		world.scroll(4.0 * delta)
		_update_visuals(delta)
		return
	match _state:
		"play":
			_update_time_scale(delta)
			var d := delta * _time_scale
			_acc += d
			var steps := 0
			# The sim hits obstacles where the squad really is (between lanes while steering).
			# Autoplay keeps lane centres so its runs match the headless routes.
			if input_enabled:
				sim.set_squad_x(_squad_x)
			while _acc >= DT and steps < 8:
				sim.step(DT)
				_acc -= DT
				steps += 1
				_handle_events(sim.drain())
				if _state != "play":
					break
			world.scroll(sim.traveled - _last_traveled)
			_last_traveled = sim.traveled
			fx.scroll_speed = sim.S * _time_scale
			var stand := sim.standoff()
			if stand and not _was_standoff:
				# Standoff: the street stops and the squad plants its feet.
				fx.burst(Vector3(_squad_x, 0.1, 1.2), Color(0.75, 0.7, 0.62), 18, 3.0, 0.4, 0.6, 1.0, 2.0)
				Sfx.play("thunk", -6.0, 0.7)
			_was_standoff = stand
			_update_visuals(d)
		"finale", "done_win":
			fx.scroll_speed = 0.0
			_update_visuals(delta)
		"done":
			if sim.state == "run":
				# Revived from outside (main.gd called sim.revive): pick the revive event up.
				_handle_events(sim.drain())
				return
			_end_t += delta
			var d := delta * 0.3
			world.scroll(sim.S * d)
			fx.scroll_speed = sim.S * 0.3
			_update_visuals(d)
			if _end_t > 1.2 and _end_t - delta <= 1.2:
				finished.emit({"won": false, "cause": sim.lose_cause, "kills": sim.kills, "level": level_id})


## The street's speed this frame (1 = real time; 0 only while a first-run tutorial holds it).
func time_scale() -> float:
	return _time_scale


func _update_time_scale(delta: float) -> void:
	var target := 1.0
	if hold:
		_time_scale = 0.0
		return
	# Spec v2 §3: nothing else slows the street (no rank spotlight, no red-gate or boss-death
	# slow motion); only the first-run tutorial holds above and below stop it.
	if _spotlight > 0.0:
		_spotlight -= delta   # the new rank's gold ring stays up for a second, at full speed
	for id in _rows:
		var row: Dictionary = (_rows[id] as GateRowView).row
		var z := float(row["z"])
		# v2 §12.3: only until Tutorial has taught the drag (else: a freeze with no cue, every replay).
		if String(row.get("tutorial", "")) == "swipe" and not _tut_done.has(id) and z > -17.0 and not Game.hint_seen("swipe"):
			# Freeze only while the squad sits in a lane with no gate: "swipe to grab one".
			var empty := true
			for g in row["gates"]:
				if int(g["lane"]) == sim.lane:
					empty = false
			if empty:
				if _tut_row != id:
					_tut_row = id
					tutorial.emit(true)
				target = 0.0
			else:
				_tut_done[id] = true
				if _tut_row == id:
					_tut_row = -1
					tutorial.emit(false)
	_time_scale = target if target == 0.0 else move_toward(_time_scale, target, 0.08)


# ---------------------------------------------------------------- events

func _handle_events(events: Array) -> void:
	for e in events:
		if perf_on and String(e["type"]) in PERF_EVENTS:
			var tag := "" if not e.has("unit") else ":" + String(e["unit"])
			if e.get("horde") is Dictionary:
				tag = ":" + String((e["horde"] as Dictionary).get("enemy", ""))
			perf_marks.append(String(e["type"]) + tag)
		if _log_events and not String(e["type"]) in ["kill", "gate_tick", "boss_hit"]:
			print("EV %d %s %s" % [Engine.get_process_frames(), e["type"], e["horde"].get("enemy", "") if e.get("horde") is Dictionary else ""])
		match String(e["type"]):
			"row_spawn":
				var v := GateRowView.new().setup(e["row"], font, LANE_X)
				add_child(v)
				_rows[e["row"]["id"]] = v
				v.position.z = float(e["row"]["z"])
			"gate_tick":
				_on_gate_tick(e)
			"row_pass":
				_on_row_pass(e)
			"horde_spawn":
				_on_horde_spawn(e["horde"], bool(e.get("lieutenant", false)))
			"kill":
				Sfx.play("die", -4.0)
			"horde_cleared":
				pass
			"melee_start":
				Sfx.play("swoosh", -2.0, 0.7)
			"melee":
				_on_melee(e)
			"turncoat":
				_on_turncoat(e)
			"shield_broken":
				var hb: Dictionary = _hordes.get(e["horde"], {})
				if not hb.is_empty():
					fx.burst(_horde_front(hb) + Vector3(0, 1.2, 0), Color("9fc6ff"), 30, 7.0, 0.22, 0.6)
					Sfx.play("clink")
			"barrel_armed":
				var bo: Dictionary = _obstacles.get(e["ob"]["id"], {})
				if not bo.is_empty():
					Sfx.play("tick", 0.0, 1.6)
			"barrel_boom":
				_on_barrel_boom(e)
			"armour_block":
				var hv: Dictionary = _hordes.get(e["horde"], {})
				if not hv.is_empty():
					var p := _horde_front(hv)
					fx.burst(p + Vector3(0, 1.2, 0), Color(1, 1, 0.8), 8, 5.0, 0.12, 0.3)
					Sfx.play("clink")
			"foe_mod":
				var hv: Dictionary = _hordes.get(e["horde"], {})
				if not hv.is_empty():
					var p := _horde_front(hv)
					fx.burst(p + Vector3(0, 1.0, 0), Color("6fa8ff"), 24, 6.0, 0.2, 0.6)
					Sfx.play("flip")
			"bomb":
				_on_bomb(e)
			"bomb_throw":
				_on_bomb_throw(e)
			"return_fire":
				_on_return_fire(e)
			"shield_on":
				Sfx.play("shield")
			"hint":
				new_item_card().show_item(e["ev"])  # first: it marks the hint seen, so Hud's old hand stays away
				hint.emit(e["ev"])
			"finish_spawn":
				_spawn_finish(float(e["at"]))
			"finish":
				_land_impacts(true)
				_clear_threats()
				_begin_strike()
			"lost":
				_state = "done"
				_end_t = 0.0
				_land_impacts(true)   # the last shots land with the loss
				_clear_threats()
				Sfx.play("lose")
				Game.vibrate(200)
				_mark_cause(e)
			"obstacle_spawn":
				_spawn_obstacle(e["ob"])
			"cage_spawn", "cage_open", "cage_free", "cage_lost":
				_on_cage_event(e)
			"obstacle_broken":
				_on_obstacle_broken(e["ob"])
			"obstacle_hit":
				world.shake(0.5)
				Sfx.play("hurt")
				var hit_ob: Dictionary = e["ob"]
				var hole := String(hit_ob.get("kind", "")) == "pothole"
				if String(hit_ob.get("kind", "")) == "barrel":
					# The squad smashes an unarmed drum: metal and oil fly (never "rubber").
					var bp := _obstacle_pos(hit_ob) + Vector3(0, 0.7, 0)
					fx.burst(bp, GateRowView.BARREL_RED, 16, 6.0, 0.22, 0.6, 4.0)
					fx.burst(bp, Color(0.08, 0.07, 0.06), 12, 4.0, 0.3, 0.7, 2.0)
				# Exactly the figures that stood on its footprint fall; the rest close ranks.
				_kill_overlap(e, hole)
				# A pothole stays in the road and rides away; anything solid was smashed.
				_free_obstacle(int(hit_ob["id"]), hole)
			"obstacle_pass":
				_free_obstacle(int(e["ob"]["id"]), true)
			"pothole_pass":
				_on_pothole(e)
			"barricade_hit":
				_on_barricade_hit(e)
			"telegraph":
				_on_telegraph(e)
			"attack_land":
				_on_attack_land(e)
			"boss_shot":
				_on_boss_shot(e)
			"boss_hit":
				_on_boss_hit(e)
			"rank_join":
				_on_rank_join(e)
			"revive":
				_on_revive(e)
	_emit_total()


## The squad's count as the player sees it: the sim's, plus what shots still in the air took.
func shown_total() -> int:
	return maxi(sim.squad.total() + _pending_lost, 0)


func _emit_total() -> void:
	var n := shown_total()
	if n != _last_total:
		_last_total = n
		squad_changed.emit(n)
		_label_pop = 1.0


func _on_gate_tick(e: Dictionary) -> void:
	for id in _rows:
		var v: GateRowView = _rows[id]
		for g in v.row["gates"]:
			if g == e["gate"]:
				v.refresh(g, true)
				var root := v.lane_root(int(g["lane"]))
				if root:
					var p := root.global_position + Vector3(0, 2.0, 0.1)
					if e["flipped"]:
						fx.confetti(p, 30)
						Sfx.play("flip")
						Game.vibrate(40)
					else:
						fx.burst(p, Color(1, 1, 1), 3, 3.0, 0.12, 0.25)
						Sfx.play("tick", -3.0, 1.0 + clampf(float(e["to"]) / 30.0, -0.3, 0.6))


func _on_row_pass(e: Dictionary) -> void:
	var row: Dictionary = e["row"]
	var v: GateRowView = _rows.get(row["id"])
	_rows.erase(row["id"])
	var g = e["gate"]
	var src := Vector3(LANE_X[sim.lane], 0, -1.5)
	if v:
		v.passed(int(g["lane"]) if g != null else -1)
	if g == null:
		return
	var delta := int(e["delta"])
	var col: Color = GateRowView.describe(g)["color"]
	fx.burst(src + Vector3(0, 1.6, 0), col.lightened(0.3), 26, 7.0, 0.22, 0.6)
	match String(g["op"]):
		"num", "pct", "div", "mul", "recruit":
			var txt := NumFormat.signed(delta) if delta != 0 else "+0"
			if g["op"] == "mul":
				txt = "×%d  →  %s" % [int(g["k"]), NumFormat.fmt(int(e["after"]))]
			elif g["op"] == "recruit":
				txt = "+%s %s" % [NumFormat.fmt(delta), String(g["unit"]).to_upper()]
			if delta >= 0:
				Sfx.play("gate_good")
				Sfx.play("recruit", -4.0)
				Game.vibrate(35)
			else:
				Sfx.play("gate_bad")
				Game.vibrate(90)
		"weapon":
			Sfx.play("gate_good")
			Game.vibrate(35)
		"power":
			charges_changed.emit(sim.charges)
			Sfx.play("gate_good")
		"foe_div", "foe_strip":
			Sfx.play("gate_good")
	_sync_allies(src)


func _on_horde_spawn(h: Dictionary, lieutenant := false) -> void:
	var kind := String(h["enemy"])
	# Spec v2.1 §1.3: a lieutenant (the horde or its spawn event says so) is the boss's rig in
	# his own colours, drawn smaller, with a smaller bar.
	var lt := lieutenant or bool(h.get("lieutenant", false)) or kind == "lieutenant"
	if lt:
		kind = "lieutenant"
		_lieutenant_crowd()
	var n := int(h["count"])
	# The sim stands a gang in at most world.gang_figures figures of `per` people each
	# (LevelSim._spawn_horde); one figure row is one of its rows, so rows sit row_gap apart.
	var per := maxi(int(h.get("per", ceili(n / float(HORDE_CAP)))), 1)
	var vis := int(ceil(n / float(per)))
	var cols := int(h["cols"])
	var dx := 9.0 / maxf(cols, 1)
	var dz := float(h["row_gap"]) * (1 if h.has("per") else per)
	var offs: Array = []
	for i in vis:
		var r := i / cols
		var c := i % cols
		var row_n := mini(cols, vis - r * cols)
		var x := (c - (row_n - 1) * 0.5) * dx + randf_range(-0.15, 0.15)
		offs.append(Vector3(x if cols > 1 else 0.0, randf(), r * dz + randf_range(-0.12, 0.12)))  # y holds a phase
	var label := GateRowView._label(font, 90, 0.011)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("ff6b6b") if int(h["armour"]) == 0 else Color("b8c7d9")
	add_child(label)
	var sub := Node3D.new()
	add_child(sub)
	var hv := {"h": h, "kind": kind, "offs": offs, "per": per, "label": label, "sub": sub, "shoot_flash": 0.0,
		"hit_flash": 0.0, "shown": -1, "lt": lt, "bossy": lt or bool(h.get("boss", false)), "leader": is_leader(h)}
	_hordes[h["id"]] = hv
	if hv["bossy"]:
		_build_boss_bar(hv)
		_boss_music = true
		Sfx.play_music("boss")
		_sfx("boss_roar", "blast", 0.0, 0.85 if lt else 0.6)
		world.shake(0.5 if lt else 0.8)
	var label_text := String(h.get("label", ""))
	if label_text != "" and not _shown_banner.has(label_text):
		_shown_banner[label_text] = true
		banner.emit(label_text, Color("ff5a5f"))


func _on_melee(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	if hv.is_empty():
		return
	# The striking row charges into the squad (the sim already removed them).
	var n := mini(int(ceil(int(e["enemies"]) / float(hv["per"]))), (hv["offs"] as Array).size())
	for i in n:
		var o: Vector3 = hv["offs"].pop_front()
		_charging.append({"kind": hv["kind"], "pos": _fig_pos(hv, o), "phase": o.y, "shielded": e["shielded"], "dx": clampf(o.x * 0.35, -1.6, 1.6)})
	var lost := int(e["lost"])
	world.shake(clampf(0.2 + lost * 0.02, 0.2, 0.9))
	if e["shielded"]:
		Sfx.play("blocked")
	elif lost > 0:
		Sfx.play("hurt", -2.0)
		Game.vibrate(60)
		_add_loss(lost)
	_sync_allies(Vector3(_squad_x, 0, -1.0))


func _on_turncoat(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var src := Vector3(_squad_x, 0, -6.0)
	if not hv.is_empty():
		src = _horde_front(hv)
		var n := mini(int(ceil(int(e["n"]) / float(hv["per"]))), (hv["offs"] as Array).size())
		for i in n:
			var o: Vector3 = hv["offs"].pop_front()
			fx.burst(_fig_pos(hv, o) + Vector3(0, 1.0, 0), Color("6fa8ff"), 4, 3.0, 0.18, 0.4)
	Sfx.play("recruit")
	_sync_allies(src)


func _on_barrel_boom(e: Dictionary) -> void:
	var ob: Dictionary = e["ob"]
	var od: Dictionary = _obstacles.get(int(ob["id"]), {})
	var p: Vector3 = (od["node"] as Node3D).position if not od.is_empty() else _obstacle_pos(ob)
	_free_obstacle(int(ob["id"]))
	fx.explosion(p + Vector3(0, 0.8, 0), 2.2)
	fx.ring(p + Vector3(0, 0.3, 0), Color("ff8a2a"), 48, 13.0, 0.3)
	# Spec v2 §5: a big, readable blast count (exactly the gang members it killed).
	var killed := int(e.get("killed", 0))
	if killed > 0:
		fx.float_text("-" + NumFormat.fmt(killed), p + Vector3(0, 3.2, 0), Color("ffd23f"), 2.2, 3.0, 1.5)
	world.shake(1.1)
	Sfx.play("boom")
	Game.vibrate(150)


## Spec v2 §12.5, the throw: the hero winds up with the bomb in his right hand (the overhand
## `throw` clip, slowed so the hand comes forward at units powers.bomb.windup), lets go at the
## clip's release and it arcs, fuse sparking, to where its target will be when the sim sets it
## off (the bomb_throw event's z, `t` s after the tap). A ring on the road marks that spot.
func _on_bomb_throw(e: Dictionary) -> void:
	_bomb_throw_t = 0.0
	var to := Vector3(float(e.get("x", _squad_x)), 0.4, float(e["z"]))
	_bomb_launch = {"id": int(e.get("id", 0)), "to": to, "t": float(e["t"]),
		"windup": float(e.get("windup", 0.0)), "arc": clampf(-float(e["z"]) * 0.18, 2.5, 9.0)}
	_bomb_speed = bomb_clip_speed(float(e.get("windup", 0.0)), _throw_clip())
	_show_bomb_mark(to, float(e.get("radius", 4.0)))
	Sfx.play("swoosh", -6.0, 0.6)


## The clip runs at release / windup speed so the hand comes forward exactly at the windup.
static func bomb_clip_speed(windup: float, clip: String) -> float:
	var release := float(Crowd.clips.get(clip, {}).get("release", 0.54 * Crowd.clip_length(clip)))
	return release / windup if windup > 0.0 and release > 0.0 else 1.0


## Where the hero's right hand is at `u` (0..1) of the throw clip, in his own frame (forward
## = -z): a rough match of tools/bake_vat.gd THROW_KEYS (cocked behind the head, then over
## the top to the release in front).
const HAND_KEYS := [[0.0, Vector3(0.32, 0.95, 0.05)], [0.3, Vector3(0.34, 1.75, 0.35)],
	[0.38, Vector3(0.34, 1.8, 0.4)], [0.46, Vector3(0.3, 1.98, -0.1)], [0.54, Vector3(0.25, 1.72, -0.55)],
	[0.72, Vector3(-0.15, 1.2, -0.5)], [1.0, Vector3(0.32, 0.95, 0.05)]]


static func hand_offset(u: float) -> Vector3:
	for i in range(1, HAND_KEYS.size()):
		var k1: Array = HAND_KEYS[i]
		if u <= float(k1[0]):
			var k0: Array = HAND_KEYS[i - 1]
			var f := (u - float(k0[0])) / maxf(float(k1[0]) - float(k0[0]), 0.001)
			return (k0[1] as Vector3).lerp(k1[1], clampf(f, 0.0, 1.0))
	return HAND_KEYS[-1][1]


## The release: the bomb leaves his hand and flies the rest of the sim's time.
func _launch_bomb(hand: Vector3) -> void:
	var b := _bomb_launch
	_bomb_launch = {}
	fx.held_bomb_on = false
	fx.bomb(hand, b["to"], maxf(float(b["t"]) - float(b["windup"]), 0.2), float(b["arc"]), int(b["id"]))
	Sfx.play("swoosh", -3.0, 0.8)


func _show_bomb_mark(at: Vector3, radius: float) -> void:
	if _bomb_mark == null:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.9
		ring.outer_radius = 1.0
		ring.rings = 32
		ring.ring_segments = 6
		_bomb_mark = MeshInstance3D.new()
		_bomb_mark.mesh = ring
		_bomb_mark_mat = StandardMaterial3D.new()
		_bomb_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bomb_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bomb_mark_mat.albedo_color = Color(1.0, 0.3, 0.15, 0.0)
		_bomb_mark.material_override = _bomb_mark_mat
		_bomb_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bomb_mark)
	_bomb_mark.position = Vector3(at.x, 0.07, at.z)
	_bomb_mark.scale = Vector3(radius, 0.1, radius)
	_bomb_mark.set_meta("t", 0.0)
	_bomb_mark.visible = true


func _tick_bomb_mark(d: float) -> void:
	if _bomb_mark == null or not _bomb_mark.visible:
		return
	var t := float(_bomb_mark.get_meta("t", 0.0)) + d
	_bomb_mark.set_meta("t", t)
	_bomb_mark_mat.albedo_color = Color(1.0, 0.3, 0.15, minf(t * 3.0, 1.0) * (0.55 + 0.35 * absf(sin(t * 12.0))))


## The landing: the blast where the sim set it off (a gang's front, a wreck, the road), as big
## as the blast radius really is, the exact number it killed and the boss's health it took.
func _on_bomb(e: Dictionary) -> void:
	if not _bomb_launch.is_empty() and int(_bomb_launch["id"]) == int(e.get("id", -1)):
		_bomb_launch = {}   # set off before it left his hand (the stash's safety net)
		fx.held_bomb_on = false
	fx.land_bomb(int(e.get("id", 0)))
	if _bomb_mark != null:
		_bomb_mark.visible = false
	var hv: Dictionary = _hordes.get(e.get("horde", -1), {})
	var p := Vector3(float(e.get("x", _squad_x)), 0.5, float(e["z"]))
	if not hv.is_empty() and String(e.get("target", "horde")) == "horde":
		p.z = _horde_front(hv).z
	fx.blast(p, float(e.get("radius", 4.0)), clampf(-p.z / 50.0, 0.0, 1.0))
	var killed := int(e.get("killed", 0))
	if killed > 0:
		fx.float_text("-" + NumFormat.fmt(killed), p + Vector3(0, 3.0, 0), Color("ffd23f"), 2.0, 3.0, 1.3)
	var boss_dmg := int(e.get("boss_dmg", 0))
	if boss_dmg > 0:
		fx.float_text("-" + NumFormat.fmt(boss_dmg), p + Vector3(0, 6.0, 0), Color("ff5050"), 2.0, 2.5, 1.3)
	world.shake(1.0)
	Sfx.play("boom")
	Game.vibrate(150)


## Spec v2.1 §1.1: a gang firing back. Big muzzle flashes on its front shooters (bigger still
## for its opening volley), up to 8 orange-red tracers that take about a second to reach the
## squad (or the shield), and the loss lands with them: the figures they hit fall, a red -N, the
## troop pill pulses, a short buzz.
func _on_return_fire(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var opening := bool(e.get("opening", false))
	var n := clampi(int(e.get("shots", 1)), 1, TRACERS_PER_EVENT)
	var froms := _shooter_points(hv, n, Vector3(float(e.get("x", 0.0)), 1.35, float(e.get("z", -45.0))))
	if not hv.is_empty():
		hv["shoot_flash"] = 0.2 if opening else 0.12
	for f in froms:
		fx.muzzle_big(f, _flash_k(f) * (1.4 if opening else 1.0))
	_volley(froms, int(e.get("lost", 0)), bool(e.get("blocked", false)), "etracer")
	if _rf_sfx_t <= 0.0 or opening:
		_rf_sfx_t = 0.09
		Sfx.play("shot", -4.0 if opening else -8.0, randf_range(0.8, 0.95))


## Spec v2.1 §1.3: the boss's (or lieutenant's) gun: a big flash at his gun hand and two heavy
## tracers; the loss lands with them and shows its -N like any other.
func _on_boss_shot(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var from := Vector3(0, 4.0, -40.0)
	if not hv.is_empty():
		hv["shoot_flash"] = 0.2
		from = _boss_gun(hv)
	fx.muzzle_big(from, _flash_k(from) * 1.6)
	_volley([from, from + Vector3(0.25, -0.15, 0.1)], int(e.get("lost", 0)), bool(e.get("blocked", false)), "etracer_big")
	Sfx.play("blast", -3.0, 0.85)


## Where up to `n` of a gang's front figures hold their guns (`fallback` when it is gone).
func _shooter_points(hv: Dictionary, n: int, fallback: Vector3) -> Array:
	var out: Array = []
	var offs: Array = hv.get("offs", [])
	if offs.is_empty():
		for i in n:
			out.append(fallback + Vector3(randf_range(-1.5, 1.5), 0, randf_range(0, 1.5)))
		return out
	var front := mini(offs.size(), maxi(int(hv["h"].get("cols", 1)) * 2, 1))
	for i in n:
		out.append(_fig_pos(hv, offs[randi() % front]) + Vector3(0.22, 1.35, 0.55))
	return out


## The boss's (or lieutenant's) gun hand.
func _boss_gun(hv: Dictionary) -> Vector3:
	var front := _horde_front(hv)
	var k := _boss_scale(hv) * boss_grow(front.z) * crowd_scale((hv["offs"] as Array).size())
	return front + Vector3(0.5, CHAR_H * k * 0.62, 0.8)


## Muzzle flashes grow with distance so a gang 50 m up the street visibly opens fire.
static func _flash_k(at: Vector3) -> float:
	return clampf(-at.z / 22.0, 1.0, 2.4)


## Fires `froms.size()` incoming tracers at the squad (onto the shield when `blocked`). The
## figures they aim at are the ones that fall: `lost` troops land when the first one arrives.
func _volley(froms: Array, lost: int, blocked: bool, kind: String) -> void:
	var targets := _volley_targets(froms, blocked)
	var first := INF
	for i in froms.size():
		var t := fx.enemy_shoot(froms[i], targets[i], true, kind)
		if t > 0.0:
			first = minf(first, t)
	var rel: Array = []
	for p in targets:
		rel.append((p as Vector3) - Vector3(_squad_x, 0, 0))
	_impacts.append({"at": _anim_t + (first if first < INF else 0.0), "lost": maxi(lost, 0), "blocked": blocked,
		"points": rel})
	_pending_lost += maxi(lost, 0)


## Where a volley's tracers end: on the shield bubble where each shot enters it (it ripples there
## when the shot lands), or on followers near the front (the hero only when he stands alone).
func _volley_targets(froms: Array, blocked: bool) -> Array:
	var out: Array = []
	var n := froms.size()
	if blocked:
		for i in n:
			var aim := Vector3(_squad_x + randf_range(-1.2, 1.2), 1.0 + randf(), 0.6)
			out.append(_shield_fx.entry(froms[i], aim) if _shield_fx != null and _shield_fx.is_up()
				else Vector3(_squad_x + randf_range(-1.4, 1.4), 1.2 + randf(), -2.2))
		return out
	var pool: Array = _allies.filter(func(a): return a["kind"] != "hero")
	if pool.is_empty():
		pool = _allies
	pool.sort_custom(func(a, b): return (a["pos"] as Vector3).z < (b["pos"] as Vector3).z)
	pool = pool.slice(0, maxi(pool.size() / 2, mini(pool.size(), n)))
	for i in n:
		if pool.is_empty():
			out.append(Vector3(_squad_x + randf_range(-1.0, 1.0), 1.0, randf_range(0.0, 1.5)))
		else:
			out.append((pool[randi() % pool.size()]["pos"] as Vector3) + Vector3(0, 1.0, 0))
	return out


## Shots that reached the squad this frame (all of them when `all`: the loss, the finish).
func _land_impacts(all := false) -> void:
	var i := 0
	while i < _impacts.size():
		if all or float(_impacts[i]["at"]) <= _anim_t:
			var im: Dictionary = _impacts[i]
			_impacts.remove_at(i)
			_land_impact(im)
		else:
			i += 1
	_emit_total()


func _land_impact(im: Dictionary) -> void:
	_pending_lost = maxi(_pending_lost - int(im["lost"]), 0)
	var pts: Array = []
	for p in im["points"]:
		pts.append((p as Vector3) + Vector3(_squad_x, 0, 0))
	if im["blocked"]:
		# Each blocked shot stops on the bubble, which ripples where it lands (rate-limited there).
		for p in pts.slice(0, 3):
			if _shield_fx != null and _shield_fx.is_up():
				_shield_fx.ripple_at(p)
			else:
				fx.burst(p, Color("9fc6ff"), 5, 4.0, 0.16, 0.25)
		if _hit_sfx_t <= 0.0:
			_hit_sfx_t = 0.12
			Sfx.play("blocked", -6.0)
		return
	var lost := int(im["lost"])
	if lost <= 0:
		for p in pts.slice(0, 3):
			fx.burst(Vector3((p as Vector3).x, 0.1, (p as Vector3).z), Color(0.7, 0.66, 0.6), 4, 2.0, 0.18, 0.3, 1.0)
		return
	for p in pts:
		fx.burst(p, Color(1.0, 0.25, 0.15), 4, 3.0, 0.16, 0.25, 1.5)
	if _hit_sfx_t <= 0.0:
		_hit_sfx_t = 0.12
		Sfx.play("hurt", -5.0)
	world.shake(clampf(0.12 + lost * 0.01, 0.12, 0.5))
	_add_loss(lost)
	_sync_allies(Vector3(_squad_x, 0, 0), pts)


## Spec v2.1 §1.1: the red -N over the squad. Losses within MINUS_WINDOW s add up; a later one
## starts a new number (with a short buzz, through the vibration setting).
func _add_loss(n: int) -> void:
	if n <= 0:
		return
	if _anim_t - _minus_t0 > MINUS_WINDOW:
		_minus_t0 = _anim_t
		_minus_n = 0
		Game.vibrate(30)
	_minus_n += n
	_minus_last = _anim_t
	_minus_pop = 1.0
	_minus_label.text = "-" + NumFormat.fmt(_minus_n)
	_minus_label.visible = true


func _tick_minus(d: float) -> void:
	if not _minus_label.visible:
		return
	var age := _anim_t - _minus_last
	if age > MINUS_HOLD:
		_minus_label.visible = false
		return
	_minus_pop = maxf(_minus_pop - d * 5.0, 0.0)
	var a := clampf((MINUS_HOLD - age) / 0.3, 0.0, 1.0)
	_minus_label.modulate = Color(MINUS_RED, a)
	_minus_label.outline_modulate = Color(0.05, 0.05, 0.08, a)
	_minus_label.position = Vector3(_squad_x, 3.7 + 0.9 * minf(age, MINUS_HOLD), -0.6)
	_minus_label.scale = Vector3.ONE * (1.0 + 0.6 * _minus_pop)


# ---------------------------------------------------------------- v1 threats and moments

## Plays a spec sound id, or `fallback` until AUDIO ships a file for it.
func _sfx(id: String, fallback: String, vol := 0.0, pitch := 1.0) -> void:
	Sfx.play(id if Sfx.has_sound(id) else fallback, vol, pitch)


func _on_pothole(e: Dictionary) -> void:
	var hole := _obstacle_pos(e["ob"])
	_sfx("pothole", "thunk", 0.0, 0.8)
	fx.burst(hole + Vector3(0, 0.3, 0), Color(0.42, 0.36, 0.3), 16, 4.0, 0.22, 0.5)
	var lost := int(e["lost"])
	if lost > 0:
		fx.float_text("-" + NumFormat.fmt(lost), hole + Vector3(0, 2.6, 0), Color("ff5a5f"), 0.9)
		Game.vibrate(70)
	# The troops the hole took drop into it (obstacle_hit picks exactly which ones).
	_death_at = hole


func _on_barricade_hit(e: Dictionary) -> void:
	var p := _obstacle_pos(e["ob"])
	_splinters(p, 1.4)
	_sfx("crash", "boom", -2.0, 0.9)
	world.shake(0.8)
	Game.vibrate(90)
	var lost := int(e["lost"])
	if lost > 0:
		fx.float_text("-" + NumFormat.fmt(lost), p + Vector3(0, 2.8, 0), Color("ff5a5f"), 0.9)
	var g = e.get("blocked_gate")
	if g == null:
		return
	for id in _rows:
		var v: GateRowView = _rows[id]
		for gg in v.row["gates"]:
			if is_same(gg, g):
				v.refresh(gg, true)
				Sfx.play("thunk", -2.0, 0.8)


func _on_obstacle_broken(ob: Dictionary) -> void:
	var p := _obstacle_pos(ob)
	match String(ob.get("kind", "")):
		"barricade":
			_splinters(p, 1.0)
			_sfx("crash", "boom", -4.0, 1.1)
		"car":
			fx.explosion(p + Vector3(0, 0.8, 0), 1.2)
			fx.burst(p + Vector3(0, 1.0, 0), Color(0.6, 0.62, 0.66), 20, 7.0, 0.3, 0.8)
			Sfx.play("boom", -4.0, 1.1)
			world.shake(0.5)
		_:
			fx.burst(p + Vector3(0, 1.0, 0), Color(0.55, 0.45, 0.35), 24, 6.0, 0.3, 0.7)
			Sfx.play("boom", -8.0, 1.4)
	_free_obstacle(int(ob["id"]))


## Wood flying apart: planks, splinters and dust.
func _splinters(p: Vector3, k: float) -> void:
	fx.burst(p + Vector3(0, 0.9, 0), Color("9a6b3c"), int(26 * k), 8.0, 0.32, 0.8, 5.0)
	fx.burst(p + Vector3(0, 0.9, 0), Color("d63a3a"), int(8 * k), 7.0, 0.26, 0.7, 5.0)
	fx.burst(p + Vector3(0, 0.5, 0), Color(0.75, 0.7, 0.62), int(10 * k), 3.0, 0.45, 0.7, 1.0, 2.0)


## Spec v2.1 §1.2-1.3: an attack is coming to `lane` (the sim's telegraph event). The lane
## where the squad stands is marked in the kind's colour with a countdown to the landing; a
## sniper paints it with his laser, a grenadier or molotov lobs his grenade or bottle onto it,
## the boss (or lieutenant) raises his arm and his barrage shells arc onto it.
func _on_telegraph(e: Dictionary) -> void:
	var kind := String(e.get("kind", ""))
	var lane := clampi(int(e.get("lane", 1)), 0, 2)
	var src := int(e.get("src", e.get("horde", -1)))
	var hv: Dictionary = _hordes.get(src, {})
	var from := Vector3(float(e.get("x", LANE_X[lane])), 1.6, float(e.get("z", -45.0)))
	if not hv.is_empty():
		hv["shoot_flash"] = 0.3 if kind.ends_with("barrage") else 0.15
		if hv["bossy"]:
			from = _boss_gun(hv) + Vector3(0, CHAR_H * 0.4, 0)
		elif not (hv["offs"] as Array).is_empty():
			from = _fig_pos(hv, hv["offs"][randi() % mini((hv["offs"] as Array).size(), 6)]) + Vector3(0, 1.9, 0.3)
	var dur := maxf(_land_time(e) - sim.time, 0.2)
	var spot := Vector3(LANE_X[lane], 0.25, SPOT_Z)
	var th := {"kind": kind, "lane": lane, "src": src, "from": from, "start": sim.time, "land": sim.time + dur,
		"points": [spot]}
	match kind:
		"snipe":
			Sfx.play("tick", -6.0, 2.2)
		"grenade":
			fx.enemy_lob("grenade", from, spot, dur, 4.0)
			_sfx("launcher", "swoosh", -7.0, 1.3)
		"firebomb":
			fx.enemy_lob("lob", from, spot, dur, 2.5)
			Sfx.play("swoosh", -5.0, 0.7)
		"barrage", "lt_barrage":
			var pts: Array = []
			for i in int(SHELLS.get(kind, 3)):
				var p := Vector3(LANE_X[lane] + randf_range(-0.9, 0.9), 0.3, ZONE_Z + randf_range(-3.0, 1.2))
				pts.append(p)
				fx.enemy_lob("shell", from + Vector3(randf_range(-0.4, 0.4), 0, 0), p, dur, randf_range(6.0, 9.0))
			th["points"] = pts
			_sfx("launcher", "boom", -3.0, 0.7)
			world.shake(0.3)
	_threats.append(th)


## The sim's landing of a telegraphed attack: the impact on the marked lane (a sniper round, a
## grenade blast, burning fuel, the barrage), then what it did: blocked by the shield, the loss
## (red -N, the figures it hit fall) or nothing (the squad stepped out of the lane).
func _on_attack_land(e: Dictionary) -> void:
	var kind := String(e.get("kind", ""))
	var lane := clampi(int(e.get("lane", 1)), 0, 2)
	var th: Dictionary = {}
	for t in _threats:
		if t["lane"] == lane and t["kind"] == kind and (th.is_empty() or float(t["land"]) < float(th["land"])):
			th = t
	if th.is_empty():
		th = {"kind": kind, "lane": lane, "src": -1, "from": Vector3(LANE_X[lane], 2.0, -45.0),
			"points": [Vector3(LANE_X[lane], 0.25, SPOT_Z)]}
	else:
		_threats.erase(th)
	(_zones[lane] as Dictionary)["flash"] = 0.18
	var pts: Array = th["points"]
	var spot: Vector3 = pts[0]
	var blocked := bool(e.get("blocked", false))
	if blocked:
		# The shield caught it: the round or the blast lands on the bubble over the squad, which
		# ripples there, not on the road under the figures.
		var hit := _shield_hit(Vector3(spot.x, 9.0, spot.z - 4.0) if kind != "snipe" else th["from"],
			Vector3(_squad_x, 1.2, 0.6))
		spot = Vector3(hit.x, maxf(hit.y - 0.6, 0.1), hit.z)
		var moved: Array = []
		for p in pts:
			moved.append(spot + ((p as Vector3) - (pts[0] as Vector3)) * 0.3)
		pts = moved
	match kind:
		"snipe":
			var hv: Dictionary = _hordes.get(th["src"], {})
			var from: Vector3 = th["from"]
			if not hv.is_empty() and not (hv["offs"] as Array).is_empty():
				hv["shoot_flash"] = 0.15
				from = _fig_pos(hv, hv["offs"][0]) + Vector3(0, 1.5, 0.3)
			fx.muzzle_big(from, _flash_k(from))
			fx.enemy_shoot(from, spot + Vector3(0, 0.6 if blocked else 0.9, 0), false, "esniper", 0.08)
			fx.burst(spot + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.5), 8, 5.0, 0.14, 0.25, 2.0)
			_sfx("shot_sniper", "shot_rifle", -3.0, 0.7)
		"grenade":
			fx.explosion(spot + Vector3(0, 0.5, 0), 0.9)
			fx.ring(spot + Vector3(0, 0.2, 0), Color(1.0, 0.6, 0.2), 30, 9.0, 0.24)
			Sfx.play("boom", -4.0, 1.3)
			world.shake(0.45)
		"firebomb":
			if blocked:
				fx.burst(spot + Vector3(0, 0.6, 0), Color("ff8a3d"), 16, 5.0, 0.2, 0.45, 1.5)
			else:
				fx.fire(Vector3(spot.x, 0.1, spot.z))
			_sfx("fire", "boom", -5.0, 1.6)
		"barrage", "lt_barrage":
			for p in pts:
				fx.explosion((p as Vector3) + Vector3(0, 0.4, 0), 0.85 if kind == "barrage" else 0.7)
			fx.ring(Vector3(LANE_X[lane], 0.3, ZONE_Z), Color(1.0, 0.45, 0.2), 40, 11.0, 0.28)
			Sfx.play("boom", 0.0, 0.8)
			world.shake(1.0 if kind == "barrage" else 0.7)
	var lost := int(e.get("lost", 0))
	if blocked:
		Sfx.play("blocked")
		if _shield_fx == null or not _shield_fx.is_up():
			fx.burst(Vector3(_squad_x, 1.6, -2.2), Color("9fc6ff"), 16, 6.0, 0.2, 0.4)
	elif lost > 0:
		Sfx.play("hurt", -3.0)
		_add_loss(lost)
		var near: Array = []
		for p in pts:
			near.append(Vector3((p as Vector3).x, 0, (p as Vector3).z))
		_sync_allies(Vector3(_squad_x, 0, 0), near)


## When a telegraphed attack lands, in sim seconds. The interface's land_t is the sim's clock
## at the landing; a small value (below the clock) is read as seconds from now.
func _land_time(e: Dictionary) -> float:
	var t := float(e.get("land_t", e.get("t", 1.0)))
	return t if t >= sim.time - 0.05 else sim.time + t


## Every pending telegraph and its marks go (a revive, the finish, a loss): nothing pending is
## ever shown landing after them.
func _clear_threats() -> void:
	_threats.clear()
	for z in _zones:
		(z["node"] as Node3D).visible = false
		z["fill"] = 0.0
		z["flash"] = 0.0
	for l in _lasers:
		l.visible = false
	fx.clear_enemy()


## True while an attack is telegraphed onto `lane`.
func lane_marked(lane: int) -> bool:
	for t in _threats:
		if int(t["lane"]) == lane:
			return true
	return false


## The countdown shown on `lane`'s mark (0 at the telegraph, 1 at the landing).
func lane_fill(lane: int) -> float:
	return float(_zones[lane]["fill"])


## Sniper laser beams on screen.
func lasers_shown() -> int:
	return _lasers.filter(func(l): return l.visible).size()


func _on_boss_hit(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var hp := int(e["hp"])
	if not hv.is_empty():
		hv["hit_flash"] = 0.75
		var p := _horde_front(hv) + Vector3(randf_range(-0.7, 0.7), CHAR_H * _boss_scale(hv) * randf_range(0.4, 0.75), 0.9)
		fx.burst(p, Color(1.0, 0.93, 0.55), 5, 6.0, 0.12, 0.25, 2.0)
		if hp <= 0:
			var c := _horde_front(hv) + Vector3(0, CHAR_H * _boss_scale(hv) * 0.5, 0)
			fx.explosion(c, 2.2)
			fx.confetti(c + Vector3(0, 2, 0), 70)
			fx.burst(c, Color(1.0, 0.8, 0.3), 30, 9.0, 0.3, 0.7, 5.0)
			if hv.has("bar"):
				# The HP bar shatters into red shards.
				var bp: Vector3 = (hv["bar"] as Node3D).global_position
				fx.burst(bp, Color("e0484f"), 26, 7.0, 0.24, 0.6, 4.0)
				fx.burst(bp, Color(0.06, 0.06, 0.08), 12, 6.0, 0.2, 0.5, 3.0)
				(hv["bar"] as Node3D).visible = false
			fx.ring(c, Color(1.0, 0.85, 0.35), 40, 14.0, 0.3)   # no slow motion (spec v2 §3): a shock ring
	if hp <= 0:
		world.shake(1.2)
		Sfx.play("boom")
		Game.vibrate(200)
		if _boss_music:
			_boss_music = false
			Sfx.play_music("level")


func _on_rank_join(e: Dictionary) -> void:
	var first := bool(e.get("first_time", false))
	rank_joined.emit(String(e["unit"]), first)
	if first:
		fx.ring(Vector3(_squad_x, 0.4, 0.4), GateRowView.GOLD, 32, 8.0)
		_sfx("rank_up", "recruit", -2.0)
		# Spotlight: a gold ring under the newcomers for a second (time stays at 1.0).
		if not demo:
			_spotlight = 1.0
		_spot_kind = String(e["unit"])
		if _spot_ring == null:
			_spot_ring = _ground_ring(GateRowView.GOLD)
		_spot_ring.visible = true


func _throw_clip() -> String:
	return "throw" if Crowd.clips.has("throw") else "punch"


func _on_revive(_e: Dictionary) -> void:
	_state = "play"
	_reset_steer()
	if _touch != null:
		_touch.clear()
	_end_t = 0.0
	_acc = 0.0
	_charging.clear()
	_clear_threats()
	_impacts.clear()    # the squad came back whole: shots from before the loss are moot
	_pending_lost = 0
	var p := Vector3(_squad_x, 0.4, 0.4)
	fx.ring(p, Color("9fe0ff"), 48, 12.0, 0.26)
	fx.burst(p + Vector3(0, 1.2, 0), Color.WHITE, 30, 8.0, 0.25, 0.5, 5.0)
	fx.confetti(p + Vector3(0, 2.0, 0), 30)
	_sfx("rank_up", "recruit", 0.0)
	Sfx.play("shield", -2.0)
	world.shake(0.6)
	Game.vibrate(120)
	_sync_allies(Vector3(_squad_x, 0, 0.5))
	for a in _allies:
		a["flash"] = 1.0


# ---------------------------------------------------------------- telegraphs

func _build_lasers() -> void:
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.albedo_color = Color(1.0, 0.12, 0.1, 0.8)
	var beam := _box_mesh(Vector3(0.09, 0.09, 1.0))
	for i in LASER_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = beam
		mi.material_override = _laser_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_lasers.append(mi)
	# Spec v2.1 §1.2: one lane mark per lane where the squad stands (ZONE_SHADER).
	var sh := Shader.new()
	sh.code = ZONE_SHADER
	var plane := PlaneMesh.new()
	plane.size = ZONE_SIZE
	for lane in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("size", ZONE_SIZE)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(LANE_X[lane], 0.05, ZONE_Z)
		mi.visible = false
		add_child(mi)
		_zones.append({"node": mi, "mat": m, "fill": 0.0, "flash": 0.0})


## Draws the pending telegraphs: per lane the most urgent one's mark (its countdown on the sim's
## clock, so it waits with a paused or held street), a short white flash where one landed, and
## each aiming sniper's laser from his figures to the lane he aims at.
func _update_telegraphs(d: float) -> void:
	# A dead sniper takes no shot; anything the sim never landed goes after a moment.
	for i in range(_threats.size() - 1, -1, -1):
		var th: Dictionary = _threats[i]
		var src: Dictionary = _hordes.get(th["src"], {})
		var gone := src.is_empty() or int(src["h"]["count"]) <= 0
		if sim.time > float(th["land"]) + 0.3 or (th["kind"] == "snipe" and gone):
			_threats.remove_at(i)
	for lane in 3:
		var z: Dictionary = _zones[lane]
		var node: MeshInstance3D = z["node"]
		var mat: ShaderMaterial = z["mat"]
		var best: Dictionary = {}
		for th in _threats:
			if int(th["lane"]) == lane and (best.is_empty() or float(th["land"]) < float(best["land"])):
				best = th
		z["flash"] = maxf(float(z["flash"]) - d, 0.0)
		if best.is_empty():
			z["fill"] = 0.0
			node.visible = float(z["flash"]) > 0.0
			mat.set_shader_parameter("flash", 1.0)
			continue
		var span := maxf(float(best["land"]) - float(best["start"]), 0.05)
		var fill := clampf((sim.time - float(best["start"])) / span, 0.0, 1.0)
		z["fill"] = fill
		node.visible = true
		mat.set_shader_parameter("tint", THREAT_TINT.get(best["kind"], Color(1.0, 0.2, 0.1)))
		mat.set_shader_parameter("fill", fill)
		mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_anim_t * (10.0 + 22.0 * fill)))
		mat.set_shader_parameter("flash", 0.0)
	# Sniper lasers: from up to 3 of his figures to the lane he aims at, faster as the shot nears.
	var used := 0
	var fastest := 0.0
	for th in _threats:
		if th["kind"] != "snipe":
			continue
		var hv: Dictionary = _hordes.get(th["src"], {})
		if hv.is_empty():
			continue
		var to: Vector3 = (th["points"][0] as Vector3) + Vector3(0, 0.9, 0)
		var offs: Array = hv["offs"]
		for j in mini(offs.size(), 3):
			if used >= _lasers.size():
				break
			var from := _fig_pos(hv, offs[j]) + Vector3(0, 1.5, 0.3)
			var dir := to - from
			var length := dir.length()
			if length < 0.1:
				continue
			var mi := _lasers[used]
			mi.transform = Transform3D(Basis.looking_at(dir / length, Vector3.UP).scaled_local(Vector3(1, 1, length)), (from + to) * 0.5)
			mi.visible = true
			used += 1
		var span := maxf(float(th["land"]) - float(th["start"]), 0.05)
		fastest = maxf(fastest, clampf((sim.time - float(th["start"])) / span, 0.0, 1.0))
	for k in range(used, _lasers.size()):
		_lasers[k].visible = false
	if used > 0:
		_laser_mat.albedo_color = Color(1.0, 0.12, 0.1, 0.55 + 0.4 * absf(sin(_anim_t * (14.0 + 30.0 * fastest))))


# ---------------------------------------------------------------- boss bar

## How much bigger than a thug's figure a boss (BOSS_SCALE) or lieutenant (LT_SCALE) is drawn.
func _boss_scale(hv: Dictionary) -> float:
	return LT_SCALE if hv.get("lt", false) else BOSS_SCALE


## Spec v2.1 §1.3: the lieutenant's crowd, the boss's bake recoloured (LT_COLORS). Built once.
func _lieutenant_crowd() -> void:
	if _crowds.has("lieutenant"):
		return
	var c := Crowd.new().setup("boss", int(ENEMY_CAP["boss"]) + 8, "thug")
	c.recolor(LT_COLORS)
	c.name = "Crowd_lieutenant"
	add_child(c)
	_crowds["lieutenant"] = c
	(c.material_override as ShaderMaterial).set_shader_parameter("rim_strength",
		0.3 + (0.2 if district >= 4 else 0.0) + BOSS_RIM)


func _build_boss_bar(hv: Dictionary) -> void:
	var bar := Node3D.new()
	add_child(bar)
	var bg := _quad(Vector2(3.5, 0.56), Color(0.06, 0.06, 0.08, 0.9), 11)
	bar.add_child(bg)
	var fill := _quad(Vector2(3.3, 0.38), Color("e0484f"), 12)
	fill.position.z = 0.01
	bar.add_child(fill)
	var num := GateRowView._label(font, 84, 0.011)
	num.no_depth_test = true
	num.render_priority = 14
	num.outline_render_priority = 13
	num.position = Vector3(0, 0, 0.02)
	bar.add_child(num)
	var crown := Sprite3D.new()
	crown.texture = UiKit.icon_texture("boss_crown")
	crown.pixel_size = 0.95 / 320.0
	crown.shaded = false
	crown.no_depth_test = true
	crown.render_priority = 14
	crown.position = Vector3(-2.1, 0.05, 0.02)
	if hv.get("lt", false):
		crown.modulate = LT_CROWN   # the lieutenant: a silver crown on a smaller bar
	bar.add_child(crown)
	hv["bar"] = bar
	hv["bar_fill"] = fill
	hv["bar_num"] = num
	hv["bar_hp"] = -1
	(hv["label"] as Label3D).visible = false


func _update_boss_bar(hv: Dictionary, d: float) -> void:
	var h: Dictionary = hv["h"]
	var bar: Node3D = hv["bar"]
	var front := _horde_front(hv)
	var k := _boss_scale(hv) * boss_grow(front.z) * crowd_scale((hv["offs"] as Array).size())
	# Always above the scaled model's head, never inside it.
	# Faces the camera and grows with distance, so it reads the same far up the street;
	# its bottom edge stays above the scaled model's head.
	var size := 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		bar.basis = cam.global_transform.basis
		size = clampf(cam.global_position.distance_to(front) / 16.0, 1.0, 3.2)
	# Pulled towards the middle of the road so a boss in an outer lane never clips it.
	bar.position = Vector3(clampf(front.x, -1.3, 1.3), CHAR_H * k + 0.5 + 0.4 * size, front.z)
	var hp := LevelSim.boss_hp(h)
	var mx := maxf(float(h.get("max_hp", h["hp"])), 1.0)
	var fill: MeshInstance3D = hv["bar_fill"]
	if hp != int(hv["bar_hp"]):
		hv["bar_hp"] = hp
		(hv["bar_num"] as Label3D).text = NumFormat.fmt(hp)
		var frac := clampf(hp / mx, 0.0, 1.0)
		fill.scale.x = maxf(frac, 0.001)
		fill.position.x = -1.65 * (1.0 - frac)
	var fl := float(hv.get("hit_flash", 0.0))
	hv["hit_flash"] = maxf(fl - d * 14.0, 0.0)
	(fill.material_override as StandardMaterial3D).albedo_color = Color("e0484f").lerp(Color.WHITE, fl * 0.8)
	bar.scale = Vector3.ONE * size * (LT_BAR if hv.get("lt", false) else 1.0) * (1.0 + 0.08 * fl)


func _quad(size: Vector2, color: Color, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = priority
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- allies

func _desired_allies() -> Dictionary:
	var counts := sim.squad.counts
	var total := sim.squad.total()
	var out := {}
	for k in ALLY_KINDS:
		out[k] = int(counts.get(k, 0))
	if total > ALLY_CAP:
		# Too many to draw: every rank shrinks in proportion (at least one stays visible),
		# constables fill what is left.
		var per := float(total) / ALLY_CAP
		var used := int(out["hero"])
		for k in ALLY_KINDS:
			if k == "hero" or k == "constable":
				continue
			var c := int(counts.get(k, 0))
			out[k] = maxi(int(round(c / per)), 1 if c > 0 else 0)
			used += int(out[k])
		out["constable"] = mini(int(counts.get("constable", 0)), maxi(ALLY_CAP - used, 0))
	return out


## Shown figures follow the squad. Losses take the back of the blob first, or with `near` (where
## incoming shots landed) the figures nearest those points: the ones the tracers hit fall.
func _sync_allies(source: Vector3, near: Array = []) -> void:
	var want := _desired_allies()
	for kind in ALLY_KINDS:
		var have: Array = _allies.filter(func(a): return a["kind"] == kind)
		var diff := int(want[kind]) - have.size()
		if diff > 0:
			for i in diff:
				var jitter := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-0.5, 0.5))
				_allies.append({"kind": kind, "pos": source + jitter, "slot": 0, "phase": randf(), "flash": 0.6,
					"fire_t": randf() * 0.5})
		elif diff < 0 and not near.is_empty():
			have.sort_custom(func(a, b): return _near_d(a["pos"], near) < _near_d(b["pos"], near))
		elif diff < 0:
			# Remove from the back of the blob first.
			have.sort_custom(func(a, b): return (a["pos"] as Vector3).z > (b["pos"] as Vector3).z)
		if diff < 0:
			for i in -diff:
				var a: Dictionary = have[i]
				_allies.erase(a)
				if _death_style == "fall":
					_falling.append({"kind": kind, "pos": a["pos"], "t": randf() * -0.15, "spin": randf_range(-3.0, 3.0)})
				else:
					_dying.append({"kind": kind, "pos": a["pos"], "t": 0.0, "basis": Basis()})
					fx.puff(a["pos"])
		_shown_count[kind] = int(want[kind])
	_assign_slots()


## Ground distance (squared) from `p` to the nearest of `pts`.
static func _near_d(p: Vector3, pts: Array) -> float:
	var best := INF
	for q in pts:
		best = minf(best, Vector2(p.x - (q as Vector3).x, p.z - (q as Vector3).z).length_squared())
	return best


## Slots: hero in front, the heavy hitters next, constables behind. Stable (a figure keeps
## its place relative to its rank-mates), so survivors close ranks instead of swapping.
func _assign_slots() -> void:
	_allies.sort_custom(func(a, b):
		var oa := int(ALLY_ORDER.get(a["kind"], 9))
		var ob := int(ALLY_ORDER.get(b["kind"], 9))
		return oa < ob or (oa == ob and int(a["slot"]) < int(b["slot"])))
	for i in _allies.size():
		_allies[i]["slot"] = i


## An obstacle hit (spatial): kill exactly the figures standing on its footprint, nearest its
## centre first, as many as the sim's loss is worth in shown figures (the shown-figure cap
## makes one figure stand for several troops). Survivors keep their places and close ranks.
func _kill_overlap(e: Dictionary, hole: bool) -> void:
	var lost := int(e["lost"])
	if lost <= 0 or _allies.is_empty():
		return
	var after := sim.squad.total()
	var before := after + lost
	var n := _allies.size()
	var k := clampi(int(round(lost * float(n) / maxf(before, 1.0))), 1, n)
	if sim.squad.hero_alive():
		k = mini(k, n - 1)
	var ob_x: float = LANE_X[int(e["ob"]["lane"])]
	var at_x := float(e.get("x", _squad_x))
	var order: Array = []
	for a in _allies:
		if a["kind"] == "hero" and sim.squad.hero_alive():
			continue
		var sx := at_x + Squad.slot_offset(_place_of(int(a["slot"]), n), n, sim.form_half).x  # where it stands
		order.append([absf(sx - ob_x), int(a["slot"]), a])
	order.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	for i in mini(k, order.size()):
		var a: Dictionary = order[i][2]
		_allies.erase(a)
		if hole:
			_falling.append({"kind": a["kind"], "pos": a["pos"], "t": randf() * -0.15, "spin": randf_range(-3.0, 3.0)})
		else:
			_dying.append({"kind": a["kind"], "pos": a["pos"], "t": 0.0, "basis": Basis()})
			fx.puff(a["pos"])
	# Ranks: the sim loses the lowest ranks first, so relabel survivors to match it (the
	# outermost of a surplus rank takes a missing rank's look), then settle any rounding.
	var want := _desired_allies()
	var have := {}
	for a in _allies:
		have[a["kind"]] = int(have.get(a["kind"], 0)) + 1
	var short: Array = []
	for kind in ALLY_KINDS:
		for j in maxi(int(want[kind]) - int(have.get(kind, 0)), 0):
			short.append(kind)
	if not short.is_empty():
		var spare: Array = _allies.filter(func(a): return a["kind"] != "hero")
		spare.sort_custom(func(x, y): return int(x["slot"]) > int(y["slot"]))
		for a in spare:
			if short.is_empty():
				break
			var kind := String(a["kind"])
			if int(have.get(kind, 0)) > int(want[kind]):
				have[kind] = int(have[kind]) - 1
				a["kind"] = short.pop_back()
				a["flash"] = 0.4
	_sync_allies(Vector3(_squad_x, 0, 0))


## The squad lost: a red ring marks what did it (the gang, the obstacle) so the cause reads.
func _mark_cause(e: Dictionary) -> void:
	var src := int(e.get("source", 0))
	var at = null
	if _hordes.has(src):
		var hv: Dictionary = _hordes[src]
		at = _horde_front(hv) if not (hv["offs"] as Array).is_empty() else Vector3(_squad_x, 0, -1.5)
		hv["hit_flash"] = 1.0
	elif _obstacles.has(src):
		at = _obstacle_pos(_obstacles[src]["ob"])
	elif String(e.get("cause", "")) == "molotov":
		at = Vector3(LANE_X[sim.lane], 0, 0)
	if at == null:
		return
	if _danger_ring == null:
		_danger_ring = _ground_ring(Color("ff3b3b"))
	_danger_at = at
	_danger_t = 2.5
	fx.ring((at as Vector3) + Vector3(0, 0.4, 0), Color("ff3b3b"), 36, 7.0, 0.24)


## A flat glowing ring on the road (new-rank spotlight, death cause).
func _ground_ring(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.15
	tm.rings = 32
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.scale = Vector3(1, 0.15, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Figure scale for a crowd of n shown figures: full size up to 20, down to 78% at 80+,
## so a huge army reads as a dense mob instead of a pile-up.
## Owner: troops a bit smaller than the hero (0.85), shrinking to 0.68 in big crowds.
static func crowd_scale(n: int) -> float:
	return Squad.crowd_scale(n)


func _slot_pos(slot: int, n: int) -> Vector3:
	var lift := -7.0 if demo else 0.0  # lobby: squad further up the street, above the menu
	# The same formation the sim hits obstacles with (Squad.slot_offset), around _squad_x.
	var o := Squad.slot_offset(_place_of(slot, n), n, sim.form_half if sim else 0.0)
	# Spec v2 §4 smudge: a big squad packs its rows so tight that only caps show (a dark blob).
	# Rows open up in depth around the formation's centre; depth is the view's alone (the sim
	# hits obstacles by x only), so the arithmetic is untouched.
	if slot > 0:
		var zc := 1.1 + 0.18 * crowd_scale(n) * sqrt(maxf(n, 1))  # Squad.slot_offset's centre
		o.y = zc + (o.y - zc) * depth_spread(n)
	# A hair of height per place keeps overlapping caps and hats from z-fighting.
	return Vector3(_squad_x + o.x, 0.012 * (slot % 4), o.y + lift)


## Spec v2 §5: a boss far up the street is drawn bigger (up to BOSS_FAR_SCALE at 70 m), easing
## to his true size by 30 m, so he is never lost behind his escorts while he walks in.
## True when a label at `at` would sit on the boss's body on screen (its feet to its head,
## about its width either side, with a margin for the label itself).
func _covers_boss(cam: Camera3D, at: Vector3, bv: Dictionary) -> bool:
	var feet := _horde_front(bv)
	var k := _boss_scale(bv) * boss_grow(feet.z) * crowd_scale((bv["offs"] as Array).size())
	var f2 := cam.unproject_position(feet)
	var h2 := cam.unproject_position(feet + Vector3(0, CHAR_H * k, 0))
	var w := absf(cam.unproject_position(feet + Vector3(CHAR_H * k * 0.3, 0, 0)).x - f2.x)
	var p := cam.unproject_position(at)
	return p.y > h2.y - 40.0 and p.y < f2.y + 40.0 and absf(p.x - f2.x) < w + 70.0


static func boss_grow(z: float) -> float:
	return lerpf(1.0, BOSS_FAR_SCALE, clampf((-z - 30.0) / 40.0, 0.0, 1.0))


## Followers' ink outline width for a squad of n shown figures: full ink while the squad is
## small, thinner once heads overlap (the hero keeps full ink and stands out).
static func ink_width(n: int) -> float:
	return lerpf(INK_W, INK_W_PACKED, clampf((n - 30) / 40.0, 0.0, 1.0))


## How much a squad of n shown figures opens up in depth (1 = the sim's rows).
static func depth_spread(n: int) -> float:
	return lerpf(1.0, DEPTH_SPREAD, clampf((n - 30) / 40.0, 0.0, 1.0))


## Spec v2 §4 smudge fix. The formation's places are the sim's (Squad.slot_offset); this only
## decides who stands where. Slot 0 (the hero) stays in front; the ranks after him (snipers,
## commandos, SWAT, inspectors, sergeants, by ALLY_ORDER) take the rear places nearest the
## camera, seen whole instead of as a clump of purple and brown hats in the middle of the
## blob; constables fill the rest, rear to front.
func _place_of(slot: int, n: int) -> int:
	if slot <= 0 or n <= 2:
		return slot
	if not _places.has(n):
		var half := sim.form_half if sim else 0.0
		var idx: Array = range(1, n)
		idx.sort_custom(func(a, b):
			var za := Squad.slot_offset(a, n, half).y
			var zb := Squad.slot_offset(b, n, half).y
			return za > zb or (za == zb and a < b))
		_places[n] = [0] + idx
	var p: Array = _places[n]
	return int(p[slot]) if slot < p.size() else slot


# ---------------------------------------------------------------- visuals

func _update_visuals(d: float) -> void:
	var lane_target: float = _steer_x if _touching else LANE_X[sim.lane]
	var x_before := _squad_x
	if demo:
		_squad_x = move_toward(_squad_x, lane_target, 1.0)
	else:
		_squad_x = lerpf(_squad_x, lane_target, 1.0 - exp(-d * STEER_EASE))
	var shift := _squad_x - x_before
	var target_pos = _target_point()
	_anim_t += d
	_hero_knife_t += d
	_rf_sfx_t = maxf(_rf_sfx_t - d, 0.0)
	_hit_sfx_t = maxf(_hit_sfx_t - d, 0.0)
	fx.track_x = _squad_x
	if not _impacts.is_empty():
		_land_impacts()
	_tick_minus(d)
	if _bomb_throw_t >= 0.0:
		_bomb_throw_t += d
		if _state != "play":
			_bomb_throw_t = -1.0
			_bomb_launch = {}
			fx.held_bomb_on = false
		elif _bomb_throw_t > Crowd.clip_length(_throw_clip()) / _bomb_speed and _bomb_launch.is_empty():
			_bomb_throw_t = -1.0
	_tick_bomb_mark(d)
	var moving := demo or _state == "play" or _state == "done"

	for k in _crowds:
		(_crowds[k] as Crowd).begin()

	# Allies
	var n := _allies.size()
	var troop_k := crowd_scale(_allies.size())
	var ink := ink_width(n)
	for k in ALLY_KINDS:
		if k != "hero" and _crowds.has(k):
			(_crowds[k] as Crowd).set_ink_width(ink)
	for a in _allies:
		var target := _slot_pos(int(a["slot"]), n)
		var pos: Vector3 = a["pos"]
		# Steering carries the whole formation at once; gaps close smoothly (survivors ease
		# into the free slots instead of snapping).
		pos.x += shift
		pos = pos.move_toward(target, d * (14.0 if pos.distance_to(target) > 1.8 else 3.0 + 6.0 * pos.distance_to(target)))
		a["pos"] = pos
		a["flash"] = maxf(float(a["flash"]) - d * 3.0, 0.0)
		var aim := 0.0
		if not demo and _state == "play":
			aim = 1.0
			a["fire_t"] = float(a["fire_t"]) - d
			# The hero's hands are busy with the bomb: no knife throws drawn until it is gone.
			if float(a["fire_t"]) <= 0.0 and not (a["kind"] == "hero" and _bomb_throw_t >= 0.0):
				var aim_at: Vector3 = target_pos if target_pos != null else Vector3(pos.x, 1.1, pos.z - sim.fire_range)
				_fire(a, aim_at)
		var basis := Basis()
		if target_pos != null and not demo:
			var dir: Vector3 = (target_pos as Vector3) - pos
			dir.y = 0
			if dir.length() > 0.5:
				basis = Basis.looking_at(dir.normalized(), Vector3.UP)
		if a["kind"] == "hero" and _flick_t < FLICK_S and _state == "play":
			# The hand flick on a tap: a quick twist into the throw and back.
			var fk := sin(PI * _flick_t / FLICK_S)
			basis = basis * Basis(Vector3.UP, 0.2 * fk) * Basis(Vector3.RIGHT, -0.08 * fk)
		var ph := float(a["phase"]) * 3.0
		if a["kind"] == "hero" and _state == "finale":
			if finale != null and is_instance_valid(finale) and finale.camera_in_head():
				continue  # first person: the view model is his hands, his body is behind the eye
			basis = Basis()
			if _hero_throw_t >= 0.0:
				_hero_throw_t += d
				if _hero_throw_t > 0.75:
					_hero_throw_t = -1.0
			var throw := _throw_clip()
			var clip := throw if _hero_throw_t >= 0.0 else "idle"
			(_crowds["hero"] as Crowd).push(Transform3D(basis, pos), clip, maxf(_hero_throw_t, 0.0) if clip == throw else _anim_t)
		elif a["kind"] == "hero" and _bomb_throw_t >= 0.0:
			# Spec v2 §12.5: one slow, full overhand throw for the bomb (any weapon he holds),
			# the bomb in his hand until the release.
			var throw := _throw_clip()
			var clen := Crowd.clip_length(throw)
			var ct := minf(_bomb_throw_t * _bomb_speed, clen)
			(_crowds["hero"] as Crowd).push(Transform3D(basis, pos), throw, ct, float(a["flash"]))
			if not _bomb_launch.is_empty():
				var hand := pos + basis * hand_offset(ct / clen)
				if _bomb_throw_t < float(_bomb_launch["windup"]):
					fx.held_bomb = hand
					fx.held_bomb_on = true
				else:
					_launch_bomb(hand)
		elif aim > 0.0 and a["kind"] == "hero" and sim.squad.hero_weapon == "":
			# Knives: a real overhand throw per knife, the clip sped up to fit the throw rate.
			var throw := _throw_clip()
			var per := 1.0 / maxf(float(sim.stats["hero"]["rate"]) * hero_mult(), 0.5)
			var speed := maxf(Crowd.clip_length(throw) / per, 1.0)
			(_crowds["hero"] as Crowd).push(Transform3D(basis, pos), throw, minf(_hero_knife_t * speed, Crowd.clip_length(throw)), float(a["flash"]))
		elif aim > 0.0:
			(_crowds[a["kind"]] as Crowd).push(Transform3D(basis.scaled(Vector3.ONE * (1.0 if a["kind"] == "hero" else troop_k)), pos), "shoot", _anim_t + ph, float(a["flash"]))
		elif moving:
			(_crowds[a["kind"]] as Crowd).push(Transform3D(basis.scaled(Vector3.ONE * (1.0 if a["kind"] == "hero" else troop_k)), pos), "run", (_anim_t + ph) * RUN_SPEED, float(a["flash"]))
		else:
			(_crowds[a["kind"]] as Crowd).push(Transform3D(basis.scaled(Vector3.ONE * (1.0 if a["kind"] == "hero" else troop_k)), pos), "idle", _anim_t + ph, float(a["flash"]))

	# Enemies
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var boss_near := false
	for id in _hordes:
		var bh: Dictionary = _hordes[id]["h"]
		if _hordes[id].has("bar") and int(bh["count"]) > 0 and float(bh["z"]) > BOSS_BEAT_Z:
			boss_near = true
	if not demo:
		# Camera beat while a boss walks in; the camera also follows the squad sideways.
		world.beat = move_toward(world.beat, 1.0 if boss_near and _state == "play" else 0.0, d * 1.2)
		world.follow_x = _squad_x * CAM_FOLLOW if _state == "play" or _state == "done" else lerpf(world.follow_x, 0.0, minf(d * 4.0, 1.0))
	for id in _hordes:
		var hv: Dictionary = _hordes[id]
		var h: Dictionary = hv["h"]
		var want := int(ceil(int(h["count"]) / float(hv["per"])))
		var offs: Array = hv["offs"]
		var esc := _boss_scale(hv) * boss_grow(float(h["z"])) if hv["bossy"] else ENEMY_SCALE
		if hv.get("leader", false):
			esc = ENEMY_SCALE * LEADER_SCALE
		while offs.size() > want:
			var o: Vector3 = offs.pop_front()
			var p := _fig_pos(hv, o)
			_dying.append({"kind": hv["kind"], "pos": p, "t": 0.0,
				"basis": Basis(Vector3.UP, PI).scaled(Vector3.ONE * esc * crowd_scale(offs.size() + 1))})
			fx.puff(p)
		var crowd: Crowd = _crowds[hv["kind"]]
		var clip := "shoot" if h["stopped"] else ("idle" if h.has("cage") else "run")
		var speed := 1.0 if h["stopped"] else RUN_SPEED * clampf(float(h["vrel"]) / 10.0, 0.8, 1.6)
		if hv["bossy"] and not h["melee"]:
			# A boss walks in at his real pace during the standoff: a slow, heavy stride whose
			# footfalls thump the camera and kick up dust.
			speed = clampf(float(h["vrel"]) / 3.0, 0.4, RUN_SPEED)
			if _state == "play" and sim.S < 0.5 and float(h["z"]) > -sim.boss_halt:
				_boss_step += d * speed * 2.0 / Crowd.clip_length("run")
				if _boss_step >= 1.0:
					_boss_step -= 1.0
					var foot := _fig_pos(hv, offs[0]) if not offs.is_empty() else Vector3(0, 0, float(h["z"]))
					fx.burst(foot + Vector3(0, 0.1, 0), Color(0.7, 0.65, 0.58), 8, 2.5, 0.35, 0.5, 0.8, 2.0)
					world.shake(0.12)
		var flash := float(hv["shoot_flash"])
		hv["shoot_flash"] = maxf(flash - d, 0.0)
		flash = maxf(flash * 2.0, float(hv["hit_flash"]))
		var face := Basis(Vector3.UP, PI).scaled(Vector3.ONE * crowd_scale(offs.size()) * esc)
		for o in offs:
			crowd.push(Transform3D(face, _fig_pos(hv, o)), clip, (_anim_t + o.y * 3.0) * speed, flash)
		if hv.has("bar"):
			_update_boss_bar(hv, d)
			continue
		var lab: Label3D = hv["label"]
		var depth := (offs.back().z if not offs.is_empty() else 0.0) as float
		var lz := float(h["z"]) - depth * 0.5
		# Grows with distance (like the boss bar) so a far gang's count still reads.
		var ls := 1.0
		if cam:
			ls = clampf(cam.global_position.distance_to(Vector3(0, 0, lz)) / 18.0, 1.0, 2.2)
		lab.scale = Vector3.ONE * ls
		var ly := (4.6 if hv["kind"] == "brute" else 3.6) * ENEMY_SCALE * 0.85 + 0.3 * (ls - 1.0)
		# Escorts walking with a boss: their count sits above the boss's bar, never on his chest.
		# A gang walking ahead of a boss keeps its count low, just over its own heads, so the
		# boss behind it stays in sight (spec v2 §5).
		for bid in _hordes:
			var bv: Dictionary = _hordes[bid]
			if not bv.has("bar") or not (bv["bar"] as Node3D).visible:
				continue
			if absf(float(bv["h"]["z"]) - lz) < 7.0:
				var bar_top: float = (bv["bar"] as Node3D).position.y + 0.4 * (bv["bar"] as Node3D).scale.y
				ly = maxf(ly, bar_top + 0.7 * ls)
			elif float(bv["h"]["z"]) < lz and int(bv["h"]["count"]) > 0:
				ly = minf(ly, CHAR_H * ENEMY_SCALE * crowd_scale(offs.size()) + 0.45 * ls)
				# Seen from above and behind the squad, that can still land on the boss's
				# body on screen: then the count goes above the boss's bar instead.
				if cam and _covers_boss(cam, Vector3(0, ly, lz), bv):
					var bar: Node3D = bv["bar"]
					ly = bar.position.y + 0.4 * bar.scale.y + 0.7 * ls
					lz = bar.position.z
		lab.position = Vector3(0, ly, lz)
		var shown := LevelSim.boss_hp(h) if hv.get("leader", false) else int(h["count"])
		if shown != int(hv["shown"]):
			hv["shown"] = shown
			lab.text = NumFormat.fmt(shown)
		# Closing in while the squad's fire goes elsewhere (a red gate, an obstacle): the count
		# pulses so the threat behind the gate is visible before it arrives.
		var ignored: bool = _state == "play" and not is_same(sim.target_ref, h) and LevelSim.front_z(h) > -18.0 and not h["melee"]
		if ignored:
			var p := 0.5 + 0.5 * sin(_anim_t * 16.0)
			lab.modulate = Color("ff6b6b").lerp(Color(1, 1, 1), p) if int(h["armour"]) == 0 else Color("b8c7d9").lerp(Color("ff3b3b"), p)
			lab.scale = Vector3.ONE * ls * (1.0 + 0.15 * p)
		else:
			lab.modulate = Color("ff6b6b") if int(h["armour"]) == 0 else Color("b8c7d9")

	# People waiting at troop pickups, facing the squad.
	for id in _rows:
		var rv: GateRowView = _rows[id]
		var rz := float(rv.row["z"])
		for g in rv.row["gates"]:
			if not GateRowView.is_troops(g) or GateRowView.is_blocked(g):
				continue
			var cnt := mini(GateRowView.troop_count(g), 12)
			var cx: float = LANE_X[int(g["lane"])]
			var crowd: Crowd = _crowds[GateRowView.troop_kind(g)]
			for j in cnt:
				var a := j * 2.39996
				var r := 0.42 * sqrt(j + 0.3) if cnt > 1 else 0.0
				var p := Vector3(cx + cos(a) * r * 1.2, 0, rz + sin(a) * r * 0.8)
				crowd.push(Transform3D(Basis(Vector3.UP, PI), p), "idle", _anim_t + j * 0.37)

	# Charging (contact) and dying figures
	var i := 0
	while i < _charging.size():
		var c: Dictionary = _charging[i]
		var goal := Vector3(_squad_x + float(c.get("dx", 0.0)), 0, -0.6 if c["shielded"] else 0.2)
		var p: Vector3 = (c["pos"] as Vector3).move_toward(goal, d * 12.0)
		c["pos"] = p
		c["t"] = float(c.get("t", 0.0)) + d
		var bounced: bool = c["shielded"] and _shield_fx.is_up()
		if (_shield_fx.touches(p + Vector3(0, 0.9, 0), 0.3) if bounced else p.distance_to(goal) < (2.6 if c["shielded"] else 0.8)) or float(c["t"]) > 0.9:
			if bounced:
				_shield_hit(p + Vector3(0, 0.9, 0), Vector3(_squad_x, 0.9, 0.6))
			fx.puff(p)
			_dying.append({"kind": c["kind"], "pos": p, "t": 0.0, "basis": Basis(Vector3.UP, PI).scaled(Vector3.ONE * ENEMY_SCALE)})
			_charging.remove_at(i)
			continue
		(_crowds[c["kind"]] as Crowd).push(Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * ENEMY_SCALE), p), "punch", float(c["t"]) * 1.4)
		i += 1
	# Dead bodies: topple backwards flat onto the road, then ride the street past the squad
	# and off the bottom of the screen.
	while _dying.size() > CORPSE_CAP:
		_dying.pop_front()
	i = 0
	while i < _dying.size():
		var dd: Dictionary = _dying[i]
		dd["t"] = float(dd["t"]) + d
		var t := float(dd["t"])
		var p: Vector3 = dd["pos"]
		p.z += sim.S * d * (1.0 if _state == "play" or _state == "done" else 0.0)
		dd["pos"] = p
		if t > BODY_TIME + 0.5 or p.z > 4.0:
			_dying.remove_at(i)
			continue
		if not dd.has("spin"):
			dd["spin"] = randf_range(-0.5, 0.5)
		var k := clampf(t / FALL_TIME, 0.0, 1.0)
		var fall := (k * k) * PI * 0.5                        # accelerate like a falling body
		var bounce := sin(clampf((t - FALL_TIME) / 0.25, 0.0, 1.0) * PI) * 0.12
		var basis: Basis = (dd["basis"] as Basis) * Basis(Vector3.UP, float(dd["spin"])) * Basis(Vector3.RIGHT, -(fall - bounce))
		var flash := maxf(0.0, 1.0 - t * 6.0)
		if t > BODY_TIME:
			flash = -clampf((t - BODY_TIME) / 0.5, 0.0, 1.0)  # dissolve away
		(_crowds[dd["kind"]] as Crowd).push(Transform3D(basis, p + Vector3(0, 0.05, 0)), "hit", minf(t, 0.15), flash)
		i += 1
	# Troops a pothole took: hop to the hole, then drop in, shrinking and tumbling.
	i = 0
	var road := sim.S * d * (1.0 if _state == "play" or _state == "done" else 0.0)
	while i < _falling.size():
		var fd: Dictionary = _falling[i]
		fd["t"] = float(fd["t"]) + d
		var t := float(fd["t"])
		var p: Vector3 = fd["pos"]
		p.z += road
		if t > 0.0:
			p.x = move_toward(p.x, _death_at.x, d * 6.0)
			p.y = -t * t * 9.0
		fd["pos"] = p
		if t > 0.65:
			_falling.remove_at(i)
			continue
		var s := clampf(1.0 - maxf(t, 0.0) * 1.2, 0.15, 1.0)
		var basis := Basis(Vector3.RIGHT, maxf(t, 0.0) * float(fd["spin"])).scaled(Vector3.ONE * s)
		(_crowds[fd["kind"]] as Crowd).push(Transform3D(basis, p), "hit", 0.1, 0.0)
		i += 1

	_draw_cages(d)
	_update_heat_ring(d)
	if _warm_left > 0:
		_warm_frame()
	for k in _crowds:
		(_crowds[k] as Crowd).finish()
	_update_telegraphs(d)

	# Gates ride the road.
	for id in _rows:
		var v: GateRowView = _rows[id]
		v.position.z = float(v.row["z"])
	if _finish and _finish_live:
		_finish.position.z = -(sim.finish_at - sim.traveled)
	for oid in _obstacles:
		_update_obstacle(_obstacles[oid], d)
	i = 0
	while i < _riding.size():
		var rn: Node3D = _riding[i]
		rn.position.z += road
		if rn.position.z > 12.0 or road == 0.0 and _state != "play":
			rn.queue_free()
			_riding.remove_at(i)
			continue
		i += 1

	# New-rank spotlight ring under the newcomers; death-cause ring.
	if _spot_ring and _spot_ring.visible:
		var c := Vector3.ZERO
		var cnt := 0
		for a in _allies:
			if a["kind"] == _spot_kind:
				c += a["pos"]
				cnt += 1
		if cnt == 0 or _spotlight <= 0.0:
			_spot_ring.visible = false
		else:
			c /= cnt
			var pulse := 1.0 + 0.12 * sin(_anim_t * 18.0)
			_spot_ring.position = Vector3(c.x, 0.06, c.z)
			_spot_ring.scale = Vector3(pulse, 0.15, pulse)
	if _danger_ring:
		_danger_t = maxf(_danger_t - d, 0.0)
		_danger_ring.visible = _danger_t > 0.0
		if _danger_ring.visible:
			var pulse2 := 1.4 + 0.25 * sin(_anim_t * 14.0)
			_danger_ring.position = _danger_at + Vector3(0, 0.06, 0)
			_danger_ring.scale = Vector3(pulse2, 0.15, pulse2)

	# Squad label and shield.
	_label_pop = maxf(_label_pop - d * 4.0, 0.0)
	_squad_label.text = NumFormat.fmt(shown_total())
	_squad_label.position = Vector3(_squad_x, 3.9, -0.8)
	if _key_light:
		_key_light.position = Vector3(_squad_x, 4.5, 2.5)
	_squad_label.scale = Vector3.ONE * (1.0 + 0.5 * _label_pop)
	_shield_fx.update(d, sim.shield_t if _state == "play" and sim.state == "run" else 0.0, _allies,
		CHAR_H, CHAR_H * troop_k)


func _fig_pos(hv: Dictionary, o: Vector3) -> Vector3:
	var h: Dictionary = hv["h"]
	var z := float(h["z"]) - o.z
	var k := clampf((z + 16.0) / 14.0, 0.0, 1.0)
	var x := lerpf(o.x, _squad_x + o.x * 0.45, k)
	return Vector3(x, 0, z)


func _horde_front(hv: Dictionary) -> Vector3:
	var offs: Array = hv["offs"]
	if offs.is_empty():
		return Vector3(0, 0, float(hv["h"]["z"]))
	return _fig_pos(hv, offs[0])


func _target_point():
	if _state != "play":
		return null
	match sim.target_kind:
		"horde":
			var hv: Dictionary = _hordes.get(sim.target_ref["id"], {})
			if hv.is_empty():
				return null
			var offs: Array = hv["offs"]
			if offs.is_empty():
				return null
			return _fig_pos(hv, offs[randi() % mini(offs.size(), 9)]) + Vector3(0, 1.0, 0)
		"gate":
			return Vector3(LANE_X[int(sim.target_ref["lane"])], 1.9, float(sim.target_ref.get("z", -10.0)))
		"obstacle":
			return _obstacle_pos(sim.target_ref) + Vector3(0, 0.8, 0)
	return null


func _fire(a: Dictionary, target: Vector3) -> void:
	var kind := String(a["kind"])
	var unit: Dictionary = sim.stats[kind]
	var rate := float(unit["rate"])
	if kind == "hero":
		rate *= hero_mult()   # tap heat: idle hero throws slower, a tapping hero at full rate
	else:
		# A thinned-out rank fires faster so the screen still shows its real firepower.
		var per := maxf(float(sim.squad.count(kind)) / maxf(float(_shown_count.get(kind, 1)), 1.0), 1.0)
		rate *= minf(per, 2.5)
	a["fire_t"] = 1.0 / rate * randf_range(0.85, 1.15)
	var from: Vector3 = (a["pos"] as Vector3) + Vector3(0, 1.15, -0.4)
	var spread := Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0)
	var proj := String(unit["proj"])
	# Visual only (the sim's damage is exact): past ~36 shooters, draw one tracer in k so a
	# big army does not wall off the street; the hero's knives and sniper rounds always show.
	var keep := clampf(36.0 / maxf(float(_allies.size()), 1.0), 0.3, 1.0)
	if kind != "hero" and proj != "sniper_round" and randf() > keep:
		var s0: Array = ALLY_SFX.get(kind, ["shot", "shot", -11.0])
		_sfx(String(s0[0]), String(s0[1]), float(s0[2]), 1.1 if kind == "constable" else 1.0)
		return
	match proj:
		"knife":
			fx.shoot(proj, from, target + spread, 34.0)
		"pellet":
			# Shotgun: a short fan of pellets.
			for i in 3:
				fx.shoot(proj, from, target + spread + Vector3(randf_range(-0.9, 0.9), randf_range(-0.4, 0.4), 0), 60.0)
		"sniper_round":
			fx.shoot(proj, from + Vector3(0, 0.2, 0), target, 150.0)
		"rocket":
			fx.shoot(proj, from + Vector3(0, 0.3, 0), target + spread, 30.0)
		_:
			fx.shoot(proj, from, target + spread, 55.0)
	if kind == "hero":
		_hero_knife_t = 0.0
		Sfx.play("knife", -6.0)
		if sim.squad.hero_weapon != "":
			fx.shoot("bullet", from + Vector3(0.2, 0, 0), target + spread * 0.5, 55.0)
			Sfx.play("shot", -8.0)
	else:
		var s: Array = ALLY_SFX.get(kind, ["shot", "shot", -11.0])
		_sfx(String(s[0]), String(s[1]), float(s[2]), 1.1 if kind == "constable" else 1.0)


func _free_horde(id: int) -> void:
	var hv: Dictionary = _hordes.get(id, {})
	if hv.is_empty():
		return
	(hv["label"] as Node).queue_free()
	(hv["sub"] as Node).queue_free()
	if hv.has("bar"):
		(hv["bar"] as Node).queue_free()
	_hordes.erase(id)


func _physics_process(_delta: float) -> void:
	# Hordes that the sim removed (cleared or contact) and have no figures left.
	for id in _hordes.keys():
		var hv: Dictionary = _hordes[id]
		if int(hv["h"]["count"]) <= 0 and (hv["offs"] as Array).is_empty():
			_free_horde(id)


# ---------------------------------------------------------------- obstacles

func _obstacle_pos(ob: Dictionary) -> Vector3:
	return Vector3(LANE_X[int(ob["lane"])], 0, float(ob["z"]))


func _spawn_obstacle(ob: Dictionary) -> void:
	var n := Node3D.new()
	var kind := String(ob.get("kind", "barricade"))
	var od := {"ob": ob, "node": n, "label": null, "cracks": [], "hp_shown": -1, "chip_t": 0.0}
	match kind:
		"pothole":
			_build_pothole(n, od)
		"barrel":
			var bm := GateRowView.barrel_model()
			n.add_child(bm["root"])
			od["fuse"] = bm["fuse"]
			od["body"] = bm["body"]
			od["kick"] = 0.0
		"car":
			var car := World.model(["cars/sedan.glb", "cars/taxi.glb", "cars/van.glb", "cars/suv.glb"][int(ob["id"]) % 4], 1.45)
			car.rotation.y = PI * (0.5 if int(ob["id"]) % 2 == 0 else -0.5)
			n.add_child(car)
		_:
			_build_barricade(n, od)
	# Anything you can shoot shows the hits it still takes.
	if kind != "pothole" and float(ob.get("hp_max", 0.0)) > 0.0:
		var lab := GateRowView._label(font, 100, 0.011)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position.y = {"car": 2.6, "barrel": 2.1}.get(kind, 2.3)
		lab.modulate = Color("ffe08a")
		n.add_child(lab)
		od["label"] = lab
	if kind != "pothole":
		# Its cost before you reach it: the most troops it takes if you hit it (red, on the
		# near lip; the yellow number above is the hits it still takes).
		var tag := GateRowView._label(font, 100, 0.011)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color("ff5a5f")
		tag.position = Vector3(0, 0.5, 0.9 if kind == "barrel" else 1.5)
		tag.text = ("-%d%%" % int(ob["dmg_pct"])) if ob.has("dmg_pct") else ("-" + NumFormat.fmt(int(ob.get("dmg", 0))))
		n.add_child(tag)
		od["tag"] = tag
	add_child(n)
	n.position = _obstacle_pos(ob)
	_obstacles[int(ob["id"])] = od
	_update_obstacle(od, 0.0)


## Pothole: a black hole with a broken orange rim and loose chunks, plus the troops it costs.
func _build_pothole(n: Node3D, od: Dictionary) -> void:
	var ob: Dictionary = od["ob"]
	var rim := MeshInstance3D.new()
	rim.mesh = _cyl_mesh("pothole_rim", 1.3)
	rim.material_override = _mat(Color("e8742a"))
	rim.position.y = 0.025
	n.add_child(rim)
	var hole := MeshInstance3D.new()
	hole.mesh = _cyl_mesh("pothole_hole", 1.05)
	hole.material_override = _mat(Color("120d0b"), true)
	hole.position.y = 0.04
	n.add_child(hole)
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		var chunk := _part(Vector3(0.32, 0.16, 0.26), Color("5b544e"), Vector3(cos(a) * 1.35, 0.08, sin(a) * 1.1))
		chunk.rotation.y = a
		n.add_child(chunk)
	var lab := GateRowView._label(font, 110, 0.011)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color("ff5a5f")
	# On the hole's near lip, in front of any gate sign sharing the lane.
	lab.position = Vector3(0, 0.55, 1.5)
	lab.text = ("-%d%%" % int(ob["fall_pct"])) if ob.has("fall_pct") else ("-" + NumFormat.fmt(int(ob.get("fall", 0))))
	n.add_child(lab)
	od["tag"] = lab


## Barricade: two posts, wooden planks and a red/white hazard board; cracks show damage.
func _build_barricade(n: Node3D, od: Dictionary) -> void:
	for x in [-1.2, 1.2]:
		n.add_child(_part(Vector3(0.24, 1.5, 0.24), Color("3a2d22"), Vector3(x, 0.75, 0)))
	var woods := [Color("9a6b3c"), Color("8a5a2e"), Color("a8783f")]
	for j in 3:
		n.add_child(_part(Vector3(2.6, 0.28, 0.14), woods[j], Vector3(0, 0.35 + j * 0.34, 0.12)))
	for s in 5:
		n.add_child(_part(Vector3(0.52, 0.3, 0.16), Color("d63a3a") if s % 2 == 0 else Color("f2f2f2"),
			Vector3(-1.04 + s * 0.52, 1.36, 0.12)))
	# Two crack stages (dark zig-zags on the front), shown as the hp drops.
	for stage in 2:
		var cracks := Node3D.new()
		cracks.visible = false
		for c in 3:
			var x := randf_range(-1.0, 1.0)
			var y := randf_range(0.4, 1.3)
			for seg in 2:
				var piece := _part(Vector3(0.05, 0.36, 0.02), Color("1d1410"), Vector3(x + seg * 0.1, y - seg * 0.3, 0.21))
				piece.rotation.z = 0.6 if seg == 0 else -0.5
				cracks.add_child(piece)
		n.add_child(cracks)
		od["cracks"].append(cracks)


func _update_obstacle(od: Dictionary, d: float) -> void:
	var ob: Dictionary = od["ob"]
	var on: Node3D = od["node"]
	on.position = _obstacle_pos(ob)
	var armed := bool(ob.get("armed", false))
	if armed:
		on.scale = Vector3.ONE * (1.0 + 0.12 * absf(sin(_anim_t * 16.0)))
		if od.has("tag"):
			(od["tag"] as Node3D).visible = false  # an armed barrel no longer hurts the squad
	if od.has("fuse"):
		_update_barrel(od, on, armed, d)
	od["chip_t"] = float(od["chip_t"]) - d
	var lab = od["label"]
	if lab == null:
		return
	var hp := int(ceil(float(ob["hp"])))
	if hp == int(od["hp_shown"]) and not armed:
		return
	if int(od["hp_shown"]) > hp and float(od["chip_t"]) <= 0.0:
		# Chips fly off as it takes hits (throttled).
		od["chip_t"] = 0.12
		var wood := String(ob.get("kind", "")) == "barricade"
		fx.burst(on.position + Vector3(randf_range(-0.8, 0.8), 1.0, 0.4), Color("b88a52") if wood else Color(0.85, 0.85, 0.8), 3, 4.0, 0.14, 0.3)
	od["hp_shown"] = hp
	(lab as Label3D).text = NumFormat.fmt(hp)
	(lab as Label3D).visible = hp > 0 and not armed
	var frac := float(ob["hp"]) / maxf(float(ob.get("hp_max", 1.0)), 1.0)
	var cracks: Array = od["cracks"]
	for ci in cracks.size():
		(cracks[ci] as Node3D).visible = frac < (0.67 if ci == 0 else 0.34)


## Spec v2 §5 barrel states: the fuse ring fills with the shots it takes; armed, ring and drum
## blink. An armed barrel is no longer solid (the sim lets the squad through), so one the squad
## walks into is kicked rolling to the kerb instead of the troops passing through it.
func _update_barrel(od: Dictionary, on: Node3D, armed: bool, d: float) -> void:
	var ob: Dictionary = od["ob"]
	var fm: ShaderMaterial = od["fuse"]
	var frac := 1.0 if armed else 1.0 - float(ob["hp"]) / maxf(float(ob.get("hp_max", 1.0)), 1.0)
	fm.set_shader_parameter("fill", frac)
	var bl := (0.5 + 0.5 * sin(_anim_t * 18.0)) if armed else 0.0
	fm.set_shader_parameter("blink", bl)
	fm.set_shader_parameter("color", Color("ff3b2a") if armed else GateRowView.FUSE_COLOR)
	(od["body"] as StandardMaterial3D).albedo_color = GateRowView.BARREL_RED.lerp(Color("ffd23f"), bl * 0.55)
	var kick := float(od["kick"])
	var lane_x: float = LANE_X[int(ob["lane"])]
	if armed and kick == 0.0 and absf(lane_x - _squad_x) < 1.9 and on.position.z > -1.2 and on.position.z < 1.5:
		kick = 0.01 * (1.0 if lane_x >= _squad_x else -1.0)
		Sfx.play("clink", -4.0, 0.7)
	if kick != 0.0:
		kick = signf(kick) * minf(absf(kick) + d * 7.0, 4.0)
		od["kick"] = kick
		on.position.x = clampf(lane_x + kick, -World.ROAD_HALF + 0.5, World.ROAD_HALF - 0.5)
		(on.get_child(0) as Node3D).rotation = Vector3(0, 0, -kick * 1.2)


## `ride`: leave the node on the road (it scrolls away under the squad) instead of vanishing.
func _free_obstacle(id: int, ride := false) -> void:
	var od: Dictionary = _obstacles.get(id, {})
	if od.is_empty():
		return
	if ride:
		_riding.append(od["node"])
		if od.has("tag"):
			(od["tag"] as Node3D).visible = false  # the real loss floats up instead
	else:
		(od["node"] as Node).queue_free()
	_obstacles.erase(id)


# Shared meshes and materials: every obstacle reuses them (no per-spawn allocations).
func _part(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = _mat(color)
	mi.position = pos
	return mi


func _box_mesh(size: Vector3) -> BoxMesh:
	if not _meshes.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[size] = bm
	return _meshes[size]


func _cyl_mesh(key: String, radius: float) -> CylinderMesh:
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.02
		cm.radial_segments = 20
		cm.rings = 1
		_meshes[key] = cm
	return _meshes[key]


func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var key := color.to_html() + ("u" if unshaded else "l")
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	return _mats[key]


# ---------------------------------------------------------------- shield, finish, strike

func _build_shield() -> void:
	_shield_fx = ShieldBubble.new().setup(fx)
	add_child(_shield_fx)


func shield_bubble() -> ShieldBubble:
	return _shield_fx


## Where a blocked shot from `from` aimed at `to` ends: on the bubble, which ripples there.
func _shield_hit(from: Vector3, to: Vector3) -> Vector3:
	return _shield_fx.hit(from, to) if _shield_fx != null else to


# ---------------------------------------------------------------- pre-warm (spec v2 §3)

## Everything that first appears mid-level (each rank and enemy crowd, the effects, every
## obstacle kind, a gate row, the rings, the stash) is drawn once below the road, inside the
## camera's view and shadow range, for the first WARM_FRAMES frames. The GPU pipelines compile
## while the level loads instead of as a hitch when followers join or the stash appears.
func _prewarm() -> void:
	_warm_at = _warm_spot()
	_warm_left = WARM_FRAMES
	_build_finish()
	_finish.position = _warm_at + Vector3(0, -6, -6)
	_spot_ring = _ground_ring(GateRowView.GOLD)
	_spot_ring.position = _warm_at
	var kinds := ["pothole", "barricade", "car", "barrel"]
	for i in kinds.size():
		var fake := {"id": -100 - i, "kind": kinds[i], "lane": 1, "z": 0.0, "hp": 10.0, "hp_max": 10.0,
			"dmg": 1, "fall": 1, "x": 0.0}
		_spawn_obstacle(fake)
		var od: Dictionary = _obstacles[-100 - i]
		_obstacles.erase(-100 - i)
		_warm.append(od["node"])
		(od["node"] as Node3D).position = _warm_at + Vector3(-4.5 + 3.0 * i, 0, -3)
	var row := {"id": -1, "z": 0.0, "gates": [
		{"lane": 0, "op": "num", "v": 5}, {"lane": 1, "op": "num", "v": -5, "step": 1.0, "max": 6},
		{"lane": 2, "op": "power", "id": "bomb", "n": 1}]}
	var gv := GateRowView.new().setup(row, font, LANE_X)
	add_child(gv)
	gv.position = _warm_at + Vector3(0, 0, 3)
	_warm.append(gv)
	if fx.has_method("prewarm"):
		fx.prewarm(_warm_at)
	var wb := ShieldBubble.new().setup()   # the shield bubble's shader, first drawn on a press
	add_child(wb)
	wb.show_warm(_warm_at + Vector3(0, 0, -6))
	_warm.append(wb)
	# Spec v2.1: a telegraph's lane mark (its own shader) and a sniper's laser compile now, not
	# on the first sniper or grenade.
	var zone := MeshInstance3D.new()
	zone.mesh = (_zones[0]["node"] as MeshInstance3D).mesh
	zone.material_override = _zones[0]["mat"]
	zone.position = _warm_at + Vector3(0, 0.1, -2.0)
	add_child(zone)
	var beam := MeshInstance3D.new()
	beam.mesh = _lasers[0].mesh
	beam.material_override = _laser_mat
	beam.position = _warm_at + Vector3(1.0, 0.5, -2.0)
	add_child(beam)
	_warm.append_array([zone, beam])
	# The boss bar (see-through backing, crown sprite, big number): first drawn when the boss
	# walked in, a 54 ms frame on L10 with a cold shader cache.
	var boss_lab := Label3D.new()
	add_child(boss_lab)
	var bv := {"label": boss_lab}
	_build_boss_bar(bv)
	(bv["bar"] as Node3D).position = _warm_at + Vector3(0, 1.0, -2.0)
	(bv["bar_num"] as Label3D).text = "1,234K"
	_warm.append_array([bv["bar"], boss_lab])
	# The new-item card (v2 §11): its card, outline and badge first drew when the first new
	# item came, a 99 ms frame at L13's first SWAT with a cold canvas pipeline cache.
	var hint_ids: Array = []
	for e in _level.get("events", []):
		if String(e.get("type", "")) == "hint":
			hint_ids.append(String(e.get("id", "")))
	if not hint_ids.is_empty():
		new_item_card().prewarm(hint_ids)
	if not demo:
		_prewarm_finale()   # the lobby's street never reaches a stash
	# Every icon this level shows (UiKit caches them), and every glyph at every label size and
	# outline the street uses (the font is rasterised per size on first draw).
	for e in _level.get("events", []):
		for g in (e as Dictionary).get("gates", []):
			var icon := String(GateRowView.describe(g).get("icon", ""))
			if icon != "":
				UiKit.icon_texture(icon)
			if String(g.get("op", "")) == "recruit":
				UiKit.icon_texture(String(g.get("unit", "constable")))
		if String(e.get("type", "")) == "hint":
			UiKit.icon_texture(String(e.get("icon", "")))
	var j := 0
	for so in [[150, 36], [130, 36], [108, 36], [100, 36], [84, 36], [120, 28], [110, 26], [100, 24],
			[90, 21], [84, 20]]:
		var lab := GateRowView._label(font, so[0], 0.011)
		lab.outline_size = so[1]
		lab.text = "+-×÷%0123456789?"
		lab.position = _warm_at + Vector3(0, 0.5, -1.0 - j)
		add_child(lab)
		_warm.append(lab)
		j += 1


## This level's Bottle Shot (spec v2 §3): stash, bottles, HUD and weapon built now and drawn
## out of sight while loading, then resting hidden; the burst into the stash plays this one
## (it was a 173 ms frame with 38 pipeline compiles at L11's finish, then ~80 ms of building).
func _prewarm_finale() -> void:
	var bs := BottleShot.new().setup(world, fx, font, level_id, 0, Vector3.ZERO, 0.0)
	bs.dormant = true
	var cam: Camera3D = world.camera if world else null
	var deep := Vector3(0, -24, -40)
	if cam != null and cam.is_inside_tree():
		var vs := cam.get_viewport().get_visible_rect().size
		var dir := cam.project_ray_normal(Vector2(vs.x * 0.5, vs.y * 0.75))
		if dir.y < -0.2:
			deep = cam.global_position + dir * ((cam.global_position.y + 22.0) / -dir.y)
	# The bottle wall (about 1.5 m up, `distance` ahead of the hero) lands on that view ray,
	# 22 m under the road.
	bs.position = deep - Vector3(0, 1.5, -bs.logic.distance)
	add_child(bs)
	_finale_warm = bs
	# The squad stands in the stash's lights there too: their lit and shadow variants compile now.
	_warm_stash_at = bs.position + Vector3(0, 0, -bs.logic.distance * 0.5)


## A point below the road along a view ray through the lower screen: drawn (inside the view
## and the sun's shadow range) but hidden under the street.
func _warm_spot() -> Vector3:
	var cam: Camera3D = world.camera if world else null
	if cam == null or not cam.is_inside_tree():
		return Vector3(0, -8, -16)
	var size := cam.get_viewport().get_visible_rect().size
	var o := cam.global_position
	var dir := cam.project_ray_normal(Vector2(size.x * 0.5, size.y * 0.7))
	if dir.y > -0.2:
		return Vector3(0, -8, -16)
	# Far enough along the ray to sit 8 m under the road.
	return o + dir * ((o.y + 8.0) / -dir.y)


func _warm_frame() -> void:
	_warm_left -= 1
	var i := 0
	for k in _crowds:
		(_crowds[k] as Crowd).push(Transform3D(Basis(), _warm_at + Vector3(-6.0 + 0.7 * i, -1.0, 0)), "run", 0.0, 0.5)
		if _warm_stash_at != Vector3.ZERO:
			(_crowds[k] as Crowd).push(Transform3D(Basis(), _warm_stash_at + Vector3(-3.0 + 0.5 * i, 0, 0)), "idle", 0.0, 0.0)
		i += 1
	if _warm_left > 0:
		return
	for n in _warm:
		n.queue_free()
	_warm.clear()
	_spot_ring.visible = false
	if not _finish_live:
		_finish.visible = false
	if BottleShot.reusable(_finale_warm, level_id):
		_finale_warm.rest()   # hidden and still until the squad reaches the stash


func _spawn_finish(at: float) -> void:
	if _finish == null:
		_build_finish()
	_finish_live = true
	_finish.visible = true
	_finish.position = Vector3(0, 0, -(at - sim.traveled))


## The finish line and the gang's stash, built at load (out of sight, pre-warm) and shown when
## the sim spawns the finish: building it then cost a 70 ms frame on a cold shader cache.
func _build_finish() -> void:
	_finish = Node3D.new()
	add_child(_finish)
	# Chequered line
	for i in 20:
		for j in 2:
			var tile := World._box(Vector3(0.49, 0.03, 0.5), Color.WHITE if (i + j) % 2 == 0 else Color(0.1, 0.1, 0.1))
			tile.position = Vector3(-4.75 + i * 0.5, 0.02, j * 0.5)
			_finish.add_child(tile)
	# The gang's stash front, themed per district (bar, carnival stall, docks, factory, rooftop
	# lounge) with its neon bottle sign: where Bottle Shot happens once the squad bursts in.
	_hq = FinaleStash.facade(district)
	_hq.position = Vector3(0, 0, -16)
	_finish.add_child(_hq)
	var bar_bg := World._box(Vector3(6.2, 0.5, 0.2), Color(0.1, 0.1, 0.1))
	bar_bg.position = Vector3(0, 7.3, 0)
	_hq.add_child(bar_bg)
	_hq_fill = World._box(Vector3(6.0, 0.36, 0.22), Color("e0484f"))
	_hq_fill.position = Vector3(0, 7.3, 0.02)
	_hq.add_child(_hq_fill)


func _begin_strike() -> void:
	# The squad gathers behind the hero; Bottle Shot takes over the camera.
	var t0 := Time.get_ticks_usec()
	_state = "finale"
	_time_scale = 1.0
	fx.scroll_speed = 0.0
	fx.land_bomb()          # spec v2 §12.5: no bomb ever flies over Bottle Shot
	fx.held_bomb_on = false
	_bomb_launch = {}
	if _bomb_mark != null:
		_bomb_mark.visible = false
	strike_ready.emit()
	var hero := _slot_pos(0, _allies.size())
	_hq.visible = false   # the squad bursts in: the finale is played inside the stash
	# Coins count the squad as district-1 troops (LevelSim.coin_troops), so a 100K squad in
	# district 5 pays like a full squad in district 1 and the economy's curve holds.
	# Spec v2.1 §3.1: the coins are Economy.level_coins; tapping adds its tap term (the level's
	# mean heat, up to +10%) and the evidence room multiplies.
	var bonus := Game.coin_bonus()
	var reuse := BottleShot.reusable(_finale_warm, level_id)
	finale = _finale_warm if reuse else BottleShot.new().setup(world, fx, font, level_id, sim.coin_troops(), hero, bonus)
	_finale_warm = null
	finale.logic.heat = sim.mean_heat()
	finale.on_throw = func(): _hero_throw_t = 0.0
	finale.done.connect(_on_finale_done)
	if reuse:
		finale.wake(sim.coin_troops(), hero, bonus)   # built at load: nothing to build now
	else:
		add_child(finale)
	if perf_on:
		perf_marks.append("strike_cpu:%.1f%s" % [(Time.get_ticks_usec() - t0) / 1000.0, "" if reuse else ":built"])


func _on_finale_done(r: Dictionary) -> void:
	_state = "done_win"
	fx.explosion(_hq.global_position + Vector3(0, 3, 0), 2.5)
	fx.confetti(_hq.global_position + Vector3(0, 5, 0), 60)
	_hq.visible = false
	world.shake(1.0)
	Sfx.play("boom")
	r.merge({"won": true, "troops": sim.squad.total(), "kills": sim.kills, "level": level_id,
		"tap_pct": Economy.heat_pct(sim.mean_heat())})
	finished.emit(r)


# ---------------------------------------------------------------- v2.1: rescue cages, gang leader

const LEADER_SCALE := 2.2   # a gang leader (L1's last wave) is drawn this much bigger than his men


## A gang leader: one tough man (a level gives a single gang member at least 10x his kind's
## health). He is drawn big and his number is his health, so the player sees why he soaks fire.
static func is_leader(h: Dictionary) -> bool:
	if h.get("boss", false) or int(h.get("start", 0)) != 1:
		return false
	var def: Dictionary = Game.units.get("enemies", {}).get(String(h.get("enemy", "")), {})
	return not def.is_empty() and float(h.get("hp", 0.0)) >= 10.0 * float(def.get("hp", 1.0))


func _on_cage_event(e: Dictionary) -> void:
	var c: Dictionary = e["cage"]
	var id := int(c["id"])
	match String(e["type"]):
		"cage_spawn":
			var v := CageView.new().setup(c, font)
			add_child(v)
			v.position = Vector3(LANE_X[int(c["lane"])], 0, float(c["z"]))
			_cages[id] = {"cage": c, "view": v}
		"cage_open":
			var cv: Dictionary = _cages.get(id, {})
			if not cv.is_empty():
				(cv["view"] as CageView).open()
				fx.confetti((cv["view"] as Node3D).global_position + Vector3(0, CageView.H, 0), 24)
				Sfx.play("flip")
		"cage_free":
			var cv: Dictionary = _cages.get(id, {})
			if cv.is_empty():
				return
			var v: CageView = cv["view"]
			v.free_people()
			Sfx.play("gate_good")
			Sfx.play("recruit", -4.0)
			Game.vibrate(35)
			fx.burst(v.global_position + Vector3(0, 1.6, 0), Color("5df07a"), 26, 7.0, 0.22, 0.6)
			# The freed people run out of the cage into the formation.
			_sync_allies(v.global_position)
			if String(e.get("unit", "constable")) != "constable":
				rank_joined.emit(String(e["unit"]), false)
			_riding.append(v)
			_cages.erase(id)
		"cage_lost":
			var cv: Dictionary = _cages.get(id, {})
			if cv.is_empty():
				return
			(cv["view"] as CageView).lost()
			Sfx.play("gate_bad")
			cv["lost_t"] = 0.0


## Cages ride the road; a lost one is dragged back up the street and shrinks away. The people
## inside are police figures (the cage's own crowd kind), idle while they wait.
func _draw_cages(d: float) -> void:
	for id in _cages.keys():
		var cv: Dictionary = _cages[id]
		var c: Dictionary = cv["cage"]
		var v: CageView = cv["view"]
		if cv.has("lost_t"):
			cv["lost_t"] = float(cv["lost_t"]) + d
			var k := clampf(1.0 - float(cv["lost_t"]) / 1.2, 0.0, 1.0)
			v.position.z -= d * 22.0
			v.scale = Vector3.ONE * maxf(k, 0.01)
			if k <= 0.0:
				v.queue_free()
				_cages.erase(id)
			continue
		v.position.z = float(c["z"])
		var unit := String(c.get("unit", "constable"))
		var crowd: Crowd = _crowds.get(unit, _crowds["constable"])
		for spot in CageView.spots(int(c.get("hostages", 0))):
			var p: Vector3 = v.position + (spot as Vector3)
			crowd.push(Transform3D(Basis(Vector3.UP, PI), p), "idle", _anim_t + p.x)
