class_name BottleLogic
extends RefCounted
## Bottle Shot finale rules. Pure and tested; src/finale/bottle_shot.gd only draws it.
## Bottles live on a wall plane; a knife flies in a straight line to the aimed point and
## hits whichever unbroken bottle is within `hit_radius` of that point when it arrives.

var cfg: Dictionary
var layout: Dictionary
var broken: Array = []      # bool per bottle
var knives_left := 3
var time := 0.0


func _init(finale_cfg: Dictionary, level_id: int) -> void:
	cfg = finale_cfg
	var layouts: Dictionary = cfg["layouts"]
	layout = layouts.get(str(level_id), layouts["1"])
	knives_left = int(cfg["knives"])
	for b in layout["bottles"]:
		broken.append(false)


func count() -> int:
	return (layout["bottles"] as Array).size()


func is_gold(i: int) -> bool:
	return bool(layout["bottles"][i].get("gold", false))


## Where bottle `i` is on the wall at time `t` (x sideways, y height).
func position(i: int, t: float) -> Vector2:
	var b: Dictionary = layout["bottles"][i]
	var p := Vector2(float(b["x"]), float(b["y"]))
	var amp := float(layout.get("amp", 0.0))
	var speed := float(layout.get("speed", 1.0))
	match String(layout.get("motion", "static")):
		"slide", "drive":
			p.x += sin(t * speed) * amp
		"swing":
			p.x += sin(t * speed + i * 1.3) * amp
	return p


## Seconds a knife takes to cover `dist` metres.
func flight_time(dist: float) -> float:
	return dist / float(cfg["knife_speed"])


## Which bottle (or -1) a knife aimed at `aim` hits, arriving at time `t_hit`.
func hit_at(aim: Vector2, t_hit: float) -> int:
	var best := -1
	var best_d := float(cfg["hit_radius"])
	for i in count():
		if broken[i]:
			continue
		var d := position(i, t_hit).distance_to(aim)
		if d <= best_d:
			best = i
			best_d = d
	return best


## Throws one knife; returns the bottle index broken or -1. Uses up a knife either way.
func throw(aim: Vector2, t_hit: float) -> int:
	if knives_left <= 0:
		return -1
	knives_left -= 1
	var i := hit_at(aim, t_hit)
	if i >= 0:
		broken[i] = true
	return i


func broken_count(gold := false) -> int:
	var n := 0
	for i in count():
		if broken[i] and is_gold(i) == gold:
			n += 1
	return n


## Multiplier from broken bottles: 1 + bonus per normal bottle, x gold_mult for gold.
func multiplier() -> float:
	var m := 1.0 + broken_count(false) * float(cfg["bonus_per_bottle"])
	if broken_count(true) > 0:
		m *= float(cfg["gold_mult"])
	return m


func coins(troops: int, station_bonus := 0.0) -> int:
	var base := float(cfg["clear_bonus"]) + troops * float(cfg["per_troop"])
	return int(round(base * multiplier() * (1.0 + station_bonus)))
