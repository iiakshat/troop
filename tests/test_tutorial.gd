extends "res://tests/test_case.gd"
## First-run tutorials (v1.1 item 11): the lane the gate tutorial lights and red-gate detection.


func test_first_gate_of_level_1_lights_the_plus_ten() -> void:
	var row := {"gates": [{"lane": 0, "op": "num", "v": 4}, {"lane": 1, "op": "num", "v": -1, "step": 0.5, "max": 3}, {"lane": 2, "op": "num", "v": 10}]}
	eq(Tutorial.best_lane(row, 1.0, 1), 2, "+10 beats +4 and the red -1")


func test_multiplier_wins_for_a_big_squad_only() -> void:
	var row := {"gates": [{"lane": 0, "op": "num", "v": 10}, {"lane": 2, "op": "mul", "k": 3}]}
	eq(Tutorial.best_lane(row, 1.0, 1), 0, "1 troop: +10 beats x3")
	eq(Tutorial.best_lane(row, 20.0, 1), 2, "20 troops: x3 beats +10")


func test_tie_keeps_the_current_lane() -> void:
	var row := {"gates": [{"lane": 0, "op": "num", "v": 5}, {"lane": 2, "op": "num", "v": 5}]}
	eq(Tutorial.best_lane(row, 3.0, 2), 2, "equal offers: stay")


func test_red_gate_detection() -> void:
	check(Tutorial._is_red({"op": "num", "v": -4, "step": 1.5, "max": 8}), "ticking negative gate is red")
	check(Tutorial._is_red({"op": "pct", "v": -40, "step": 12.4, "max": 40}), "negative percent gate is red")
	check(not Tutorial._is_red({"op": "num", "v": 2, "step": 1.5, "max": 8}), "shot up past 0: an offer")
	check(not Tutorial._is_red({"op": "num", "v": -4}), "no step: a plain minus gate")


func test_owned_hints_cover_the_level_data_ids() -> void:
	for id in ["swipe", "red_gate", "shield", "bomb"]:
		check(Tutorial.OWNS.has(id), id)
