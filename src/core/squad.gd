class_name Squad
extends RefCounted
## The player's army as a head count per rank. Pure logic: no nodes, unit tested.
##
## Rules that keep the arithmetic honest (what the player sees is what happens):
## - total() is what the squad counter shows.
## - ×k makes total() exactly k times bigger: every recruit brings k-1 more of the same
##   rank, and the hero (who can't be copied) brings k-1 constables.
## - Losses take the lowest rank first; the hero falls last, and that ends the level.

const LOSS_ORDER := ["constable", "inspector", "hero"]

var counts: Dictionary = {"hero": 1, "constable": 0, "inspector": 0}
var hero_weapon: String = ""


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
	return total() - before


## Removes up to n troops, lowest rank first. Returns how many were actually lost.
func lose(n: int) -> int:
	var left := maxi(n, 0)
	for rank in LOSS_ORDER:
		if left <= 0:
			break
		var take := mini(left, count(rank))
		counts[rank] = count(rank) - take
		left -= take
	return maxi(n, 0) - left


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
## (after upgrades); armour comes off every hit unless the attacker pierces.
func dps(stats: Dictionary, weapons: Dictionary, armour: int) -> float:
	var sum := 0.0
	for rank in counts:
		var n := count(rank)
		if n <= 0 or not stats.has(rank):
			continue
		sum += n * hit_value(stats[rank], armour)
	if hero_weapon != "" and hero_alive() and weapons.has(hero_weapon):
		sum += hit_value(weapons[hero_weapon], armour)
	return sum


static func hit_value(unit: Dictionary, armour: int) -> float:
	var dmg := float(unit.get("dmg", 1))
	if not bool(unit.get("pierce", false)):
		dmg = maxf(dmg - armour, 0.0)
	return dmg * float(unit.get("rate", 1.0))


func duplicate_squad() -> Squad:
	var s := Squad.new()
	s.counts = counts.duplicate()
	s.hero_weapon = hero_weapon
	return s
