extends "res://tests/test_case.gd"

var cfg: Dictionary = Config.load_json("res://config/finale.json")


func test_one_knife_per_bottle() -> void:
	var b := BottleLogic.new(cfg, 1)
	eq(b.knives_left, b.count(), "as many knives as bottles")
	for i in b.count():
		b.throw(Vector2(9, 9), 0.0)
	eq(b.knives_left, 0, "all used")
	eq(b.throw(b.position(0, 0.0), 0.0), -1, "no extra knife")


func test_direct_hit_breaks_and_misses_do_not() -> void:
	var b := BottleLogic.new(cfg, 1)
	eq(b.throw(b.position(1, 0.0), 0.0), 1, "aimed at bottle 1")
	eq(b.throw(b.position(1, 0.0), 0.0), -1, "already broken")
	eq(b.throw(Vector2(5, 5), 0.0), -1, "miss")
	eq(b.broken_count(), 1, "one broken")


func test_moving_bottles_are_hit_where_they_are_on_arrival() -> void:
	var b := BottleLogic.new(cfg, 3)  # sliding shelf
	var t := 1.0
	check(b.position(0, 0.0).distance_to(b.position(0, t)) > 0.3, "the shelf moved")
	eq(b.hit_at(b.position(0, 0.0), t), -1, "aiming where it was misses")
	eq(b.hit_at(b.position(0, t), t), 0, "leading the target hits")


func test_reward_multiplier() -> void:
	var b := BottleLogic.new(cfg, 1)
	eq(b.coins(10), 60, "no bottles: 40 + 10x2")
	b.throw(b.position(0, 0.0), 0.0)
	b.throw(b.position(1, 0.0), 0.0)
	eq(b.multiplier(), 2.0, "two bottles = x2")
	b.throw(b.position(3, 0.0), 0.0)  # gold
	eq(b.multiplier(), 4.0, "gold doubles")
	eq(b.coins(10, 0.1), 264, "station +10%")
