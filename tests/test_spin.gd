extends "res://tests/test_case.gd"
## Lucky spin: odds match slice sizes, daily limits.

var eco := Config.economy()


func test_probabilities_sum_to_one_and_match_weights() -> void:
	var total := 0.0
	var w := Spin.total_weight(eco)
	for i in Spin.slices(eco).size():
		var p := Spin.probability(i, eco)
		total += p
		check(absf(p - float(Spin.slices(eco)[i]["weight"]) / w) < 1e-12, "slice %d chance = weight share" % i)
	check(absf(total - 1.0) < 1e-9, "chances sum to 1")
	eq(Spin.probability(-1, eco), 0.0, "bad index")


func test_pick_follows_weights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var n := Spin.slices(eco).size()
	var counts := []
	counts.resize(n)
	counts.fill(0)
	var draws := 40000
	for k in draws:
		counts[Spin.pick(rng, eco)] += 1
	for i in n:
		var got := float(counts[i]) / draws
		check(absf(got - Spin.probability(i, eco)) < 0.01, "slice %d drawn %.3f vs %.3f" % [i, got, Spin.probability(i, eco)])


func test_daily_limits() -> void:
	var s := SaveData.migrate({}, eco)
	var d := "2026-11-08"
	check(Spin.can_spin_free(s, d, eco), "free spin first")
	check(not Spin.can_spin_ad(s, d, eco), "ad spins only after the free one")
	check(not Spin.use(s, d, "ad", eco), "no ad spin yet")
	check(Spin.use(s, d, "free", eco), "free spin")
	check(not Spin.can_spin_free(s, d, eco), "one free a day")
	for i in int(eco["spin"]["ad_per_day"]):
		check(Spin.use(s, d, "ad", eco), "ad spin %d" % i)
	check(not Spin.use(s, d, "ad", eco), "ad spins run out")
	eq(Spin.ad_left(s, d, eco), 0, "none left")
	check(Spin.can_spin_free(s, "2026-11-09", eco), "new day, new free spin")
	eq(Spin.ad_left(s, "2026-11-09", eco), int(eco["spin"]["ad_per_day"]), "ad spins reset")


func test_clock_going_back_grants_nothing() -> void:
	var s := SaveData.migrate({}, eco)
	check(Spin.use(s, "2026-11-09", "free", eco), "today's free spin")
	check(not Spin.can_spin_free(s, "2026-11-08", eco), "a day back: no new free spin")
	eq(Spin.ad_left(s, "2026-11-08", eco), int(eco["spin"]["ad_per_day"]), "ad spins not doubled by the date either")
	check(not Spin.can_spin_free(s, "2026-11-09", eco), "and back to today: still used")
