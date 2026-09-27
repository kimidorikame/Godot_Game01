extends SceneTree
## Focused probes use synthetic boundary states; these are not counted as full playthroughs.
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var events = load("res://scripts/day1_events.gd")
	var oc = load("res://scripts/open_controller.gd")
	var results := {"commit": "1eadb70"}
	gs.reset_for_new_game()
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	root.add_child(panel)
	var actual := 0
	for slot in panel._tonight_schedule:
		for cid in slot.customers:
			actual += events._customer_total_servings(str(cid))
	results["day1"] = {"demand_function": gs.total_demand_today(), "actual_cups": actual,
		"initial_inventory": gs.inventory.duplicate(), "cash_after_upkeep": gs.money,
		"memo": panel._format_tonight_memo(), "dashi": gs.dashi_units,
		"shops": events._market_options(), "pending_bill_label": gs.pending_bills_today,
		"actual_unpaid": gs.RENT_PRICE + gs.WATER_PRICE}
	gs.set_soup("bone_broth", [], 14, 3, 2)
	gs.dashi_units = 1
	gs.add_water()
	gs.add_dashi()
	gs.add_water()
	results["volume_after_water_dashi_water"] = gs.soup.duplicate()
	gs.set_soup("bone_broth", [], 5, 1, 2)
	var bowl = oc.new([{ "name": "test", "customers": ["granny"] }])
	bowl.add_to_bowl("herbal_sauce", true)
	bowl.add_to_bowl("broken_wrapper")
	results["two_penalties"] = bowl.judge_bowl(["SAVORY", "FILLING"])
	gs.set_soup("bone_broth", [], 5, 3, 2)
	bowl.reset_bowl()
	bowl.add_to_bowl("tofu")
	bowl.add_to_bowl("meat_ball")
	results["no_taste_but_favorite"] = bowl.judge_bowl(["MELLOW", "GENTLE"], "meat_ball")
	panel.free()
	var recovered := []
	for strength in [0, 1]:
		gs.reset_for_new_game()
		panel = load("res://scenes/debug_panel.tscn").instantiate()
		root.add_child(panel)
		gs.phase = gs.Phase.OPEN
		panel._open = oc.new([{ "name": "test", "customers": ["thug"] }])
		gs.set_soup("bone_broth", [], 0, 2, 2)
		gs.add_water()
		gs.consume_soup(2)
		if strength == 1: gs.deepen_soup()
		gs.dashi_units = 2
		panel._load_current_customer()
		while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT: panel._on_next_event_pressed()
		var entry := {"strength": strength, "pot_enabled": not panel._btn_pot.disabled}
		if not panel._btn_pot.disabled:
			panel._on_pot_pressed()
			await process_frame
			entry["buttons_before"] = buttons(panel._options_row)
			panel._on_add_dashi_pressed()
			panel._on_add_water_pressed()
			if int(gs.soup.strength) < 2: panel._on_add_dashi_pressed()
			panel._on_pot_back_pressed()
			entry["after"] = gs.soup.duplicate()
			entry["back_in_order"] = not panel._pot_mode
		recovered.append(entry)
		panel.free()
	results["pot_recovery"] = recovered
	gs.reset_for_new_game()
	panel = load("res://scenes/debug_panel.tscn").instantiate()
	root.add_child(panel)
	gs.phase = gs.Phase.OPEN
	for goods in [events.produce_goods(), events.meat_wholesale_goods(), events.dry_goods_goods(), events.tofu_noodles_goods(), events.seafood_goods(), events.scraps_goods()]:
		for good in goods:
			if good.has("item"): gs.add_inventory(good.item, good.count)
	panel._open = oc.new([{ "name": "test", "customers": ["thug"] }])
	gs.set_soup("bone_broth", [], 14, 3, 2)
	panel._load_current_customer()
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT: panel._on_next_event_pressed()
	await process_frame
	await process_frame
	results["all_stock_layout"] = {"panel": str(panel.size), "topping_minimum": str(panel._options_row.get_combined_minimum_size()), "seasoning_minimum": str(panel._seasoning_row.get_combined_minimum_size())}
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://planning/playtest_2026_09_26/adjust_all_stock.png")
	panel.free()
	var f := FileAccess.open("res://planning/playtest_2026_09_26/latest_probes.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print(JSON.stringify(results))
	quit()

func buttons(row) -> Array:
	var out := []
	for btn in row.get_children(): out.append({"text": btn.text, "disabled": btn.disabled})
	return out
