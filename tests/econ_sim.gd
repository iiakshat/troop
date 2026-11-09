extends SceneTree
## Prints the economy simulation (tests/econ_model.gd): one row per level won.
##   godot --headless --path . --script res://tests/econ_sim.gd [-- buys=1]
## Columns: level, win coins, extra (daily, missions, spin, star chests, liberation), city
## coins collected, coins on the map, affordable progress items (rooms + buildings) / all incl.
## cosmetics, cheapest progress price, what got bought, coins left, Squad Power vs the
## recommended power of the next level, city income per hour.

const Model := preload("res://tests/econ_model.gd")


func _initialize() -> void:
	var rows: Array = Model.run(Config.economy(), Config.load_json("res://config/finale.json"), Config.units())
	print("L   win  extra city  coins aff/all cheap  left  power/rec  inc/h  bought")
	for r in rows:
		print("%-3d %4d %5d %4d %6d   %d/%-2d %5d %5d  %4d/%-4d %5d  %s" % [
			r["level"], r["income"], r["extra"], r["city"], r["coins"], r["affordable_progress"],
			r["affordable"], r["cheapest"], r["left"], r["power"], r["rec"], r["income_h"],
			" ".join(PackedStringArray(r["bought"]))])
	var s: Dictionary = Model.summary(rows)
	print("in band (1-3 affordable): %d%%  none at: %s  over 3 at: %s" % [int(round(float(s["in_band"]) * 100.0)), str(s["none"]), str(s["over"])])
	quit()
