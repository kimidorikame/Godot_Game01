extends RefCounted
## ③初回好物の開示（BALANCE_REDESIGN_PLAN.md §4）の検証。対象は名前あり客だけ。
## 経済数値・判定ロジック本体（judge_bowl）・モブの扱いは変更していないことも合わせて
## 確認する。

func _setup(t: SceneTree, customers: Array, inventory: Dictionary):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が自動でinitial_inventory()を積む
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	return panel


func _drive_to_adjust(panel) -> void:
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1〜2. 老婆（favorite: offal, 要求: SAVORY+FILLING）。1回目はGOOD止まり、
	#     2回目（好物を知った後）は同じ構成でGREATになる ---
	var panel = _setup(t, ["granny"], { "herbal_sauce": 5, "broken_wrapper": 5, "offal": 5 })
	_drive_to_adjust(panel)
	c.check("下準備: 老婆はまだ好物を知られていない", not GameState.knows_favorite("granny"))
	panel._on_ingredient_selected("herbal_sauce")
	panel._on_ingredient_selected("broken_wrapper")
	panel._on_ingredient_selected("offal")
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()   # SERVE -> REACT
	c.check("初回：要求2つ一致+好物を入れてもGREATにならない(GOOD止まり)",
		str(panel._open.current_bowl.get("result", "")) == "GOOD",
		str(panel._open.current_bowl.get("result", "")))
	c.check("初回の判定に使ったfavoriteは空(current_bowl)",
		str(panel._open.current_bowl.get("favorite", "")) == "")
	c.check("退店(このREACTの直後)で老婆の好物は知った扱いになる", GameState.knows_favorite("granny"))

	# --- 2回目の来店（同じ構成）：知っているのでGREATになる ---
	panel._open = OpenController.new([{ "name": "宵の口", "customers": ["granny"] }])
	GameState.add_inventory("herbal_sauce", 5)
	GameState.add_inventory("broken_wrapper", 5)
	GameState.add_inventory("offal", 5)
	panel._load_current_customer()
	_drive_to_adjust(panel)
	panel._on_ingredient_selected("herbal_sauce")
	panel._on_ingredient_selected("broken_wrapper")
	panel._on_ingredient_selected("offal")
	panel._on_complete_input_pressed()
	panel._on_next_event_pressed()
	c.check("2回目：同じ構成でGREATになる",
		str(panel._open.current_bowl.get("result", "")) == "GREAT",
		str(panel._open.current_bowl.get("result", "")))
	c.check("2回目の判定に使ったfavoriteは本来の値(offal)",
		str(panel._open.current_bowl.get("favorite", "")) == "offal")
	c.check("_format_bowlに本来の好物とknown=trueが出る(2回目)",
		panel._format_bowl().contains("favorite_true(本来の好物・デバッグ): offal (known=true)"),
		panel._format_bowl())

	# --- 3〜4. 配達員（aggregate:true・favorite: tofu）：1杯目の直後ではまだ知らない扱い、
	#     3杯すべて終えて退店した後に初めて知った扱いになる ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel2 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel2)
	GameState.phase = GameState.Phase.OPEN
	panel2._open = OpenController.new([{ "name": "宵の口", "customers": ["delivery_man"] }])
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel2._load_current_customer()
	c.check("下準備: 配達員はまだ好物を知られていない", not GameState.knows_favorite("delivery_man"))
	var guard := 0
	var picks := [["nam_prik_pao", "offal", "tofu"], ["nam_prik_pao", "tofu"], ["nam_prik_pao"]]
	var ai := 0
	while str(panel2._open.current_customer()) == "delivery_man" and guard < 400:
		guard += 1
		if panel2.flow.runner.status == EventRunner.Status.WAITING_INPUT:
			for id in picks[ai]:
				panel2._on_ingredient_selected(id)
			ai += 1
			panel2._on_complete_input_pressed()
		else:
			panel2._on_next_event_pressed()
			var cur = panel2.flow.runner.current()
			if ai == 1 and cur is Dictionary and cur.get("type", "") == "REACT":
				# 1杯目のREACTが適用された直後（まだ2杯目のGREETより前）。
				c.check("1杯目の判定直後もまだ知った扱いにならない(退店前)",
					not GameState.knows_favorite("delivery_man"))
	c.check("3杯すべて終えて退店した後は知った扱いになる", GameState.knows_favorite("delivery_man"))

	# --- 5. reset_for_new_game() で既知状態がリセットされる ---
	# (直前でGameState.reset_for_new_game()を挟んでいるため、老婆の既知状態はここでは
	#  すでに消えている＝それ自体がreset_for_new_game()の効果の証拠。配達員はその後
	#  改めて知った状態にしたので、それがリセットで消えることを確認する)
	c.check("リセット前は配達員が既知", GameState.knows_favorite("delivery_man"))
	GameState.reset_for_new_game()
	c.check("reset_for_new_game()でknown_favoritesが空になる", GameState.known_favorites.is_empty())

	# --- 6. モブは対象外（favoriteは常に空。今回の変更による回帰がないことの確認） ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel3 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel3)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	Day1Events._mob_instances["mob_fav_test"] = { "type": "dock_workers", "count": 2 }
	panel3._open = OpenController.new([{ "name": "宵の口", "customers": ["mob_fav_test"] }])
	GameState.add_inventory("nam_prik_pao", 5)
	GameState.add_inventory("meat_ball", 5)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel3._load_current_customer()
	_drive_to_adjust(panel3)
	panel3._on_ingredient_selected("nam_prik_pao")
	panel3._on_ingredient_selected("meat_ball", false)
	panel3._on_complete_input_pressed()
	panel3._on_group_serve_pressed(2, 2)
	panel3._on_next_event_pressed()
	c.check("モブの判定はGOOD(要求2つ一致・好物なしなのでGREATにはならない)",
		str(panel3._open.current_bowl.get("result", "")) == "GOOD",
		str(panel3._open.current_bowl.get("result", "")))

	# --- 7. _format_bowl() の新しい行（モブはfavoriteが空なので行自体が出ない） ---
	c.check("モブはfavorite_true行が出ない(favoriteが常に空のため)",
		not panel3._format_bowl().contains("favorite_true"))
	c.check("_format_game_stateにknown_favoritesの一覧が出る",
		panel3._format_game_state().contains("known_favorites"))

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
