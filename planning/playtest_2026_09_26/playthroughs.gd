extends RefCounted
## Drives actual DebugPanel handlers, EventRunner, GameState and shipped customer data.
## Reads only today's now-public SNS forecast for procurement; no future days or debug grants.
## Shopping policy assumes perfect reading of that forecast, not a human novice.
## Global RNG is reset at each morning from run seed/day to pair demand draws across policies.

const OUT := "res://planning/playtest_2026_09_26/"
const POLICIES := ["forecast_good", "forecast_favorites", "always_small", "always_large", "cheap_valid", "bare_broth", "forecast_mistakes"]
var tree: SceneTree
var panel
var policy := ""
var clicks := 0
var purchases := 0
var incidents: Array = []
var counts: Dictionary = {}
var reserved: Dictionary = {}
var recipes: Dictionary = {}

func run(t: SceneTree) -> void:
	tree = t
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() else 20
	var results: Array = []
	for p in POLICIES:
		for run_seed in range(1, seeds + 1):
			results.append(await play(p, run_seed))
		print("PLAYTEST_PROGRESS ", p, " ", seeds, " runs")
	var f := FileAccess.open(OUT + "playthrough_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"commit": "1eadb70155e4d614466bfd5003d10b65be6bb3bb", "engine": Engine.get_version_info(),
		"seeds": seeds, "policies": POLICIES, "runs": results}, "\t"))
	f.close()
	print("PLAYTEST_COMPLETE ", results.size())

func play(p: String, run_seed: int) -> Dictionary:
	policy = p
	clicks = 0
	purchases = 0
	incidents = []
	counts = {}
	GameState.reset_for_new_game()
	seed(run_seed * 1000 + 1)
	panel = load("res://scenes/debug_panel.tscn").instantiate()
	tree.root.add_child(panel)
	var rows: Array = []
	var steps := 0
	var done := false
	var stalled := false
	var before_market := false
	while not done and steps < 4000:
		steps += 1
		if steps % 12 == 0:
			await tree.process_frame # release queue_free UI controls
		if GameState.phase == GameState.Phase.GAME_OVER:
			incidents.append({"type": "game_over", "day": GameState.day_count, "cash": GameState.money})
			break
		var r: EventRunner = panel.flow.runner
		if GameState.phase == GameState.Phase.NEXT_DAY:
			rows.append(day_row())
			if GameState.day_count == 7:
				# Run the actual day-end settlement but stop before the automatic new-game reset.
				panel._on_day_ending()
				done = true
				break
			seed(run_seed * 1000 + GameState.day_count + 1)
			panel.flow.advance_phase()
			before_market = false
			continue
		if r.status == EventRunner.Status.DONE:
			panel.flow.advance_phase()
			continue
		if GameState.phase == GameState.Phase.WAKE:
			panel.flow.advance_phase()
			continue
		var ev = r.current()
		var typ := str(ev.get("type", "")) if ev is Dictionary else ""
		if typ == "PREP_TIER":
			var tier := "small"
			var target := forecast_cups()
			if policy == "always_large":
				tier = "large"
			elif policy != "always_small":
				tier = "large" if GameState.day_count == 1 and policy != "bare_broth" else ("small" if target <= 12 else ("medium" if target <= 15 else "large"))
			if GameState.money < int(Day1Events.prep_tier_by_id(tier).price):
				tier = "small"
			act("prep")
			panel._on_prep_tier_selected(tier)
			continue
		if typ == "MARKET":
			if not before_market:
				shop()
				before_market = true
			act("market_exit")
			panel._on_market_exit_pressed()
			continue
		if GameState.phase == GameState.Phase.OPEN:
			if panel._pot_mode:
				incidents.append({"type": "pot_mode_stuck", "day": GameState.day_count, "soup": GameState.soup.duplicate(), "dashi": GameState.dashi_units})
				stalled = true
				break
			if panel._pending_shortage_ev != null:
				if not fix_pot() and not panel._btn_close.disabled:
					act("close")
					panel._on_close_pressed()
				continue
			if typ == "ADJUST":
				var order: Dictionary = panel._react_for_now()
				var wanted := int(order.get("servings", 1))
				if int(GameState.soup.remaining_servings) < wanted or int(GameState.soup.strength) <= 0:
					fix_pot()
				if GameState.phase != GameState.Phase.OPEN:
					continue
				if panel._btn_complete_input.disabled:
					if not panel._btn_close.disabled:
						incidents.append({"type": "forced_close", "day": GameState.day_count, "soup": GameState.soup.duplicate(), "dashi": GameState.dashi_units})
						act("close")
						panel._on_close_pressed()
						continue
					stalled = true
					incidents.append({"type": "adjust_stuck", "day": GameState.day_count, "soup": GameState.soup.duplicate()})
					break
				cook(order)
				act("confirm")
				panel._on_complete_input_pressed()
				if panel._pending_group_choice:
					var achievable: int = panel._mob_achievable_servings(wanted)
					act("group_choice")
					if achievable < wanted and panel._mob_recipe_number == 1 and policy not in ["bare_broth", "cheap_valid"]:
						panel._on_group_retry_pressed(achievable, wanted)
					elif achievable > 0:
						panel._on_group_serve_pressed(achievable, wanted)
					else:
						panel._on_group_decline_pressed(wanted)
				continue
			# Adjust concentration before taking an order; ADJUST locks normal pot changes.
			if typ not in ["SERVE", "REACT"] and not panel._btn_pot.disabled:
				fix_pot()
		if r.status == EventRunner.Status.WAITING_INPUT:
			act("input")
			panel._on_complete_input_pressed()
		else:
			act("next_text_event")
			panel._on_next_event_pressed()
	var result := {"policy": policy, "seed": run_seed, "completed": done, "stalled": stalled or steps >= 4000,
		"cash": GameState.money, "rep": GameState.reputation, "rows": rows, "incidents": incidents.duplicate(true),
		"actions": counts.duplicate(), "clicks": clicks, "purchases": purchases, "steps": steps,
		"closing_stock_units": GameState.inventory.duplicate(), "dashi": GameState.dashi_units}
	panel.queue_free()
	await tree.process_frame
	return result

func act(kind: String) -> void:
	clicks += 1
	counts[kind] = int(counts.get(kind, 0)) + 1

func center() -> int:
	for row in GameState.DEMAND_TABLE:
		if GameState.reputation >= int(row[0]):
			return int(row[1])
	return 7

func shop() -> void:
	reserved = {}
	recipes = {}
	if GameState.day_count == 1 or policy == "bare_broth":
		return # all shops locked on day1; bare broth intentionally uses no ingredients
	while GameState.dashi_units < 2 and GameState.money >= 16:
		buy("meat_wholesale", "dashi")
	for slot in panel._tonight_schedule:
		for cid in slot.customers:
			var flavor: Dictionary = Day1Events._customer_flavor(str(cid))
			var n := int(flavor.get("servings", 1))
			var tags: Array = ["SOUR", "FILLING"] if policy == "cheap_valid" else flavor.get("wanted_tags", [])
			var selected: Array = []
			for tag in tags:
				var options: Array = []
				for shop_id in ["produce", "meat_wholesale", "dry_goods", "tofu_noodles", "seafood", "scraps"]:
					for good in panel._shop_goods(shop_id):
						var id := str(good.get("item", ""))
						if id == "" or not Ingredients.tags_for(id).has(tag): continue
						var short := maxi(0, n + int(reserved.get(id, 0)) - GameState.fresh_count(id))
						options.append({"id": id, "score": ceili(float(short) / int(good.count)) * int(good.price), "unit": float(good.price) / int(good.count)})
				options.sort_custom(func(a, b): return a.score < b.score if a.score != b.score else a.unit < b.unit)
				if not options.is_empty():
					var id := str(options[0].id)
					if not selected.has(id):
						reserve(id, n)
						selected.append(id)
			recipes[str(cid)] = selected
	if policy == "forecast_favorites":
		for slot in panel._tonight_schedule:
			for cid in slot.customers:
				if not GameState.knows_favorite(str(cid)): continue
				var favorite := str(Day1Events._customer_flavor(str(cid)).get("favorite", ""))
				if favorite != "" and not recipes.get(str(cid), []).has(favorite): reserve(favorite, 1)
	if panel._market_shop != "":
		act("shop_exit")
		panel._on_shop_exit_pressed()

func reserve(id: String, n: int) -> void:
	reserved[id] = int(reserved.get(id, 0)) + n
	ensure(id, int(reserved[id]))

func forecast_cups() -> int:
	if GameState.day_count == 1: return 13
	var n := 0
	for slot in panel._tonight_schedule:
		for cid in slot.customers:
			n += int(Day1Events._customer_flavor(str(cid)).get("servings", 1))
	return n

func ensure(id: String, target: int) -> void:
	while GameState.fresh_count(id) < target:
		var choices: Array = []
		for shop_id in ["produce", "meat_wholesale", "dry_goods", "tofu_noodles", "seafood", "scraps"]:
			for good in panel._shop_goods(shop_id):
				if str(good.get("item", "")) == id:
					var short := target - GameState.fresh_count(id)
					var units := int(good.get("count", 1))
					choices.append({"shop": shop_id, "good": good, "score": ceili(float(short) / units) * int(good.price)})
		choices.sort_custom(func(a, b): return a.score < b.score)
		if choices.is_empty() or GameState.money < int(choices[0].good.price):
			return
		buy(str(choices[0].shop), str(choices[0].good.id))

func buy(shop_id: String, id: String) -> void:
	if panel._market_shop != shop_id:
		if panel._market_shop != "":
			act("shop_exit")
			panel._on_shop_exit_pressed()
		act("shop_enter")
		panel._on_market_stall_selected(shop_id)
	var before := GameState.money
	act("purchase")
	panel._on_shop_item_selected(shop_id, id)
	purchases += before - GameState.money

func cook(order: Dictionary) -> void:
	if policy == "bare_broth":
		return
	var wanted: Array = order.get("wanted_tags", [])
	var n := int(order.get("servings", 1))
	if not bool(order.get("judge", true)):
		wanted = ["MELLOW", "GENTLE"]
	var added: Array = []
	if policy == "cheap_valid":
		wanted = ["SOUR", "FILLING"]
	if policy == "forecast_mistakes" and GameState.day_count in [3, 5] and panel._open.slot_index == 0 and not bool(order.get("is_mob", false)):
		wanted = ["SAVORY", "FILLING"] if not wanted.has("SAVORY") else ["HOT", "POWER"]
	for tag in wanted:
		if added.size() >= 2:
			break
		var id := ""
		for planned in recipes.get(str(order.get("customer", "")), []):
			if Ingredients.tags_for(str(planned)).has(tag) and GameState.fresh_count(planned) >= n: id = str(planned)
		if id == "": id = choose(str(tag), n)
		if id != "" and not added.has(id):
			act("ingredient")
			panel._on_ingredient_selected(id)
			added.append(id)
	if policy == "forecast_favorites" and GameState.knows_favorite(str(order.get("customer", ""))):
		var favorite := str(order.get("favorite", ""))
		if favorite != "" and not added.has(favorite) and GameState.fresh_count(favorite) >= n:
			act("ingredient")
			panel._on_ingredient_selected(favorite)

func choose(tag: String, n: int) -> String:
	var ids: Array = []
	for id in GameState.inventory:
		if Ingredients.tags_for(str(id)).has(tag) and GameState.fresh_count(id) > 0:
			ids.append(str(id))
	ids.sort_custom(func(a, b):
		var ac: int = GameState.fresh_count(a)
		var bc: int = GameState.fresh_count(b)
		if (ac >= n) != (bc >= n): return ac >= n
		# Use fresh stock that expires first. Otherwise abundant stock, stable id tie-break.
		var aa := first_day(a)
		var ba := first_day(b)
		if aa != ba: return aa < ba
		if ac != bc: return ac > bc
		return a < b)
	return str(ids[0]) if not ids.is_empty() else ""

func first_day(id: String) -> int:
	var batches: Array = GameState.perishable_batches.get(id, [])
	for batch in batches:
		if GameState.day_count - int(batch.day) < 2:
			return int(batch.day)
	return 999

func fix_pot() -> bool:
	if panel._btn_pot.disabled:
		return false
	var n: int = int(panel._react_for_now().get("servings", 1))
	var v := int(GameState.soup.remaining_servings)
	var s := int(GameState.soup.strength)
	if v >= n and (policy == "bare_broth" or (s >= 2 and s <= 4)):
		return false
	act("pot_open")
	panel._on_pot_pressed()
	var changed := false
	for attempt in range(5):
		v = int(GameState.soup.remaining_servings)
		s = int(GameState.soup.strength)
		if s < 2 and GameState.can_add_dashi() and not panel._pot_locked_until_water():
			act("dashi")
			panel._on_add_dashi_pressed()
			changed = true
		elif (v < n or s >= 5) and GameState.can_add_water():
			act("water")
			panel._on_add_water_pressed()
			changed = true
		else:
			break
	var locked: bool = (panel._pot_locked_until_water() and GameState.can_add_water()) or (panel._pot_locked_until_dashi() and GameState.can_add_dashi())
	if not locked:
		act("pot_back")
		panel._on_pot_back_pressed()
	return changed

func day_row() -> Dictionary:
	var served := 0
	var sale := 0
	for rec in GameState.served:
		if not bool(rec.get("discarded", false)):
			served += int(rec.get("servings", 0))
			sale += int(rec.get("sale", 0))
	var quality: float = panel._quality_score(panel._log_quality_counts, panel._log_judged_planned_cups)
	return {"day": GameState.day_count, "cash": GameState.money, "open_rep": GameState.reputation,
		"next_rep": roundi(GameState.reputation * 0.7 + quality * 0.3), "quality": quality,
		"demand": panel._log_planned_cups, "served": served, "unserved": panel._log_planned_cups - served,
		"sales": sale, "grades": panel._log_quality_counts.duplicate(), "spoiled_value": panel._spoiled_value(panel._log_spoiled_items),
		"water": panel._log_water_used, "dashi": panel._log_dashi_used, "soup_left": GameState.soup.get("remaining_servings", 0),
		"stock": GameState.inventory.duplicate(), "actions_cumulative": clicks}
