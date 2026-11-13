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
const LT_SCALE := 2.9           # units.json lieutenant.scale (review v2.1: 2.4 read as a big thug at range)
const LT_HAT := Color("efe6cf")   # his cream fedora with a black band, and a red ring at his feet
const LT_AURA := Color(1.0, 0.18, 0.12, 0.85)
const LT_BAR := 0.72
const LT_COLORS := {Color("151515"): Color("e9e1cd"), Color("b3282d"): Color("1c1c22")}
const LT_CROWN := Color(0.78, 0.84, 0.95)
## Spec v2.1 §1.1: incoming fire reads at a glance: at most this many tracers per event, and the
## red -N over the squad sums what is lost within MINUS_WINDOW s (shown MINUS_HOLD s).
const TRACERS_PER_EVENT := 8
const MINUS_WINDOW := 0.3
const MINUS_HOLD := 0.9
const MINUS_RED := Color("ff3b3b")
const MINUS_Y := 1.6             # the -N's anchor: at the squad's front line, below the hero's head
const REACH_SIZE := Vector2(1.7, 0.22)  # the reach bar under a gang's count (m, at scale 1)
const REACH_BG := Color(0.93, 0.95, 1.0, 0.5)   # its empty part: pale, so "melts first" reads too
const RF_TRACER_MIN := 3         # a volley draws at least this many tracers (its shooters; the rest miss)
const MINUS_Z := 0.8
## Owner play-test 2026-11-13: every loss says what did it. The red -N carries the cause's icon
## (CAUSE_ICON by attack kind; obstacles by their own kind), MINUS_ICON_W wide at scale 1.
const MINUS_ICON_W := 0.85
const GUN_ICON := "pistol"       # gunfire (a gang's volley, the boss's gun): the same gun over the shooter
const CAUSE_ICON := {"snipe": "aim", "grenade": "blast", "firebomb": "fire", "barrage": "blast",
	"lt_barrage": "blast", "sweep": "blast", "crane": "crane", "steam": "steam", "chopper": "chopper",
	"melee": "thug", "gun": GUN_ICON}   # clash: the gang itself (the fist-bump read as "join")
## The stash (FinaleStash.facade) is built STASH_FACE m behind its front face, which stands
## LevelSim.stash_front m past the finish line. No gang figure is drawn closer to that face than
## STASH_PAD: a deep gang's back rows close up in front of it instead of standing inside it.
const STASH_FACE := 4.0
const FIRST_FIRE_HINT := "first_gunfire"   # Game.hint_seen: the first-ever volley got its ring
const STASH_PAD := 0.4
const STASH_OUT := 1.5          # a gang still inside the stash shows as a block this deep at its door
## Spec v2.1 §1.2-1.3: a telegraph marks its lane where the squad stands, in its kind's colour,
## while its countdown sweeps towards the squad (on the street's clock, so it is honest).
## Review v2.1: the mark runs up the lane in front of the squad (1.5-13.5 m ahead), so the
## countdown sweep is never under the squad's own crowd; a countdown ring over the squad
## repeats it while the squad's lane is marked.
const ZONE_SIZE := Vector2(2.4, 12.0)
const ZONE_Z := -7.5             # the mark's centre: 1.5 m to 13.5 m ahead of the hero
const SHELL_Z := -0.4            # where a barrage's shells land: on the squad's lane, around the squad
const RING_Y := 3.4              # the countdown ring over the squad (m)
const LASER_FAR_W := 0.42        # a sniper's laser is this wide at his end (m) ...
const LASER_NEAR_W := 0.1        # ... and this wide where it meets the lane (a tapered beam)
const SPOT_Z := -2.0             # where a grenade, bottle or sniper round lands: just ahead of the hero
const DODGE_TINT := Color(0.7, 0.95, 1.0)   # the ring round a squad that dodged a marked attack
const THREAT_TINT := {"snipe": Color(1.0, 0.1, 0.1), "grenade": Color(1.0, 0.4, 0.06),
	"firebomb": Color(1.0, 0.58, 0.05), "barrage": Color(1.0, 0.06, 0.18), "lt_barrage": Color(1.0, 0.16, 0.5),
	"sweep": Color(1.0, 0.04, 0.3), "crane": Color(1.0, 0.5, 0.06), "steam": Color(1.0, 0.72, 0.3),
	"chopper": Color(1.0, 0.12, 0.08)}
## Review v2.1: the district hazards (units.json hazards) on screen. The docks' container drops
## from CRANE_Y onto the marked lane; the mill's vents burst steam from the road; uptown's
## helicopter hovers CHOPPER_Z up the street over the marked lane and strafes it.
const HAZARD_KINDS := ["crane", "steam", "chopper"]
const CRANE_Y := 16.0
const CHOPPER_Y := 8.5
const CHOPPER_Z := -20.0
const SHELLS := {"barrage": 5, "lt_barrage": 3, "sweep": 3}
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
## A released swipe settles in the lane nearest the finger's spot pushed this far on in the
## direction it was moving (owner 2026-11-13: a quick flick toward a lane takes that lane; it
## used to spring back into the marked lane it was leaving unless it passed the midpoint + slack).
const FLICK_BIAS := 0.9
## The level's clock starts only once it is on screen (owner 2026-11-13: the squad had walked a
## few metres while the level was still loading): after the warm frames, START_HOLD_FRAMES more
## drawn frames, and no frame slower than START_SLOW_S (still loading), at most START_HOLD_MAX.
const START_HOLD_FRAMES := 2
const START_SLOW_S := 0.1
const START_HOLD_MAX := 30

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
var _drawn_x := 0.0            # the squad x the formation was last drawn at (steering shift)
var _steer_dir := 0            # the steering finger's last direction of travel (-1, 0, 1)
var started := false           # the street's clock runs (false while the level is still loading)
var _start_frames := 0         # frames drawn while it waited to start
var clear_run := false         # LevelSim.clear: nothing left to fight, the squad runs to the stash
var _run_t := 0.0              # the run cycle's clock (faster on the clear run)
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
var _tele_ring: MeshInstance3D  # the countdown ring over the squad while its lane is marked
var _choppers: Dictionary = {}  # hazard id -> {node, x, t (0..1 in), leave}
var _crates: Array = []         # falling or landed containers: {node, lane, start, land, id, gone}
var _tele_ring_mat: ShaderMaterial
var _impacts: Array = []       # incoming shots in the air: {at, lost, blocked, points (x by the squad)}
var _pending_lost := 0         # troops the sim took whose shots have not landed on screen yet
var _minus_label: Label3D      # the red -N over the squad
var _minus_n := 0
var _minus_t0 := -10.0         # when the current -N window opened (_anim_t)
var _minus_last := -10.0       # the last loss added to it
var _minus_pop := 0.0
var _minus_icon: Sprite3D       # the cause of the current -N (CAUSE_ICON)
var _minus_cause := ""
var _minus_w := 0.0             # the -N's text width (m, at scale 1)
var cues: LossCues              # who shot: gun icons over firing gangs, volley lines, first-fire ring
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
	_minus_icon = Sprite3D.new()
	_minus_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_minus_icon.shaded = false
	_minus_icon.no_depth_test = true
	_minus_icon.render_priority = 9
	_minus_icon.pixel_size = MINUS_ICON_W / 320.0
	_minus_icon.visible = false
	_minus_icon.add_child(LossCues.badge(MINUS_ICON_W, 8))
	add_child(_minus_icon)
	cues = LossCues.new().setup()
	add_child(cues)
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
	# anyway, or a revive starts with the squad parked between lanes on a stale anchor. Lifted
	# in play, the swipe settles in the lane it was heading for (release_lane).
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).index == _steer_id:
		if not (event as InputEventScreenTouch).pressed and not demo and _state == "play" and input_enabled:
			settle_steer()
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
			_steer_dir = 0
		if d.index != _steer_id:
			return
		var w := get_viewport().get_visible_rect().size.x
		var nx := clampf(_steer_from + (d.position.x - _drag_from_x) / w * STEER_PER_SCREEN,
			LANE_X[0], LANE_X[2])
		if absf(nx - _steer_x) > 0.02:
			_steer_dir = signi(int(signf(nx - _steer_x)))
		_steer_x = nx
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


## The lane a swipe released at squad x `x`, moving in direction `dir` (-1, 0, 1), settles in:
## the lane nearest x pushed FLICK_BIAS m on in that direction. A flick that has the squad a
## third of the way over takes the next lane; one dragged back toward its lane keeps it.
static func release_lane(x: float, dir: int) -> int:
	var w: float = LANE_X[2] - LANE_X[1]
	return clampi(int(round((x + FLICK_BIAS * signf(dir)) / w)) + 1, 0, 2)


## The steering finger lifted in play: the squad commits to the lane the swipe was heading for
## (and never springs back into the lane it was leaving, owner 2026-11-13).
func settle_steer() -> void:
	if not _touching:
		return
	var want := release_lane(_steer_x, _steer_dir)
	for i in 2:
		if sim.lane == want:
			break
		_move(signi(want - sim.lane))


## How the squad's x follows its target (the finger, or the lane centre) over `d` seconds.
static func steer_toward(x: float, target: float, d: float) -> float:
	return lerpf(x, target, 1.0 - exp(-d * STEER_EASE))


## One tap: the hero's heat rises (LevelSim.tap, spec v2 §2) and his hand flicks.
func tap() -> void:
	if paused or _state != "play" or clear_run:
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
	var show: bool = not demo and _state == "play" and not clear_run and not _allies.is_empty() \
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
## lesson's hold, the level still loading), and when it comes within input.power_guard_s of a
## fire tap that landed right next to `button` (screen rect): a thumb tapping fast that slid onto
## the button. A press with the other thumb while tapping still works. The sim also takes one
## bomb at a time.
func use_power(id: String, button := Rect2()) -> bool:
	if paused or _state != "play" or hold or _time_scale <= 0.0 or not started:
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
			if not started:
				if not _ready_to_start(delta):
					# Still loading: the level is drawn (and its warm frames compile) but the
					# street's clock waits, so the squad starts where the level starts. The
					# squad stands (no fire, no run) until it does.
					_update_visuals(delta)
					return
				started = true
				_acc = 0.0
				delta = DT   # the first played frame is one step, never the load's long frame
				if perf_on:
					perf_marks.append("sim_start:%d" % _start_frames)
					print("LEVEL start: the clock starts after %d drawn frames, sim.time %.3f traveled %.3f" % [_start_frames, sim.time, sim.traveled])
			_update_time_scale(delta)
			var d := delta * _time_scale
			_acc += d
			var steps := 0
			# The squad's steering for this frame first: the sim decides every hit (obstacles,
			# a telegraphed attack landing) by where the squad is drawn this frame, between
			# lanes while steering. Autoplay keeps lane centres so its runs match the headless routes.
			_steer(d)
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
			_update_visuals(d, true)
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


## True once the level may start its clock (see START_HOLD_FRAMES): the warm frames are done,
## START_HOLD_FRAMES more frames were drawn, and this frame was not a slow loading one (or the
## wait reached START_HOLD_MAX frames).
func _ready_to_start(delta: float) -> bool:
	_start_frames += 1
	if _warm_left > 0:
		return false
	if _start_frames >= START_HOLD_MAX:
		return true
	return _start_frames > WARM_FRAMES + START_HOLD_FRAMES and delta < START_SLOW_S


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
			print("EV %d %s %s%s%s" % [Engine.get_process_frames(), e["type"], e["horde"].get("enemy", "") if e.get("horde") is Dictionary else "",
				(" " + String(e["kind"])) if e.has("kind") else "", (" lost=%d" % int(e["lost"])) if e.has("lost") else ""])
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
				Game.vibrate(60)
				world.shake(0.5)
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
			"street_clear":
				clear_run = true   # the squad lowers its guns and runs to the stash
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
				_add_loss(int(e.get("lost", 0)), false, String(hit_ob.get("kind", "")))
				# A pothole stays in the road and rides away; anything solid was smashed.
				_free_obstacle(int(hit_ob["id"]), hole)
			"obstacle_pass":
				_free_obstacle(int(e["ob"]["id"]), true)
			"pothole_pass":
				_on_pothole(e)
			"barricade_hit":
				_on_barricade_hit(e)
			"hazard_start":
				_on_hazard_start(e)
			"hazard_end":
				if _choppers.has(int(e["id"])):
					_choppers[int(e["id"])]["leave"] = true
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
		"hit_flash": 0.0, "shown": -1, "lt": lt, "bossy": lt or bool(h.get("boss", false)), "leader": is_leader(h),
		"fire_t": 0.0}
	_hordes[h["id"]] = hv
	if not hv["bossy"]:
		# Review v2.1 (honest numbers): a bar under the count, measured against the squad's
		# firepower: its red share is how much of the squad the people who would reach it are
		# worth (LevelSim.reach_estimate); empty = the squad's fire melts it before contact.
		var bg := _quad(REACH_SIZE, REACH_BG, 9)
		var fill := _quad(REACH_SIZE, MINUS_RED, 10)
		for q in [bg, fill]:
			var m := q.material_override as StandardMaterial3D
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m.billboard_keep_scale = true
			q.visible = false
			add_child(q)
		hv["reach_bg"] = bg
		hv["reach_fill"] = fill
	if lt:
		# Review v2.1: a silhouette of his own at range, not only a tint: a wide cream fedora and
		# a red ring at his feet.
		var hat := Node3D.new()
		hat.add_child(_part(Vector3(0.62, 0.05, 0.62), LT_HAT, Vector3(0, 0.0, 0)))
		hat.add_child(_part(Vector3(0.36, 0.2, 0.34), LT_HAT, Vector3(0, 0.12, 0)))
		hat.add_child(_part(Vector3(0.38, 0.06, 0.36), Color(0.08, 0.08, 0.09), Vector3(0, 0.05, 0)))
		add_child(hat)
		hv["prop"] = hat
		hv["aura"] = _ground_ring(LT_AURA)
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


## Spec v2.1 §1.4, the crowd clash: every melee tick a few of the gang's front row strike. The
## sim already took them off its count; the figure sync (_update_visuals) pops exactly the
## figures the count lost and sends this tick's strikers' worth of them charging in (a figure
## stands for `per` people, so a tick's strikers can be part of one figure). The squad's front
## rows fall where the gang meets it, and the red -N keeps counting while the clash lasts.
func _on_melee(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	if hv.is_empty():
		return
	if not hv["bossy"]:
		# (A boss or lieutenant swings with his own fists and never falls to them: no strikers
		# to send in, so his death later is his own big fall, not a thug-sized charge.)
		var per := float(hv["per"])
		hv["strike"] = minf(float(hv.get("strike", 0.0)) + float(e["enemies"]), per * 4.0)
		hv["strike_sh"] = bool(e["shielded"])
		hv["clash_t"] = 0.4
	var lost := int(e["lost"])
	world.shake(clampf(0.08 + lost * 0.004, 0.08, 0.3))
	if e["shielded"]:
		Sfx.play("blocked", -4.0, randf_range(0.9, 1.1))
	elif lost > 0:
		Sfx.play("hurt", -6.0, randf_range(0.85, 1.15))
		_add_loss(lost, true, CAUSE_ICON["melee"])
	var front: Array = []
	for x in [-1.2, -0.6, 0.0, 0.6, 1.2]:
		front.append(Vector3(_squad_x + x, 0, -1.4))
	_sync_allies(Vector3(_squad_x, 0, -1.0), front)


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
## for its opening volley), up to 8 fast gunfire streaks that hit within Fx.GUN_MAX_S (the
## squad or the shield), and the loss lands with them: the figures they hit fall, a red -N, the
## troop pill pulses, a short buzz. Gunfire cannot be dodged (the sim took the loss when it
## fired), so it is drawn as bullets, never as a slow shot that seems to chase a squad changing
## lane (owner 2026-11-13); the dodgeable attacks are slow (lobbed or lasered) and lane-marked.
func _on_return_fire(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var opening := bool(e.get("opening", false))
	# Review v2.1: one tracer per shooter in the volley (at least RF_TRACER_MIN); the shots that
	# hit are the ones that fall, the rest miss onto the road.
	var shots := maxi(int(e.get("shots", 1)), 1)
	var n := clampi(maxi(shots, maxi(int(e.get("shooters", 1)), RF_TRACER_MIN)), 1, TRACERS_PER_EVENT)
	var froms := _shooter_points(hv, n, Vector3(float(e.get("x", 0.0)), 1.35, float(e.get("z", -45.0))))
	if not hv.is_empty():
		hv["shoot_flash"] = 0.2 if opening else 0.14
		hv["fire_t"] = 0.35
	for f in froms:
		fx.muzzle_big(f, _flash_k(f) * (1.8 if opening else 1.4))
	_volley(froms, int(e.get("lost", 0)), bool(e.get("blocked", false)), "egun", mini(shots, n))
	_who_shot(hv, int(e.get("horde", -1)), froms)
	if _rf_sfx_t <= 0.0 or opening:
		_rf_sfx_t = 0.09
		Sfx.play("shot", -4.0 if opening else -8.0, randf_range(0.8, 0.95))


## Owner play-test 2026-11-13: one bold line from the shooters to the squad per volley, their
## gun icon kicks, and the first time a gang ever fires at the player (once per save) a ring
## circles it and a line ties it to the squad for a moment (no pause, no slow motion).
func _who_shot(hv: Dictionary, id: int, froms: Array) -> void:
	if demo or froms.is_empty():
		return
	var mid := Vector3.ZERO
	for f in froms:
		mid += f
	cues.volley(mid / froms.size())
	if hv.is_empty():
		return
	hv["gun_kick"] = 1.0
	hv["gun_t"] = 1.2
	if cues.focus_id < 0 and not Game.hint_seen(FIRST_FIRE_HINT):
		Game.mark_hint(FIRST_FIRE_HINT)
		cues.focus_on(id)


## Spec v2.1 §1.3: the boss's (or lieutenant's) gun: a big flash at his gun hand and two heavy
## gunfire streaks (undodgeable, like a gang's); the loss lands with them and shows its -N.
func _on_boss_shot(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var from := Vector3(0, 4.0, -40.0)
	if not hv.is_empty():
		hv["shoot_flash"] = 0.2
		from = _boss_gun(hv)
	fx.muzzle_big(from, _flash_k(from) * 1.6)
	_volley([from, from + Vector3(0.25, -0.15, 0.1)], int(e.get("lost", 0)), bool(e.get("blocked", false)), "egun_big")
	_who_shot(hv, int(e.get("horde", -1)), [from])
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
	return clampf(-at.z / 16.0, 1.0, 3.5)   # review v2.1: a volley 50 m out reads at a glance


## Fires `froms.size()` incoming tracers at the squad (onto the shield when `blocked`). The
## figures they aim at are the ones that fall: `lost` troops land when the first one arrives.
func _volley(froms: Array, lost: int, blocked: bool, kind: String, hits := -1) -> void:
	var targets := _volley_targets(froms, blocked)
	if hits >= 0 and not blocked:
		# Tracers past the volley's hits miss: they strike the road around the squad's front.
		for i in range(maxi(hits, 1), targets.size()):
			targets[i] = Vector3(_squad_x + randf_range(-2.6, 2.6), 0.05, randf_range(-3.5, -1.2))
	var first := INF
	for i in froms.size():
		var t := fx.enemy_shoot(froms[i], targets[i], true, kind)
		if t > 0.0:
			first = minf(first, t)
	var rel: Array = []
	for p in targets:
		rel.append((p as Vector3) - Vector3(_squad_x, 0, 0))
	_impacts.append({"at": _anim_t + (first if first < INF else 0.0), "lost": maxi(lost, 0), "blocked": blocked,
		"points": rel, "cause": GUN_ICON})
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
	_add_loss(lost, false, String(im.get("cause", GUN_ICON)))
	_sync_allies(Vector3(_squad_x, 0, 0), pts)


## Spec v2.1 §1.1: the red -N over the squad. Losses within MINUS_WINDOW s add up; a later one
## starts a new number (with a short buzz, through the vibration setting). `run`: a crowd clash
## tick (§1.4), which keeps the number counting while the ticks keep coming. `cause` (owner
## play-test 2026-11-13): the icon of what took them (CAUSE_ICON, an obstacle's kind) beside the
## number; a loss with another cause starts its own number.
func _add_loss(n: int, run := false, cause := "") -> void:
	if n <= 0:
		return
	var fresh := _anim_t - _minus_t0 > MINUS_WINDOW
	if run and _anim_t - _minus_last <= MINUS_WINDOW + 0.05:
		fresh = false
	if cause != _minus_cause and _minus_label.visible:
		fresh = true
	if fresh:
		_minus_t0 = _anim_t
		_minus_n = 0
		Game.vibrate(30)
	_minus_n += n
	_minus_last = _anim_t
	_minus_pop = 1.0
	_minus_label.text = "-" + NumFormat.fmt(_minus_n)
	_minus_label.visible = true
	_minus_w = GateRowView.text_w(_minus_label, _minus_label.text)
	if cause != _minus_cause:
		_minus_cause = cause
		_minus_icon.texture = UiKit.icon_texture(cause) if cause != "" else null
	_minus_icon.visible = cause != ""


## The cause icon beside the red -N (tests): "" when none shows.
func minus_cause() -> String:
	return _minus_cause if _minus_icon.visible else ""


func _tick_minus(d: float) -> void:
	if not _minus_label.visible:
		return
	var age := _anim_t - _minus_last
	if age > MINUS_HOLD:
		_minus_label.visible = false
		_minus_icon.visible = false
		return
	_minus_pop = maxf(_minus_pop - d * 5.0, 0.0)
	var a := clampf((MINUS_HOLD - age) / 0.3, 0.0, 1.0)
	_minus_label.modulate = Color(MINUS_RED, a)
	_minus_label.outline_modulate = Color(0.05, 0.05, 0.08, a)
	# Review v2.1: at the squad's own front line, below the hero's head, drifting toward the
	# camera (never up the street into a clashing gang's number, where it read as their loss).
	_minus_label.position = Vector3(_squad_x, MINUS_Y - 0.35 * minf(age, MINUS_HOLD), MINUS_Z + 0.9 * minf(age, MINUS_HOLD))
	_minus_label.scale = Vector3.ONE * (1.0 + 0.6 * _minus_pop)
	if _minus_icon.visible:
		# The cause sits just left of the number, the same size as its digits.
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var right := cam.global_basis.x if cam else Vector3.RIGHT
		var sc := _minus_label.scale.x
		_minus_icon.position = _minus_label.position - right * (_minus_w * 0.5 + MINUS_ICON_W * LossCues.BADGE_K * 0.5) * sc
		_minus_icon.scale = Vector3.ONE * sc
		_minus_icon.modulate = Color(1, 1, 1, a)
		(_minus_icon.get_child(0) as Sprite3D).modulate = Color(1, 1, 1, a)


# ---------------------------------------------------------------- v1 threats and moments

## Plays a spec sound id, or `fallback` until AUDIO ships a file for it.
func _sfx(id: String, fallback: String, vol := 0.0, pitch := 1.0) -> void:
	Sfx.play(id if Sfx.has_sound(id) else fallback, vol, pitch)


func _on_pothole(e: Dictionary) -> void:
	var hole := _obstacle_pos(e["ob"])
	_sfx("pothole", "thunk", 0.0, 0.8)
	fx.burst(hole + Vector3(0, 0.3, 0), Color(0.42, 0.36, 0.3), 16, 4.0, 0.22, 0.5)
	if int(e["lost"]) > 0:
		Game.vibrate(70)   # (its red -N, with the pothole's icon, is the squad's: obstacle_hit)
	# The troops the hole took drop into it (obstacle_hit picks exactly which ones).
	_death_at = hole


func _on_barricade_hit(e: Dictionary) -> void:
	var p := _obstacle_pos(e["ob"])
	_splinters(p, 1.4)
	_sfx("crash", "boom", -2.0, 0.9)
	world.shake(0.8)
	Game.vibrate(90)
	# (Its red -N, with the barricade's icon, is the squad's: obstacle_hit.)
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
	var lanes: Array = e.get("lanes", [lane])
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
	var th := {"id": int(e.get("id", -1)), "kind": kind, "lane": lane, "src": src, "from": from, "start": sim.time,
		"land": sim.time + dur, "points": [spot]}
	match kind:
		"snipe":
			Sfx.play("tick", -6.0, 2.2)
		"grenade":
			fx.enemy_lob("grenade", from, spot, dur, 4.0)
			_sfx("launcher", "swoosh", -7.0, 1.3)
		"firebomb":
			fx.enemy_lob("lob", from, spot, dur, 2.5)
			Sfx.play("swoosh", -5.0, 0.7)
		"crane":
			# A container swings out over the marked lane and falls onto it.
			var crate := _crate_node()
			crate.position = Vector3(LANE_X[lane], CRANE_Y, SHELL_Z - 0.6)
			add_child(crate)
			_crates.append({"node": crate, "lane": lane, "start": sim.time, "land": sim.time + dur,
				"id": int(e.get("id", -1)), "gone": -1.0})
			Sfx.play("swoosh", -6.0, 0.55)
		"steam":
			# The vents under the marked lanes hiss: thin wisps first, the burst on landing.
			for l in lanes:
				if int(l) != lane:
					var th3 := th.duplicate()
					th3["lane"] = int(l)
					_threats.append(th3)
			for l in lanes:
				fx.burst(Vector3(LANE_X[int(l)], 0.2, SHELL_Z - 1.0), Color(0.95, 0.95, 0.95), 8, 1.6, 0.35, 0.8, 2.0, -1.0)
			_sfx("fire", "swoosh", -9.0, 2.0)
		"chopper":
			var ch: Dictionary = _choppers.get(src, {})
			if not ch.is_empty():
				ch["x"] = LANE_X[lane]
			Sfx.play("tick", -8.0, 1.6)
		"barrage", "lt_barrage", "sweep":
			# A sweep (his second pattern) puts its shells on both marked lanes.
			for l in lanes:
				var pts: Array = []
				for i in int(SHELLS.get(kind, 3)):
					var p := Vector3(LANE_X[int(l)] + randf_range(-0.9, 0.9), 0.3, SHELL_Z + randf_range(-3.0, 1.2))
					pts.append(p)
					fx.enemy_lob("shell", from + Vector3(randf_range(-0.4, 0.4), 0, 0), p, dur, randf_range(6.0, 9.0))
				if int(l) == lane:
					th["points"] = pts
				else:
					var th2 := th.duplicate()
					th2["lane"] = int(l)
					th2["points"] = pts
					_threats.append(th2)
			_sfx("launcher", "boom", -3.0, 0.7 if kind != "sweep" else 0.55)
			world.shake(0.3)
	_threats.append(th)


## The sim's landing of a telegraphed attack: the impact on the marked lane (a sniper round, a
## grenade blast, burning fuel, the barrage), then what it did: blocked by the shield, the loss
## (red -N, the figures it hit fall) or nothing (the squad stepped out of the lane).
func _on_attack_land(e: Dictionary) -> void:
	var kind := String(e.get("kind", ""))
	var lane := clampi(int(e.get("lane", 1)), 0, 2)
	if bool(e.get("cancelled", false)):
		# The sim called it off (the squad fell or revived, the finish, a sniper who died): its
		# marks go quietly, with no impact, sound or shake.
		_drop_threat(int(e.get("id", -1)), kind, lane)
		for c in _crates:
			if int(c["id"]) == int(e.get("id", -2)):
				c["gone"] = sim.time
		return
	var lanes: Array = e.get("lanes", [lane])
	if lanes.size() > 1:
		# A sweep lands on every lane it marked: the others are drawn here, the squad's below.
		for l in lanes:
			if int(l) == lane:
				continue
			var other: Dictionary = {}
			for t in _threats:
				if int(t.get("id", -2)) == int(e.get("id", -1)) and int(t["lane"]) == int(l):
					other = t
			if not other.is_empty():
				_threats.erase(other)
				if kind != "steam":
					for p in other["points"]:
						fx.explosion((p as Vector3) + Vector3(0, 0.4, 0), 0.8)
			(_zones[int(l)] as Dictionary)["flash"] = 0.18
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
		"crane":
			for c in _crates:
				if int(c["id"]) == int(e.get("id", -2)):
					c["gone"] = sim.time + 0.7
			var at := Vector3(LANE_X[lane], 0.3, SHELL_Z - 0.6)
			fx.burst(at, Color(0.62, 0.58, 0.52), 26, 7.0, 0.5, 0.7, 1.0, 2.0)
			fx.ring(at, Color(1.0, 0.7, 0.3), 32, 9.0, 0.26)
			Sfx.play("boom", -2.0, 0.6)
			world.shake(0.9)
		"steam":
			for l in lanes:
				var v := Vector3(LANE_X[int(l)], 0.2, SHELL_Z - 1.0)
				# Hot steam bursts up out of the road (white, rising), with an orange glow at the vent.
				fx.burst(v, Color(1, 1, 1), 34, 5.0, 0.7, 1.0, 7.0, -2.0)
				fx.burst(v, Color(1.0, 0.6, 0.2), 10, 3.0, 0.35, 0.45, 2.0, 0.0)
			_sfx("fire", "swoosh", -2.0, 0.7)
			world.shake(0.6)
		"chopper":
			var from := Vector3(LANE_X[lane], CHOPPER_Y - 0.6, CHOPPER_Z)
			var ch: Dictionary = _choppers.get(int(e.get("src", -1)), {})
			if not ch.is_empty():
				from = (ch["node"] as Node3D).position + Vector3(0, -0.8, 1.2)
			fx.muzzle_big(from, 2.0)
			for i in 6:
				var to := Vector3(LANE_X[lane] + randf_range(-1.0, 1.0), 0.6 + randf() * 0.6, randf_range(-2.0, 1.0))
				# A burst that hits at the sim's landing (not a beat after it).
				fx.enemy_shoot(from, to, false, "etracer", 0.05 + 0.025 * i)
			_sfx("shot_rifle", "shot", -3.0, 0.8)
			world.shake(0.5)
		"barrage", "lt_barrage", "sweep":
			for p in pts:
				fx.explosion((p as Vector3) + Vector3(0, 0.4, 0), 0.85 if kind != "lt_barrage" else 0.7)
			fx.ring(Vector3(LANE_X[lane], 0.3, SHELL_Z), Color(1.0, 0.45, 0.2), 40, 11.0, 0.28)
			Sfx.play("boom", 0.0, 0.8)
			world.shake(0.7 if kind == "lt_barrage" else 1.0)
	var lost := int(e.get("lost", 0))
	if not bool(e.get("hit", true)) and _state == "play":
		# Dodged: the squad left the marked lane in time. A pale whoosh ring round it says so
		# (the impact above lands on the empty lane).
		# (Over the heads: at the feet a full squad's figures hid it.)
		fx.ring(Vector3(_squad_x, 2.0, -0.4), DODGE_TINT, 36, 6.0, 0.28)
		Sfx.play("swoosh", -8.0, 1.5)
	if blocked:
		Sfx.play("blocked")
		if _shield_fx == null or not _shield_fx.is_up():
			fx.burst(Vector3(_squad_x, 1.6, -2.2), Color("9fc6ff"), 16, 6.0, 0.2, 0.4)
	elif lost > 0:
		Sfx.play("hurt", -3.0)
		_add_loss(lost, false, String(CAUSE_ICON.get(kind, "")))
		var near: Array = []
		for p in pts:
			near.append(Vector3((p as Vector3).x, 0, (p as Vector3).z))
		_sync_allies(Vector3(_squad_x, 0, 0), near)


## Removes the pending threat(s) of attack `id` (or the oldest of `kind` on `lane` when the id
## is not known) and hides the lanes' marks it held.
func _drop_threat(id: int, kind: String, lane: int) -> void:
	var gone := false
	for i in range(_threats.size() - 1, -1, -1):
		var t: Dictionary = _threats[i]
		if int(t.get("id", -2)) == id:
			_threats.remove_at(i)
			gone = true
	if not gone:
		for i in _threats.size():
			var t: Dictionary = _threats[i]
			if int(t["lane"]) == lane and t["kind"] == kind:
				_threats.remove_at(i)
				break


## When a telegraphed attack lands, in sim seconds. The interface's land_t is the sim's clock
## at the landing; a small value (below the clock) is read as seconds from now.
func _land_time(e: Dictionary) -> float:
	var t := float(e.get("land_t", e.get("t", 1.0)))
	return t if t >= sim.time - 0.05 else sim.time + t


## Every pending telegraph and its marks go (a revive, the finish, a loss): nothing pending is
## ever shown landing after them.
func _clear_threats() -> void:
	_threats.clear()
	if cues != null:
		cues.clear()
	for z in _zones:
		(z["node"] as Node3D).visible = false
		z["fill"] = 0.0
		z["flash"] = 0.0
	for l in _lasers:
		l.visible = false
	if _tele_ring != null:
		_tele_ring.visible = false
	for c in _crates:
		if float(c["gone"]) < 0.0 and float(c["land"]) > sim.time:
			c["gone"] = sim.time
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
	for id in _hordes:
		(_hordes[id] as Dictionary)["strike"] = 0.0   # a pushed-back gang owes no charge
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
	var beam := _laser_mesh()
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
	# The countdown ring over the squad (the mark's honest countdown, where the eye already is).
	_tele_ring = MeshInstance3D.new()
	var rp := QuadMesh.new()
	rp.size = Vector2(1.5, 1.5)
	_tele_ring.mesh = rp
	_tele_ring_mat = ShaderMaterial.new()
	_tele_ring_mat.shader = GateRowView.ARC
	_tele_ring_mat.set_shader_parameter("track", Color(1, 1, 1, 0.25))
	_tele_ring_mat.set_shader_parameter("inner", 0.62)
	_tele_ring_mat.set_shader_parameter("outer", 0.9)
	_tele_ring_mat.render_priority = 2
	_tele_ring.material_override = _tele_ring_mat
	_tele_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tele_ring.visible = false
	add_child(_tele_ring)


## A district hazard begins (review v2.1): uptown's helicopter flies in and hovers up the street.
func _on_hazard_start(e: Dictionary) -> void:
	if String(e.get("kind", "")) != "chopper":
		return
	var node := _chopper_node()
	node.position = Vector3(8.0, CHOPPER_Y + 3.0, CHOPPER_Z - 25.0)
	add_child(node)
	_choppers[int(e["id"])] = {"node": node, "x": 0.0, "leave": false, "t": 0.0}
	_sfx("boss_roar", "swoosh", -10.0, 1.8)


## Falling containers and hovering helicopters, on the street's clock.
func _update_hazards(d: float) -> void:
	for i in range(_crates.size() - 1, -1, -1):
		var c: Dictionary = _crates[i]
		var node: Node3D = c["node"]
		if float(c["gone"]) >= 0.0 and sim.time >= float(c["gone"]):
			node.queue_free()
			_crates.remove_at(i)
			continue
		var span := maxf(float(c["land"]) - float(c["start"]), 0.05)
		var u := clampf((sim.time - float(c["start"])) / span, 0.0, 1.0)
		# Hangs and sways for the first part of the warning, then drops (accelerating).
		var drop := clampf((u - 0.45) / 0.55, 0.0, 1.0)
		node.position.y = lerpf(CRANE_Y, 0.7, drop * drop)
		node.rotation.z = 0.12 * sin(_anim_t * 3.0) * (1.0 - drop)
	for id in _choppers.keys():
		var ch: Dictionary = _choppers[id]
		var node: Node3D = ch["node"]
		ch["t"] = minf(float(ch["t"]) + d * 0.8, 1.0)
		var want := Vector3(float(ch["x"]), CHOPPER_Y + 0.4 * sin(_anim_t * 2.2), CHOPPER_Z)
		if ch["leave"]:
			want = Vector3(-14.0, CHOPPER_Y + 6.0, CHOPPER_Z - 30.0)
		node.position = node.position.lerp(want, clampf(d * 2.5, 0.0, 1.0))
		node.rotation = Vector3(0.18, PI + 0.25 * signf(want.x - node.position.x), 0.0)
		var rotor: Node3D = node.get_child(0)
		rotor.rotation.y += d * 40.0
		if ch["leave"] and node.position.distance_to(want) < 2.0:
			node.queue_free()
			_choppers.erase(id)


## A shipping container (red-orange, ribbed) for the docks' crane drop.
func _crate_node() -> Node3D:
	var n := Node3D.new()
	n.add_child(_part(Vector3(2.2, 1.3, 1.3), Color("c4472b"), Vector3.ZERO))
	for k in 5:
		n.add_child(_part(Vector3(0.08, 1.36, 1.36), Color("8f2f1c"), Vector3(-0.9 + 0.45 * k, 0, 0)))
	n.add_child(_part(Vector3(0.06, 4.0, 0.06), Color("2a2d33"), Vector3(0, 2.6, 0)))   # the cable
	n.add_child(_part(Vector3(0.4, 0.3, 0.2), Color("f2c230"), Vector3(0, 0.8, 0)))     # the hook
	return n


## A dark attack helicopter: body, cockpit glass, tail boom, stub wings and a rotor (child 0).
func _chopper_node() -> Node3D:
	var n := Node3D.new()
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.0, 0)
	rotor.add_child(_part(Vector3(7.0, 0.06, 0.32), Color(0.12, 0.12, 0.14), Vector3.ZERO))
	rotor.add_child(_part(Vector3(0.32, 0.06, 7.0), Color(0.12, 0.12, 0.14), Vector3.ZERO))
	n.add_child(rotor)
	n.add_child(_part(Vector3(1.5, 1.2, 3.0), Color("4a5260"), Vector3.ZERO))
	# A blinking red light and a searchlight down onto the lane it hovers over (it reads at night).
	var red := MeshInstance3D.new()
	red.mesh = _box_mesh(Vector3(0.3, 0.3, 0.3))
	red.material_override = _mat(Color(1.0, 0.1, 0.08), true)
	red.position = Vector3(0, -0.7, 0.9)
	n.add_child(red)
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.25
	cone.bottom_radius = 1.6
	cone.height = CHOPPER_Y
	beam.mesh = cone
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1.0, 0.95, 0.7, 0.22)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, -CHOPPER_Y * 0.5, 0)
	n.add_child(beam)
	n.add_child(_part(Vector3(1.2, 0.8, 1.0), Color("7fb8e6"), Vector3(0, 0.1, 1.5)))
	n.add_child(_part(Vector3(0.35, 0.4, 3.6), Color("2b2f36"), Vector3(0, 0.25, -3.0)))
	n.add_child(_part(Vector3(0.1, 1.0, 0.7), Color("2b2f36"), Vector3(0, 0.75, -4.6)))
	n.add_child(_part(Vector3(3.0, 0.12, 0.6), Color("1d2026"), Vector3(0, -0.15, 0.2)))
	n.add_child(_part(Vector3(0.3, 0.3, 1.0), Color("6b6f78"), Vector3(1.4, -0.35, 0.3)))
	n.add_child(_part(Vector3(0.3, 0.3, 1.0), Color("6b6f78"), Vector3(-1.4, -0.35, 0.3)))
	n.add_child(_part(Vector3(1.3, 0.08, 0.08), Color("1d2026"), Vector3(0, -0.85, 0.6)))
	return n


## A sniper's laser beam: a box along -z that tapers from LASER_FAR_W (at +z, his end) to
## LASER_NEAR_W (at -z, the lane), so it reads 50 m up the street without a slab at the squad.
func _laser_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f := LASER_FAR_W * 0.5
	var n := LASER_NEAR_W * 0.5
	var v := [Vector3(-n, -n, -0.5), Vector3(n, -n, -0.5), Vector3(n, n, -0.5), Vector3(-n, n, -0.5),
		Vector3(-f, -f, 0.5), Vector3(f, -f, 0.5), Vector3(f, f, 0.5), Vector3(-f, f, 0.5)]
	for q in [[0, 3, 2, 1], [5, 6, 7, 4], [4, 7, 3, 0], [1, 2, 6, 5], [3, 7, 6, 2], [4, 0, 1, 5]]:
		st.add_vertex(v[q[0]])
		st.add_vertex(v[q[1]])
		st.add_vertex(v[q[2]])
		st.add_vertex(v[q[0]])
		st.add_vertex(v[q[2]])
		st.add_vertex(v[q[3]])
	return st.commit()


## Draws the pending telegraphs: per lane the most urgent one's mark (its countdown on the sim's
## clock, so it waits with a paused or held street), a short white flash where one landed, and
## each aiming sniper's laser from his figures to the lane he aims at.
func _update_telegraphs(d: float) -> void:
	_update_hazards(d)
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
	# The countdown ring over the squad: the most urgent mark on the lane the squad stands in.
	var mine: Dictionary = {}
	var here := clampi(sim.squad_lane(), 0, 2)
	for th in _threats:
		if int(th["lane"]) == here and (mine.is_empty() or float(th["land"]) < float(mine["land"])):
			mine = th
	_tele_ring.visible = not mine.is_empty() and _state == "play"
	if _tele_ring.visible:
		var span0 := maxf(float(mine["land"]) - float(mine["start"]), 0.05)
		var left := 1.0 - clampf((sim.time - float(mine["start"])) / span0, 0.0, 1.0)
		_tele_ring_mat.set_shader_parameter("fill", left)
		_tele_ring_mat.set_shader_parameter("color", THREAT_TINT.get(mine["kind"], Color(1.0, 0.2, 0.1)))
		_tele_ring_mat.set_shader_parameter("blink", (0.25 + 0.25 * sin(_anim_t * (12.0 + 26.0 * (1.0 - left)))) if left < 0.4 else 0.0)
		_tele_ring.position = Vector3(_squad_x, RING_Y, 0.2)
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			# Faces the camera (a vertical ring over the heads).
			_tele_ring.global_basis = Basis.looking_at(_tele_ring.global_position - cam.global_position, Vector3.UP)
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
	if hv.get("lt", false):
		return float(Game.units.get("lieutenant", {}).get("scale", LT_SCALE))
	return BOSS_SCALE


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

## The squad's x follows the finger while one steers, else its lane's centre.
func _steer(d: float) -> void:
	var lane_target: float = _steer_x if _touching else LANE_X[sim.lane]
	if demo:
		_squad_x = move_toward(_squad_x, lane_target, 1.0)
	else:
		_squad_x = steer_toward(_squad_x, lane_target, d)


func _update_visuals(d: float, steered := false) -> void:
	if not steered:
		_steer(d)
	var shift := _squad_x - _drawn_x
	_drawn_x = _squad_x
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
	# Waiting to start, the squad stands; on the clear run its legs keep up with the street.
	var moving := demo or (_state == "play" and started) or _state == "done"
	_run_t += d * (maxf(sim.S / maxf(sim.S_base, 0.01), 1.0) if clear_run and _state == "play" else 1.0)

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
		# Nobody fires before the level starts, nor on the clear run to the stash (owner
		# 2026-11-13: nobody is left to shoot at).
		if not demo and _state == "play" and started and not clear_run:
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
			(_crowds[a["kind"]] as Crowd).push(Transform3D(basis.scaled(Vector3.ONE * (1.0 if a["kind"] == "hero" else troop_k)), pos), "run", (_run_t + ph) * RUN_SPEED, float(a["flash"]))
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
		# The crowd closes ranks (spec v2.1 §1.4): when a walking gang's front row falls the sim
		# steps the rows behind up at once; drawn, they catch up over a moment (`dz`).
		var kr := LevelSim.killed_rows(h)
		if kr > int(hv.get("kr", 0)) and not h["stopped"]:
			hv["dz"] = maxf(float(hv.get("dz", 0.0)) - (kr - int(hv.get("kr", 0))) * float(h["row_gap"]), -6.0)
		hv["kr"] = kr
		hv["dz"] = move_toward(float(hv.get("dz", 0.0)), 0.0, d * 9.0)
		while offs.size() > want:
			var o: Vector3 = offs.pop_front()
			var p := _fig_pos(hv, o)
			if float(hv.get("strike", 0.0)) >= float(hv["per"]) * 0.5:
				# A striker: it charges into the squad (the clash), it does not just drop.
				hv["strike"] = float(hv["strike"]) - float(hv["per"])
				_charging.append({"kind": hv["kind"], "pos": p, "phase": o.y, "shielded": bool(hv.get("strike_sh", false)),
					"dx": clampf(o.x * 0.35, -1.6, 1.6)})
				continue
			_dying.append({"kind": hv["kind"], "pos": p, "t": 0.0, "foe": true,
				"basis": Basis(Vector3.UP, PI).scaled(Vector3.ONE * esc * crowd_scale(offs.size() + 1))})
			fx.puff(p)
		if hv.has("prop"):
			var shown := not offs.is_empty() and int(h["count"]) > 0
			(hv["prop"] as Node3D).visible = shown
			(hv["aura"] as Node3D).visible = shown
			if shown:
				var at := _fig_pos(hv, offs[0])
				var k := esc * crowd_scale(offs.size())
				var hat: Node3D = hv["prop"]
				hat.position = at + Vector3(0, CHAR_H * k * 0.95, 0)
				hat.scale = Vector3.ONE * k
				var aura: Node3D = hv["aura"]
				aura.position = at + Vector3(0, 0.06, 0)
				aura.scale = Vector3(k * 0.55, 0.15, k * 0.55) * (1.0 + 0.06 * sin(_anim_t * 6.0))
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
		# In a clash the front two rows throw punches into the squad (spec v2.1 §1.4).
		var punch_z := INF
		if h["melee"] and not hv["bossy"] and not offs.is_empty():
			hv["clash_t"] = maxf(float(hv.get("clash_t", 0.0)) - d, 0.0)
			punch_z = (offs[0] as Vector3).z + float(h["row_gap"]) * 1.5
		_squash(hv)
		var plen := Crowd.clip_length("punch")
		var drawn := 0
		for o in offs:
			var ok := false
			if o.z <= punch_z:
				ok = crowd.push(Transform3D(face, _fig_pos(hv, o)), "punch", fmod(_anim_t * 1.5 + o.y * plen, plen), flash)
			else:
				ok = crowd.push(Transform3D(face, _fig_pos(hv, o)), clip, (_anim_t + o.y * 3.0) * speed, flash)
			if ok:
				drawn += 1
		hv["drawn"] = drawn
		hv["gun_kick"] = maxf(float(hv.get("gun_kick", 0.0)) - d * 3.0, 0.0)
		if cues.focus_id == int(id) and not offs.is_empty():
			var f0 := _fig_pos(hv, offs[0])
			var span := minf(_fig_pos(hv, offs[0]).z - _fig_pos(hv, offs.back()).z, 4.0)
			cues.focus_at(Vector3(clampf(f0.x * 0.3, -1.5, 1.5), CHAR_H * ENEMY_SCALE * 0.55, f0.z - span * 0.5),
				3.2 if hv["bossy"] else 5.0)
		if hv.has("bar"):
			_update_boss_bar(hv, d)
			if _state == "play" and float(hv.get("gun_t", 0.0)) > 0.0 and int(h["count"]) > 0:
				# His gun beside his bar (right of it; the crown is on its left) for a beat after
				# each shot, never over his health number or his body.
				hv["gun_t"] = maxf(float(hv["gun_t"]) - d, 0.0)
				var bar: Node3D = hv["bar"]
				var bright := cam.global_basis.x if cam else Vector3.RIGHT
				cues.gun(int(id), bar.position + bright * 2.5 * bar.scale.x, bar.scale.x * 0.7, float(hv["gun_kick"]))
			continue
		var lab: Label3D = hv["label"]
		var lz := float(h["z"])
		if not offs.is_empty():
			lz = (_fig_pos(hv, offs[0]).z + _fig_pos(hv, offs.back()).z) * 0.5
		# Grows with distance (like the boss bar) so a far gang's count still reads.
		var ls := 1.0
		if cam:
			ls = clampf(cam.global_position.distance_to(Vector3(0, 0, lz)) / 18.0, 1.0, 2.2)
		lab.scale = Vector3.ONE * ls
		var ly := (4.6 if hv["kind"] == "brute" else 3.6) * ENEMY_SCALE * 0.85 + 0.3 * (ls - 1.0)
		var stacked := false
		# Escorts walking with a boss: their count sits above the boss's bar, never on his chest.
		# A gang walking ahead of a boss keeps its count low, just over its own heads, so the
		# boss behind it stays in sight (spec v2 §5).
		for bid in _hordes:
			var bv: Dictionary = _hordes[bid]
			if not bv.has("bar") or not (bv["bar"] as Node3D).visible:
				continue
			if absf(float(bv["h"]["z"]) - lz) < 7.0:
				# Stacked over the bar at the bar's own depth (review v2.1: at the escort's depth,
				# nearer the camera, its count slid down over the boss's health number).
				var bar_top: float = (bv["bar"] as Node3D).position.y + 0.4 * (bv["bar"] as Node3D).scale.y
				ly = maxf(ly, bar_top + 0.75 * ls)
				lz = (bv["bar"] as Node3D).position.z
				stacked = true
			elif float(bv["h"]["z"]) < lz and int(bv["h"]["count"]) > 0:
				ly = minf(ly, CHAR_H * ENEMY_SCALE * crowd_scale(offs.size()) + 0.45 * ls)
				# Seen from above and behind the squad, that can still land on the boss's
				# body on screen: then the count goes above the boss's bar instead.
				if cam and _covers_boss(cam, Vector3(0, ly, lz), bv):
					var bar: Node3D = bv["bar"]
					ly = bar.position.y + 0.4 * bar.scale.y + 0.7 * ls
					lz = bar.position.z
		lab.position = Vector3(0, ly, lz)
		# Stacked over a boss bar it is drawn over everything like the bar's own number (the HQ
		# far behind could otherwise sort over it).
		lab.no_depth_test = stacked
		lab.render_priority = 12 if stacked else 2
		lab.outline_render_priority = 11 if stacked else 1
		var shown := LevelSim.boss_hp(h) if hv.get("leader", false) else int(h["count"])
		if shown != int(hv["shown"]):
			hv["shown"] = shown
			lab.text = NumFormat.fmt(shown)
			hv["lab_w"] = GateRowView.text_w(lab, lab.text)
		# Closing in while the squad's fire goes elsewhere (a red gate, an obstacle): the count
		# pulses so the threat behind the gate is visible before it arrives.
		var ignored: bool = _state == "play" and not is_same(sim.target_ref, h) and LevelSim.front_z(h) > -18.0 and not h["melee"]
		hv["fire_t"] = maxf(float(hv.get("fire_t", 0.0)) - d, 0.0)
		if ignored:
			var p := 0.5 + 0.5 * sin(_anim_t * 16.0)
			lab.modulate = Color("ff6b6b").lerp(Color(1, 1, 1), p) if int(h["armour"]) == 0 else Color("b8c7d9").lerp(Color("ff3b3b"), p)
			lab.scale = Vector3.ONE * ls * (1.0 + 0.15 * p)
		else:
			lab.modulate = Color("ff6b6b") if int(h["armour"]) == 0 else Color("b8c7d9")
		if float(hv["fire_t"]) > 0.0:
			# Review v2.1: the count flashes red-hot when the gang fires (that gang is shooting me).
			var k := float(hv["fire_t"]) / 0.35
			lab.modulate = lab.modulate.lerp(Color(1.0, 0.12, 0.05), k)
			lab.scale = Vector3.ONE * ls * (1.0 + 0.25 * k)
		_update_reach(hv, lab.position, ls)
		if _state == "play" and LevelSim.fires_back(h):
			# Owner play-test 2026-11-13: a gang whose guns reach the squad wears a bright gun
			# beside its count (it kicks with each volley): that is who is shooting.
			var right := cam.global_basis.x if cam else Vector3.RIGHT
			var gw := LossCues.GUN_W * ls
			cues.gun(int(id), lab.position - right * (float(hv.get("lab_w", 1.0)) * lab.scale.x * 0.5 + gw * LossCues.BADGE_K * 0.55),
				ls, float(hv["gun_kick"]))

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
		# A striker falls at the squad's front line, where the two crowds meet (spec v2.1 §1.4).
		var goal := Vector3(_squad_x + float(c.get("dx", 0.0)), 0, -0.6 if c["shielded"] else -0.35)
		var p: Vector3 = (c["pos"] as Vector3).move_toward(goal, d * 12.0)
		c["pos"] = p
		c["t"] = float(c.get("t", 0.0)) + d
		var bounced: bool = c["shielded"] and _shield_fx.is_up()
		if (_shield_fx.touches(p + Vector3(0, 0.9, 0), 0.3) if bounced else p.distance_to(goal) < (2.6 if c["shielded"] else 0.8)) or float(c["t"]) > 0.9:
			if bounced:
				_shield_hit(p + Vector3(0, 0.9, 0), Vector3(_squad_x, 0.9, 0.6))
			fx.puff(p)
			_dying.append({"kind": c["kind"], "pos": p, "t": 0.0, "foe": true, "basis": Basis(Vector3.UP, PI).scaled(Vector3.ONE * ENEMY_SCALE)})
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
		# A gang member's body fades as the street carries it into the squad (a clash drops many
		# right at the front; ridden on towards the camera they loomed over the squad).
		var foe_fade := clampf((p.z - 0.2) / 1.0, 0.0, 1.0) if dd.get("foe", false) else 0.0
		if t > BODY_TIME + 0.5 or p.z > 4.0 or foe_fade >= 1.0:
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
		if foe_fade > 0.0:
			flash = minf(flash, -foe_fade)
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
	cues.squad_at = Vector3(_squad_x, 1.1, -0.9)
	cues.update(d, cam)


func _fig_pos(hv: Dictionary, o: Vector3) -> Vector3:
	var h: Dictionary = hv["h"]
	var oz := o.z
	var sq := float(hv.get("sq", 1.0))
	if sq < 1.0:
		var o0 := float(hv.get("sq0", 0.0))
		oz = o0 + maxf(o.z - o0, 0.0) * sq - float(hv.get("sq_out", 0.0))
	var z := float(h["z"]) + float(hv.get("dz", 0.0)) - oz
	if sq < 1.0:
		z = maxf(z, sim.stash_z() + STASH_PAD)
	var k := clampf((z + 16.0) / 14.0, 0.0, 1.0)
	var x := lerpf(o.x, _squad_x + o.x * 0.45, k)
	return Vector3(x, 0, z)


## Owner play-test 2026-11-13: a gang is never drawn inside or behind the stash. When its
## figures (front to back, a metre a row) would reach past the stash's front face, its rows
## close up in front of the face instead (`sq` < 1: the share of their depth they keep, from the
## front figure `sq0`). A gang whose front is still behind the face (a walking gang that came out
## late: LevelSim keeps its schedule) is inside the stash: it is drawn coming out of the door, a
## block STASH_OUT m deep at most, moved `sq_out` m forward. A gang that stops to attack always
## stands in front of the face (LevelSim.hold_m, stop_line).
func _squash(hv: Dictionary) -> void:
	hv["sq"] = 1.0
	hv["sq_out"] = 0.0
	var offs: Array = hv["offs"]
	if offs.is_empty() or not _finish_live or sim.finish_at <= 0.0:
		return
	var o0 := (offs[0] as Vector3).z
	var depth := maxf((offs.back() as Vector3).z - o0, 0.0)
	var front := float(hv["h"]["z"]) + float(hv.get("dz", 0.0)) - o0
	var face := sim.stash_z() + STASH_PAD
	var room := front - face
	var need := minf(STASH_OUT, depth)
	if room >= depth or (depth <= 0.0 and room >= 0.0):
		return
	hv["sq0"] = o0
	if room < need:
		hv["sq_out"] = need - room   # still (partly) inside: the block at the door
		room = need
	hv["sq"] = clampf(room / depth, 0.0, 1.0) if depth > 0.0 else 0.0


## Figures of gang `id` drawn on the last frame (tests: a living gang is always on screen).
func drawn_figures(id: int) -> int:
	return int((_hordes.get(id, {}) as Dictionary).get("drawn", 0))


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


## The reach bar under a gang's count (review v2.1): the share of the squad that the people who
## would reach it are worth, against the squad's firepower now (LevelSim.reach_estimate); full
## and pulsing when they would take the whole squad. Shown in play only.
func _update_reach(hv: Dictionary, at: Vector3, ls: float) -> void:
	if not hv.has("reach_bg"):
		return
	var bg: MeshInstance3D = hv["reach_bg"]
	var fill: MeshInstance3D = hv["reach_fill"]
	var h: Dictionary = hv["h"]
	var show := _state == "play" and int(h["count"]) > 0 and (hv["label"] as Label3D).visible
	bg.visible = show
	if not show:
		fill.visible = false
		return
	var reach := sim.reach_estimate(h)
	var danger := clampf(float(reach) * float(h["power"]) / maxf(float(sim.squad.total()), 1.0), 0.0, 1.0)
	var pos := at + Vector3(0, -0.62 * ls, 0)
	bg.position = pos
	bg.scale = Vector3.ONE * ls
	fill.visible = danger > 0.0
	if fill.visible:
		var w := REACH_SIZE.x * ls
		fill.scale = Vector3(danger * ls, ls * 0.8, ls)
		fill.position = pos + Vector3(-w * 0.5 + w * danger * 0.5, 0, 0.01)
		var mat := fill.material_override as StandardMaterial3D
		var pulse := (0.5 + 0.5 * sin(_anim_t * 14.0)) if danger >= 1.0 else 1.0
		mat.albedo_color = Color(MINUS_RED, 0.55 + 0.45 * pulse)


func _free_horde(id: int) -> void:
	var hv: Dictionary = _hordes.get(id, {})
	if hv.is_empty():
		return
	(hv["label"] as Node).queue_free()
	(hv["sub"] as Node).queue_free()
	if hv.has("bar"):
		(hv["bar"] as Node).queue_free()
	for k in ["reach_bg", "reach_fill", "prop", "aura"]:
		if hv.has(k):
			(hv[k] as Node).queue_free()
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
	for n in cues.warm_nodes(_warm_at + Vector3(-1.0, 0.5, -2.0)):
		add_child(n)
		_warm.append(n)
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
	_hq.position = Vector3(0, 0, -(sim.stash_front + STASH_FACE))
	_finish.add_child(_hq)
	# (No bar over it, owner 2026-11-13: a full red "life bar" on the stash that nothing ever
	# drained, left over from the v1 HQ, read as health the squad had to shoot down.)


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
