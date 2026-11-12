extends "res://tests/test_case.gd"
## Shield and bomb (spec v2 section 7): one free charge each that recharges 5 h after use,
## guarded against a clock moved back, an ad refill, and stored charges on top.

var eco := Config.economy()
const H := 3600


func _save() -> Dictionary:
	return SaveData.migrate({}, eco)


func test_config() -> void:
	eq(int(eco["powers"]["recharge_s"]), 5 * H, "5 hours")
	eq(int(eco["powers"]["free"]["shield"]), 1, "one free shield")
	eq(int(eco["powers"]["free"]["bomb"]), 1, "one free bomb")


func test_free_charge_recharges_after_5h() -> void:
	var s := _save()
	eq(PowersTimer.available(s, "shield", 1000, eco), 1, "new player: one free shield")
	check(PowersTimer.use(s, "shield", 1000, eco), "used")
	eq(PowersTimer.available(s, "shield", 1001, eco), 0, "none left")
	eq(PowersTimer.seconds_left(s, "shield", 1000 + H, eco), 4 * H, "4 h to go after 1 h")
	eq(PowersTimer.available(s, "shield", 1000 + 5 * H - 1, eco), 0, "not a second early")
	eq(PowersTimer.available(s, "shield", 1000 + 5 * H, eco), 1, "back after 5 h")
	eq(PowersTimer.seconds_left(s, "shield", 1000 + 5 * H, eco), 0, "nothing to wait for")
	eq(PowersTimer.available(s, "bomb", 1001, eco), 1, "the bomb has its own timer")
	check(not PowersTimer.use(s, "shield", 2000, eco), "nothing to use")


func test_clock_moved_back_gives_nothing() -> void:
	var s := _save()
	check(PowersTimer.use(s, "bomb", 10000, eco), "used at t=10000")
	var ready := int(s["powers"]["bomb"]["ready_at"])
	eq(PowersTimer.available(s, "bomb", 5000, eco), 0, "clock moved back: no free bomb")
	eq(int(s["powers"]["bomb"]["ready_at"]), ready, "ready time unchanged")
	# Winding the clock forward to refill, then back, does not start the next timer early.
	eq(PowersTimer.available(s, "bomb", 10000 + 5 * H, eco), 1, "ready at the later time")
	check(PowersTimer.use(s, "bomb", 10000 + 5 * H, eco), "used at the late time")
	check(PowersTimer.seconds_left(s, "bomb", 12000, eco) >= 5 * H, "the clock wound back waits at least 5 h")
	check(PowersTimer.use(s, "shield", 3000, eco), "a free shield still works with an older clock")
	check(int(s["powers"]["shield"]["ready_at"]) >= 10000 + 10 * H, "its timer starts from the latest time seen, not the wound-back clock")


func test_ad_refill_makes_free_ready_now() -> void:
	var s := _save()
	PowersTimer.use(s, "shield", 1000, eco)
	eq(PowersTimer.available(s, "shield", 2000, eco), 0, "recharging")
	PowersTimer.refill_free(s, "shield", 2000, eco)
	eq(PowersTimer.available(s, "shield", 2000, eco), 1, "ready after the ad")
	eq(PowersTimer.seconds_left(s, "shield", 2000, eco), 0, "no countdown")
	PowersTimer.refill_free(s, "shield", 2000, eco)
	eq(PowersTimer.available(s, "shield", 2000, eco), 1, "a refill never stacks past the free count")


func test_stored_used_after_free() -> void:
	var s := _save()
	PowersTimer.add_stored(s, "bomb", 2)
	eq(PowersTimer.available(s, "bomb", 100, eco), 3, "1 free + 2 stored")
	check(PowersTimer.use(s, "bomb", 100, eco), "first use")
	eq(int(s["powers"]["bomb"]["stored"]), 2, "the free one went first")
	check(int(s["powers"]["bomb"]["ready_at"]) > 100, "its timer started")
	check(PowersTimer.use(s, "bomb", 101, eco), "second use")
	eq(int(s["powers"]["bomb"]["stored"]), 1, "then a stored one")
	eq(PowersTimer.available(s, "bomb", 102, eco), 1, "one stored left")


func test_settle_after_level() -> void:
	var s := _save()
	PowersTimer.add_stored(s, "shield", 1)
	var brought := PowersTimer.available(s, "shield", 500, eco)
	eq(brought, 2, "brought 2")
	# The level also gave a shield of its own; the player used 2 of the 3, so 1 is left.
	eq(PowersTimer.settle(s, "shield", brought, 1, 500, eco), 1, "one owned charge spent (the level's went first)")
	eq(PowersTimer.available(s, "shield", 501, eco), 1, "the stored one is left")
	eq(PowersTimer.settle(s, "shield", 1, 5, 501, eco), 0, "more left than brought: nothing spent")
