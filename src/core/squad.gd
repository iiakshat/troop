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
	var amount := int(floor(total() * absi(pct) / 100.0))
	if pct >= 0:
		return add("constable", amount)
	return -lose(amount)


## ÷k, rounded down, never below the hero alone.
func divide(k: int) -> int:
	if k <= 1:
		return 0
	var target := maxi(int(floor(total() / float(k))), 1)
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
		sum += n * hit_value(stats[rank], armour, hp, enemies)
	if which != Fire.SNIPE and hero_weapon != "" and hero_alive() and weapons.has(hero_weapon):
		sum += hit_value(weapons[hero_weapon], armour, hp, enemies)
	return sum


## The part of dps() that comes from piercing attackers (passes riot shields).
func pierce_dps(stats: Dictionary, weapons: Dictionary, hp := 1.0, enemies := 1 << 30, which := Fire.ALL) -> float:
	var sum := 0.0
	for rank in counts:
		var n := count(rank)
		if n > 0 and stats.has(rank) and bool(stats[rank].get("pierce", false)) and _counts_for(stats[rank], which):
			sum += n * hit_value(stats[rank], 0, hp, enemies)
	return sum


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


func duplicate_squad() -> Squad:
	var s := Squad.new()
	s.counts = counts.duplicate()
	s.hero_weapon = hero_weapon
	s.cap = cap
	return s
