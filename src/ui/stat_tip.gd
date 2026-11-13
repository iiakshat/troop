class_name StatTip
extends Control
## Tap-to-explain for stat icons (owner play-test 2026-11-13: "what all of it means doesn't
## really understand"). Tapping a stat icon in the Codex, the Armory or a rank card pops a small
## bubble next to it: the icon big with its number, then one or two example rows drawn with
## icons and numbers only (no words): damage 3 ▸ heart -3, a second ▸ 2 hits, damage × rate =
## the lightning, armour halves a hit and the pierce icon does not, splash hits 5 thugs...
## A tap anywhere closes it. rows() is pure and tested; attach() wires a control.
##
## Tokens in a row: "@name" draws that icon, anything else is a short number / symbol label.

const ICON := 50
const FONT := 38
const DRAG := 14.0   ## a press that travels further is a scroll drag, not a tap

var key := ""
var ctx: Dictionary = {}
var anchor: Rect2 = Rect2()     # the tapped icon's rect in this control's parent space
var _bubble: PanelContainer


## Makes `c` show the bubble for `stat_key` when tapped (ctx: the numbers of that row, e.g.
## {"dmg": 3, "rate": 2, "hits": 1}, or a Callable returning that when the numbers change, as
## in the Armory). A drag that starts on it still scrolls its list.
static func attach(c: Control, stat_key: String, context: Variant = {}) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_meta("stat_tip", stat_key)
	c.gui_input.connect(_on_input.bind(c, stat_key, context))
	return c


static func _on_input(ev: InputEvent, c: Control, stat_key: String, context: Variant) -> void:
	if not (ev is InputEventMouseButton) or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mb := ev as InputEventMouseButton
	var g := c.get_global_transform() * mb.position
	if mb.pressed:
		c.set_meta("tip_down", g)
		return
	if not c.has_meta("tip_down"):
		return
	var down: Vector2 = c.get_meta("tip_down")
	c.remove_meta("tip_down")
	if g.distance_to(down) <= DRAG:
		show_for(c, stat_key, context.call() if context is Callable else context)


## Opens the bubble for `c` over the whole screen (on the topmost Control above it).
static func show_for(c: Control, stat_key: String, context := {}) -> StatTip:
	var host: Control = c
	while host.get_parent() is Control:
		host = host.get_parent() as Control
	for old in host.get_children():
		if old is StatTip:
			old.queue_free()
	var t := StatTip.new()
	t.key = stat_key
	t.ctx = context
	t.anchor = c.get_global_rect()
	host.add_child(t)
	c.tree_exiting.connect(t.queue_free, CONNECT_ONE_SHOT)   # its panel closed under it
	RetentionPanel.sfx(["tap", "click"], -6.0)
	return t


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override("panel", RetentionPanel.box(Color("1d2b55"), 22, 5, UiKit.INK, 16))
	add_child(_bubble)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(col)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	for tok in header(key, ctx):
		head.add_child(_token(String(tok), 96, 60))
	for r in rows(key, ctx):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var strip := PanelContainer.new()
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_theme_stylebox_override("panel", RetentionPanel.box(Color("3b6fd1"), 16, 4, UiKit.INK, 8))
		strip.add_child(row)
		col.add_child(strip)
		for tok in r:
			row.add_child(_token(String(tok), ICON, FONT))
	_place.call_deferred()


func _place() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var sz := _bubble.get_combined_minimum_size()
	_bubble.size = sz
	var inv := get_global_transform().affine_inverse()
	var a := Rect2(inv * anchor.position, anchor.size)
	var x := clampf(a.get_center().x - sz.x * 0.5, 16.0, maxf(vp.x - sz.x - 16.0, 16.0))
	var y := a.position.y - sz.y - 12.0
	if y < 16.0:
		y = a.end.y + 12.0
	y = clampf(y, 16.0, maxf(vp.y - sz.y - 16.0, 16.0))
	_bubble.position = Vector2(x, y)
	UiKit.pop(_bubble, 0.6)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		accept_event()
		queue_free()


static func _token(tok: String, icon_px: int, font: int) -> Control:
	if tok.begins_with("@"):
		var ic := RetentionPanel.icon_safe(tok.substr(1), icon_px)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return ic
	var col := UiKit.YELLOW if tok in ["▸", "=", "×", ">"] else (UiKit.RED if tok.begins_with("-") else Color.WHITE)
	var l := UiKit.label(tok, font, col, 9)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


# ---------------------------------------------------------------- content (pure, tested)

static func n(v: Variant) -> String:
	return CodexPanel.number(float(v))


## The bubble's head: the tapped icon (ctx "icon", else the key's own) big, with the row's own
## number when it has one.
static func header(k: String, c: Dictionary) -> Array:
	var ic := "@" + String(c["icon"]) if c.has("icon") else icon_of(k)
	match k:
		"damage":
			return [ic, n(c.get("dmg", 1))] if c.has("dmg") else [ic]
		"rate":
			return [ic, n(c.get("rate", 1)) + "/s"] if c.has("rate") else [ic]
		"power":
			return [ic, Economy.fmt_power(float(c.get("dps", 0)))] if c.has("dps") else [ic]
		"heart", "speed":
			return [ic, n(c.get("v", 1))] if c.has("v") else [ic]
		"melee":
			return ["@" + String(c.get("who", "thug")), "-" + n(c.get("v", 1)), "@person"]
	if c.has("now"):
		return [ic, String(c["now"])]
	return [ic]


## The icon a stat key is drawn with.
static func icon_of(k: String) -> String:
	match k:
		"damage": return "@damage"
		"rate": return "@fire_rate"
		"power": return "@power"
		"pierce": return "@armour_pierce"
		"splash": return "@bomb"
		"burst": return "@gang_split"
		"toughest": return "@aim"
		"tap": return "@hand"
		"melee": return "@person"
		"shooter": return "@gang_fire"
	return "@" + k


## Example rows for a stat key, icons and numbers only. ctx carries the row's own numbers.
static func rows(k: String, c: Dictionary) -> Array:
	var dmg := float(c.get("dmg", 3))
	match k:
		"damage":
			# One hit takes that many hearts off an enemy.
			return [["@damage", n(dmg), "▸", "@thug", "@heart", "-" + n(dmg)]]
		"rate":
			# Hits in one second.
			return [["@clock", "1s", "▸", "@damage", "×" + n(c.get("rate", 2))]]
		"power":
			# Damage x hits per second (x enemies each hit, for bursts and splash) = the lightning.
			var r: Array = ["@damage", n(dmg), "×", "@fire_rate", n(c.get("rate", 2)) + "/s"]
			var hits := float(c.get("hits", 1))
			if hits > 1.0:
				r.append_array(["×", "@thug", n(hits)])
			return [r, ["=", "@power", Economy.fmt_power(float(c.get("dps", dmg * float(c.get("rate", 2)) * maxf(hits, 1.0))))]]
		"pierce":
			# Armour halves a hit; a piercing hit keeps it all (and passes riot shields).
			var d := maxf(dmg, 2.0)
			return [["@armour", "@damage", n(d), "▸", n(d / 2.0)],
				["@armour_pierce", "@damage", n(d), "▸", n(d)]]
		"armour":
			var d2 := maxf(dmg, 2.0)
			return [["@damage", n(d2), "▸", "@armour", n(d2 / 2.0)],
				["@armour_pierce", n(d2), "▸", "@armour", n(d2)]]
		"splash":
			return [["@damage", "▸", "@thug", "×" + n(c.get("hits", 5))]]
		"burst":
			return [["@damage", "▸", "@thug", "×" + n(c.get("hits", 2))]]
		"toughest":
			return [["@aim", "▸", "@boss", ">", "@brute", ">", "@thug"]]
		"tap":
			# Idle the hero throws at auto_rate of his rate; steady tapping holds it full.
			return [["@hand", "0", "▸", "@fire_rate", "%d%%" % int(round(float(c.get("auto", 0.4)) * 100.0))],
				["@hand", n(c.get("taps", 4)) + "/s", "▸", "@fire_rate", "100%"]]
		"heart":
			return [["@damage", "×" + n(c.get("v", 1)), "▸", "@thug", "@heart", "0"]]
		"speed":
			return [["@clock", "1s", "▸", n(c.get("v", 1)) + "m"]]
		"melee":
			return [["@" + String(c.get("who", "thug")), "▸", "@person", "-" + n(c.get("v", 1))], ["@shield", "▸", "@person", "-0"]]
		"fire":
			return [["@molotov", "▸", "@fire", "@person", "-" + n(c.get("v", 2))], ["@swipe", "▸", "@person", "-0"]]
		"shooter":
			return [["@gang_fire", "▸", "@person", "-" + n(c.get("v", 1))], ["@shield", "▸", "@person", "-0"]]
		"riot":
			return [["@riot", "@heart", "+" + n(c.get("v", 4))], ["@armour_pierce", "▸", "@riot", "▸", "@thug"]]
		"boss_crown":
			return [["@boss", "@heart", n(c.get("v", 360))]]
	if c.has("lo") and c.has("hi"):
		# An Armory handling stat: what the track does from its first step to its last.
		return [["@" + k.trim_prefix("@"), String(c["lo"]), "▸", String(c["hi"]), "@upgrade"]]
	return []
