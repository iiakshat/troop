class_name Squad
extends RefCounted
## The player's army as a head count per rank. Pure logic: no nodes, unit tested.
##
## Rules that keep the arithmetic honest (what the player sees is what happens):
## - total() is what the squad counter shows.
## - ×k makes total() exactly k times bigger: every recruit brings k-1 more of the same
##   rank, and the hero (who can't be copied) brings k-1 constables.
## - Losses take the lowest rank first; the hero falls last, and that ends the level.
## - The squad never grows past `cap` (shown as a bar under the counter); gains that would
##   overflow it are dropped, lowest rank first.

## Lowest rank first. The hero is always last.
const LOSS_ORDER := ["constable", "sergeant", "inspector", "swat", "sniper", "commando", "hero"]

## Which shooters a dps() call counts.
enum Fire { ALL, MAIN, SNIPE }

var counts: Dictionary = {"hero": 1, "constable": 0, "sergeant": 0, "inspector": 0,
	"swat": 0, "sniper": 0, "commando": 0}
var hero_weapon: String = ""
var cap := 0   # 0 = no limit
## Tap heat: the hero's knife (and a held weapon) fires at this share of its rate. LevelSim
## sets it from tap heat each tick; followers never use it.
var hero_rate := 1.0


func total() -> int:
	var t := 0
	for rank in counts:
		t += int(counts[rank])
	return t


func count(rank: String) -> int:
	return int(counts.get(rank, 0))


func hero_alive() -> bool:
	return count("hero") > 0


func add(rank: String, n: int) -> int:
	n = maxi(n, 0)
	if cap > 0:
		n = mini(n, maxi(cap - total(), 0))
	counts[rank] = count(rank) + n
	return n


func multiply(k: int) -> int:
	var before := total()
	if k <= 1:
		return 0
	for rank in counts.keys():
		if rank != "hero":
			counts[rank] = count(rank) * k
	counts["constable"] = count("constable") + count("hero") * (k - 1)
	_clamp()
	return total() - before


## Trims overflow above `cap`, lowest rank first.
func _clamp() -> void:
	if cap > 0 and total() > cap:
		lose(total() - cap)


## Removes up to n troops, lowest rank first. Returns how many were actually lost.
func lose(n: int) -> int:
	var left := maxi(n, 0)
	for rank in _loss_order():
		if left <= 0:
			break
		var take := mini(left, count(rank))
		counts[rank] = count(rank) - take
		left -= take
	return maxi(n, 0) - left


## LOSS_ORDER, plus any rank a config added that the list doesn't know (lost before the hero).
func _loss_order() -> Array:
	var order: Array = LOSS_ORDER.slice(0, LOSS_ORDER.size() - 1)
	for rank in counts:
		if not order.has(rank) and rank != "hero":
			order.append(rank)
	order.append("hero")
	return order


## Percent change of the whole squad, rounded down. Gains arrive as constables.
func apply_percent(pct: int) -> int:
	var amount := total() * absi(pct) / 100  # exact 64-bit integers, rounded down
	if pct >= 0:
		return add("constable", amount)
	return -lose(amount)


## ÷k, rounded down, never below the hero alone.
func divide(k: int) -> int:
	if k <= 1:
		return 0
	var target := maxi(total() / k, 1)
	return -lose(total() - target)


## Damage per second against one enemy type. `stats` is the effective ally table
## (after upgrades); each point of armour divides a hit (1 armour = half damage) unless the
## attacker pierces, so every hit still counts. `count` is how many enemies stand in the
## target group: SWAT bursts (`multi`) and launcher splash (`splash`) can't hit more enemies
## than there are. `which` picks the shooters: MAIN = everyone who fires down the lane,
## SNIPE = only the ones that pick the toughest target (`"target": "toughest"`).
func dps(stats: Dictionary, weapons: Dictionary, armour: int, hp := 1.0, enemies := 1 << 30, which := Fire.ALL) -> float:
	var sum := 0.0
	for rank in counts:
		var n := count(rank)
		if n <= 0 or not stats.has(rank) or not _counts_for(stats[rank], which):
			continue
		sum += n * hit_value(stats[rank], armour, hp, enemies) * _rate_of(rank)
	if which != Fire.SNIPE and hero_weapon != "" and hero_alive() and weapons.has(hero_weapon):
		sum += hit_value(weapons[hero_weapon], armour, hp, enemies) * hero_rate
	return sum


## Live firepower (spec v2 §12.4, the HUD's lightning number): damage per second against a
## plain unarmoured crowd, every rank at its best (bursts, splash and a sniper round's full
## damage count), the hero and a held weapon at the current tap rate (hero_rate).
func firepower(stats: Dictionary, weapons: Dictionary) -> float:
	var sum := 0.0
	for rank in counts:
		var n := count(rank)
		if n > 0 and stats.has(rank):
			sum += n * hit_value(stats[rank], 0, 1.0, 1 << 30, true) * _rate_of(rank)
	if hero_weapon != "" and hero_alive() and weapons.has(hero_weapon):
		sum += hit_value(weapons[hero_weapon], 0, 1.0, 1 << 30, true) * hero_rate
	return sum


## The part of dps() that comes from piercing attackers (passes riot shields).
func pierce_dps(stats: Dictionary, weapons: Dictionary, hp := 1.0, enemies := 1 << 30, which := Fire.ALL) -> float:
	var sum := 0.0
	for rank in counts:
		var n := count(rank)
		if n > 0 and stats.has(rank) and bool(stats[rank].get("pierce", false)) and _counts_for(stats[rank], which):
			sum += n * hit_value(stats[rank], 0, hp, enemies) * _rate_of(rank)
	return sum


func _rate_of(rank: String) -> float:
	return hero_rate if rank == "hero" else 1.0


## True when the squad has at least one living shooter that picks the toughest target.
func has_snipers(stats: Dictionary) -> bool:
	for rank in counts:
		if count(rank) > 0 and stats.has(rank) and is_sniper(stats[rank]):
			return true
	return false


static func is_sniper(unit: Dictionary) -> bool:
	return String(unit.get("target", "")) == "toughest"


static func _counts_for(unit: Dictionary, which: int) -> bool:
	match which:
		Fire.MAIN:
			return not is_sniper(unit)
		Fire.SNIPE:
			return is_sniper(unit)
	return true


## Damage per second of one `unit` against enemies with `hp` and `armour`. A unit with
## `"one_per_shot": true` (the sniper) can't kill more than the one enemy it hits: its
## damage per shot is capped at that enemy's hp, unless `nominal` (the Codex value line).
static func hit_value(unit: Dictionary, armour: int, hp := 1.0, enemies := 1 << 30, nominal := false) -> float:
	var dmg := float(unit.get("dmg", 1))
	if not bool(unit.get("pierce", false)):
		dmg = dmg / float(1 + maxi(armour, 0))
	if not nominal and bool(unit.get("one_per_shot", false)):
		dmg = minf(dmg, maxf(hp, 0.0))
	var multi := float(unit.get("multi", 1))
	if multi > 1.0 and hp > dmg:
		multi = 1.0
	var splash := float(unit.get("splash", 1))
	var hits := minf(multi * splash, float(maxi(enemies, 1)))
	return dmg * float(unit.get("rate", 1.0)) * maxf(hits, 1.0)


## How many constables one of `rank` is worth in damage per second, from config.
## With hp = 0 (default) it is the nominal Codex "= N" line: a crowd of unarmoured enemies,
## every rank at its best (bursts and splash count, a sniper round's full damage counts).
## Pass hp/armour/enemies for a specific target, e.g. a boss: (stats, "sniper", 360, 1, 1).
static func value_vs_constable(stats: Dictionary, rank: String, hp := 0.0, armour := 0, enemies := 1 << 30) -> float:
	if not stats.has(rank) or not stats.has("constable"):
		return 0.0
	var nominal := hp <= 0.0
	var h := 1.0 if nominal else hp
	var base := hit_value(stats["constable"], armour, h, enemies, nominal)
	if base <= 0.0:
		return 0.0
	return hit_value(stats[rank], armour, h, enemies, nominal) / base


# ---------------------------------------------------------------- formation
# The squad's shape on the road, shared by the sim (which troops an obstacle hits) and the
# view (where each figure stands). Slot 0 is the hero in front; the others spiral out behind
# him (sunflower pattern). A squad of `total` troops is drawn as `figures(total, cap)` slots,
# each carrying `slot_troops()` troops, so a 150-strong army is 72 figures wide, not 150.

## Figure scale for a crowd of n figures: troops a bit smaller than the hero (0.85),
## shrinking to 0.68 at 80+ so a huge army reads as a dense mob instead of a pile-up.
static func crowd_scale(n: int) -> float:
	return lerpf(0.85, 0.68, clampf((n - 20) / 60.0, 0.0, 1.0))


## Offset of slot `i` of `n` from the squad centre: x sideways, y = z (positive = behind).
## `max_half` (metres, 0 = none) caps how wide the formation gets, so a squad standing in the
## middle of its lane never brushes an obstacle in the next lane.
static func slot_offset(i: int, n: int, max_half := 0.0) -> Vector2:
	if i <= 0:
		return Vector2(0.0, -0.5)
	var j := i - 1
	var k := crowd_scale(n)
	var r := 0.4 * k * sqrt(j + 0.7)
	var a := j * 2.39996
	var radius := 0.4 * k * sqrt(maxf(n, 1))
	# A big squad packs narrower and deeper, so it stays on screen in an outer lane.
	var wide := lerpf(1.35, 0.95, clampf((n - 30) / 40.0, 0.0, 1.0))
	var deep := lerpf(0.5, 0.62, clampf((n - 30) / 40.0, 0.0, 1.0))
	if max_half > 0.0:
		var r_out := 0.4 * k * sqrt(maxf(n - 2, 0) + 0.7)
		wide = minf(wide, max_half / maxf(r_out, 0.001))
	return Vector2(cos(a) * r * wide, 1.1 + radius * 0.45 + sin(a) * r * deep)


## How many figures stand for `total` troops (at most `cap`, 0 = no limit).
static func figures(total: int, cap: int) -> int:
	return mini(total, cap) if cap > 0 else total


## Troops carried by slot `i` when `total` troops stand in `n` slots (exact: they sum to total).
static func slot_troops(i: int, n: int, total: int) -> int:
	if n <= 0:
		return 0
	return int((i + 1) * total / n) - int(i * total / n)


## Spatial hit: the slots whose figures overlap a footprint `half_w` metres either side of
## `ob_x` (figure radius `fig_r` included) when the squad stands at `squad_x`, nearest to the
## footprint's centre first, taking whole slots until `capacity` troops are lost.
## Returns {lost, slots (the slot indices hit), figures (n), overlap (troops inside)}.
static func footprint_hits(total: int, fig_cap: int, squad_x: float, ob_x: float, half_w: float,
		fig_r: float, capacity: int, max_half := 0.0) -> Dictionary:
	var n := figures(total, fig_cap)
	var inside: Array = []
	for i in n:
		var x := squad_x + slot_offset(i, n, max_half).x
		if absf(x - ob_x) <= half_w + fig_r:
			inside.append([absf(x - ob_x), i])
	inside.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var overlap := 0
	for e in inside:
		overlap += slot_troops(int(e[1]), n, total)
	var lost := 0
	var slots: Array = []
	for e in inside:
		if lost >= capacity:
			break
		lost += mini(slot_troops(int(e[1]), n, total), capacity - lost)
		slots.append(int(e[1]))
	return {"lost": lost, "slots": slots, "figures": n, "overlap": overlap}


func duplicate_squad() -> Squad:
	var s := Squad.new()
	s.counts = counts.duplicate()
	s.hero_weapon = hero_weapon
	s.hero_rate = hero_rate
	s.cap = cap
	return s
