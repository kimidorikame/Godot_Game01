extends SceneTree

func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var open_script = load("res://scripts/open_controller.gd")
	var day_events = load("res://scripts/day1_events.gd")
	var results := {}
	for state in [[0, 1, 1, 1], [0, 0, 1, 1], [1, 0, 1, 1], [0, 3, 1, 0]]:
		gs.reset_for_new_game()
		var panel = load("res://scenes/debug_panel.tscn").instantiate()
		root.add_child(panel)
		gs.phase = gs.Phase.OPEN
		panel._open = open_script.new([{ "name": "test", "customers": ["thug"] }])
		gs.set_soup("bone_broth", ["meaty"], state[0], state[1], state[2])
		if state[1] == 0:
			# Reach zero through legal water addition; consumption models discards.
			gs.set_soup("bone_broth", ["meaty"], state[0] + 2, 2, state[2] + 1)
			gs.add_water()
			gs.consume_soup(4)
		gs.dashi_units = state[3]
		panel._load_current_customer()
		while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT:
			panel._on_next_event_pressed()
		panel._refresh()
		var key := "remaining%d_strength%d_water%d_dashi%d" % state
		var entry := {"pot_disabled": panel._btn_pot.disabled, "close_disabled": panel._btn_close.disabled,
			"can_water": gs.can_add_water(), "can_dashi": gs.can_add_dashi()}
		if not panel._btn_pot.disabled:
			panel._on_pot_pressed()
			await process_frame
			entry["pot_buttons"] = []
			for btn in panel._options_row.get_children():
				entry["pot_buttons"].append({"label": btn.text, "disabled": btn.disabled})
		results[key] = entry
		panel.free()

	gs.reset_for_new_game()
	var mob_panel = load("res://scenes/debug_panel.tscn").instantiate()
	root.add_child(mob_panel)
	gs.phase = gs.Phase.OPEN
	day_events._mob_instances["mob_ui_probe"] = {"type": "dock_workers", "count": 4}
	mob_panel._open = open_script.new([{ "name": "test", "customers": ["mob_ui_probe"] }])
	gs.set_soup("bone_broth", ["meaty"], 2, 2, 2)
	gs.dashi_units = 1
	gs.add_water() # remaining4, strength0, water1
	mob_panel._load_current_customer()
	while mob_panel.flow.runner.status != EventRunner.Status.WAITING_INPUT:
		mob_panel._on_next_event_pressed()
	mob_panel._on_discard_pressed() # remaining0, strength0; this is an enabled UI action.
	mob_panel._on_pot_pressed() # Enabled because dashi exists.
	await process_frame
	var mob_buttons := []
	for btn in mob_panel._options_row.get_children():
		mob_buttons.append({"label": btn.text, "disabled": btn.disabled})
	results["mob_zero_lock"] = {"soup": gs.soup.duplicate(), "dashi": gs.dashi_units,
		"pot_buttons": mob_buttons, "next_event_disabled": mob_panel._btn_next_event.disabled,
		"complete_disabled": mob_panel._btn_complete_input.disabled, "close_disabled": mob_panel._btn_close.disabled,
		"phase_blocked": mob_panel.flow.is_advance_blocked()}
	mob_panel.free()

	gs.reset_for_new_game()
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	root.add_child(panel)
	var wake_cash: int = gs.money
	results["wake_bills"] = {"cash": wake_cash, "pending_label": gs.pending_bills_today,
		"actual_unpaid": gs.RENT_PRICE + gs.WATER_PRICE}
	panel.flow.advance_phase()
	panel._on_next_event_pressed()
	panel._on_prep_tier_selected("large")
	while not panel._is_in_market():
		panel._on_next_event_pressed()
	var before_buy: int = gs.money
	# Normal market purchases can consume all but 30 before unannounced water charge.
	for unused in range(7):
		panel._on_shop_item_selected("produce", "winter_melon")
	var after_buy: int = gs.money
	panel._on_market_exit_pressed()
	results["water_fee_game_over"] = {"cash_before_buy": before_buy, "cash_after_buy": after_buy,
		"phase_after_exit": gs.Phase.keys()[gs.phase], "reason": str(panel.flow.runner.current()),
		"log_exists": FileAccess.file_exists("user://balance_log.jsonl")}
	panel.free()

	gs.reset_for_new_game()
	panel = load("res://scenes/debug_panel.tscn").instantiate()
	root.add_child(panel)
	gs.phase = gs.Phase.OPEN
	panel._open = open_script.new([{ "name": "test", "customers": ["thug"] }])
	gs.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	panel._load_current_customer()
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT:
		panel._on_next_event_pressed()
	await process_frame
	await process_frame
	results["adjust_geometry"] = {"window_size": root.size, "panel_size": panel.size,
		"options_size": panel._options_row.size, "options_minimum": panel._options_row.get_combined_minimum_size(),
		"options_count": panel._options_row.get_child_count()}
	results["new_game_cash"] = gs.money
	for goods in [day_events.produce_goods(), day_events.meat_wholesale_goods(), day_events.dry_goods_goods(), day_events.tofu_noodles_goods(), day_events.seafood_goods(), day_events.scraps_goods()]:
		for good in goods:
			if good.has("item"):
				gs.add_inventory(good["item"], good["count"])
	panel._load_current_customer()
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT:
		panel._on_next_event_pressed()
	await process_frame
	await process_frame
	results["full_inventory_geometry"] = {"panel_size": panel.size, "options_size": panel._options_row.size,
		"options_minimum": panel._options_row.get_combined_minimum_size(), "options_count": panel._options_row.get_child_count()}
	panel.free()
	var out := FileAccess.open("res://planning/playtest_2026_09_26/ui_probe_results.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(results, "\t"))
	out.close()
	print(JSON.stringify(results))
	quit()
