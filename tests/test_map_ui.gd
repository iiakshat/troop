extends "res://tests/test_case.gd"
## City map lobby helpers (MAP-UI): level node states, district progress, scroll clamping,
## the map layout file, timer / coin formatting and the icon fallback.

var eco := Config.economy()


func _save(unlocked := 1, stars := {}) -> Dictionary:
	var s := SaveData.migrate({}, eco)
	s["unlocked"] = unlocked
	s["stars"] = stars
	return s


func test_fmt_time() -> void:
	eq(UiKit.fmt_time(0), "0:00", "zero")
	eq(UiKit.fmt_time(30), "0:30", "seconds")
	eq(UiKit.fmt_time(65), "1:05", "minutes")
	eq(UiKit.fmt_time(3599), "59:59", "under an hour")
	eq(UiKit.fmt_time(3600), "1h", "one hour")
	eq(UiKit.fmt_time(7800), "2h 10m", "hours and minutes")
	eq(UiKit.fmt_time(-5), "0:00", "never negative")


func test_fmt_coins() -> void:
	eq(UiKit.fmt_coins(950), "950", "small")
	eq(UiKit.fmt_coins(9999), "9999", "under 10K stays exact")
	eq(UiKit.fmt_coins(12500), "12.5K", "thousands")
	eq(UiKit.fmt_coins(250000), "250K", "big thousands")
	eq(UiKit.fmt_coins(3200000), "3.2M", "millions")


func test_icon_fallback() -> void:
	check(UiKit.icon_texture("coin") != null, "known icon loads")
	check(UiKit.icon_texture("no_such_icon_xyz") != null, "missing icon falls back")
	eq(UiKit.icon_texture("no_such_icon_xyz"), UiKit.icon_texture("star_icon"), "falls back to the star")


func test_node_states() -> void:
	var count := 50
	var s := _save(1)
	eq(CityMap.current_level(s, count), 1, "new player plays level 1")
	eq(CityMap.node_state(s, 1, count), "current", "level 1 current")
	eq(CityMap.node_state(s, 2, count), "locked", "level 2 locked")
	s = _save(4, {"1": 3, "2": 1, "3": 2})
	eq(CityMap.current_level(s, count), 4, "first unbeaten level")
	eq(CityMap.node_state(s, 2, count), "beaten", "beaten")
	eq(CityMap.node_state(s, 4, count), "current", "current")
	eq(CityMap.node_state(s, 5, count), "locked", "past unlocked")
	eq(CityMap.node_state(s, 4, 3), "locked", "past the levels that exist")
	eq(CityMap.node_state(s, 0, count), "locked", "no level 0")
	s = _save(3, {"1": 3, "2": 1, "3": 2})
	eq(CityMap.current_level(s, 3), 3, "everything beaten: the last one")
	eq(CityMap.node_state(s, 3, 3), "beaten", "last one beaten")


func test_district_progress() -> void:
	var s := _save(12, {"1": 3, "2": 2, "3": 1, "10": 3, "11": 1})
	var p := CityMap.district_progress(s, 1, eco)
	eq(p["beaten"], 10, "levels below unlocked count as beaten")
	eq(p["total"], 10, "ten levels")
	eq(p["stars"], 9, "stars summed")
	eq(p["max_stars"], 30, "max stars")
	p = CityMap.district_progress(s, 2, eco)
	eq(p["beaten"], 1, "district 2 progress")
	eq(p["stars"], 1, "district 2 stars")


func test_scroll_and_flight() -> void:
	eq(CityMap.clamp_scroll(-50.0, 1000.0, 400.0), 0.0, "not above the top")
	eq(CityMap.clamp_scroll(900.0, 1000.0, 400.0), 600.0, "not past the bottom")
	eq(CityMap.clamp_scroll(300.0, 300.0, 400.0), 0.0, "short content stays put")
	eq(CityMap.fly_count(1), 3, "at least 3 coins fly")
	eq(CityMap.fly_count(1000), 12, "at most 12")


func test_layout_covers_levels_and_buildings() -> void:
	var l := CityMap.load_layout()
	var levels := {}
	var blds := {}
	for d in l["districts"]:
		var band: Array = d["band"]
		for e in d["levels"]:
			levels[int(e["level"])] = true
			var y := float(e["pos"][1])
			check(y >= float(band[0]) and y <= float(band[1]), "level %d inside its band" % int(e["level"]))
		for b in d["buildings"]:
			blds[String(b["id"])] = true
			check(City.buildings_in(int(d["id"]), eco).has(String(b["id"])), "%s in its district" % b["id"])
	eq(levels.size(), 50, "50 level nodes")
	eq(blds.size(), City.ids(eco).size(), "every building has a plot")
	var f := CityMap.fallback_layout()
	eq((f["districts"] as Array).size(), 5, "fallback has 5 districts")
	eq((f["districts"][0]["buildings"] as Array).size(), 5, "fallback places buildings")
