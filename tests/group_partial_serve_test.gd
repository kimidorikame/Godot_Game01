extends RefCounted
## ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6）の検証。対象はモブ客の団体オーダーだけ。
## 経済数値・判定ロジック・名前あり客/配達員のフローは変更していないことも合わせて確認する。

const MOB_ID := "mob_test"


func _setup(t: SceneTree, mob_count: int, inventory: Dictionary, kettle_remaining: int = 999):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が自動でinitial_inventory()を積む
	# 今回のテストは各具材の在庫数を厳密に指定したいため、自動で積まれた初期在庫を
	# 一旦クリアしてから、指定した個数だけを積み直す（初期在庫と合算されると期待値がずれる）。
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	Day1Events._mob_instances[MOB_ID] = { "type": "dock_workers", "count": mob_count }
	panel._open = OpenController.new([{ "name": "宵の口", "customers": [MOB_ID] }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], kettle_remaining, 3, 2)
	panel._load_current_customer()
	# GREETを読み進めてADJUST（options持ちのWAITING_INPUT）まで進める。
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 50:
		guard += 1
		panel._on_next_event_pressed()
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 具材不足：4人組・肉団子(POWER)が3個のみ。ナムプリックパオ(HOT)は十分にあるので
	#        要求タグ(HOT+POWER)は2つとも一致しGOOD判定になる（好物はモブに無いのでGREATなし）。
	var panel = _setup(t, 4, { "meat_ball": 3, "nam_prik_pao": 10 })
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("meat_ball", false)
	c.check("在庫はまだ引かれない(選択時点)", GameState.inventory.get("meat_ball", 0) == 3)
	panel._on_complete_input_pressed()
	c.check("1回目の[入力完了]は進まず確認状態になる", panel._pending_group_choice
		and panel.flow.runner.current()["type"] == "ADJUST")
	c.check("達成可能人数は3(具材律速)", panel._mob_achievable_servings(4) == 3)
	var money0: int = GameState.money
	var rep0: int = GameState.reputation
	panel._on_group_serve_pressed(3, 4)
	panel._on_next_event_pressed()   # SERVE -> REACT
	c.check("肉団子は3個消費される(在庫0)", not GameState.inventory.has("meat_ball"))
	c.check("鍋残量は3減る", int(GameState.soup["remaining_servings"]) == 999 - 3)
	c.check("売上は3人分", GameState.money == money0 + 3 * GameState.PRICE_PER_SERVING,
		str(GameState.money - money0))
	# ④評判の更新：評判は閉店時に1回だけ確定するため、提供直後は動かない
	# （tests/reputation_demand_test.gdで閉店時の確定を別途検証する）。
	c.check("評判は提供直後には動かない(閉店時に一括確定)", GameState.reputation == rep0)
	c.check("代わりに_log_quality_countsのGOODが3(提供人数)だけ増える",
		int(panel._log_quality_counts.get("GOOD", 0)) == 3, str(panel._log_quality_counts))
	var rec: Dictionary = GameState.served[GameState.served.size() - 1]
	c.check("servings=3 / ordered_servings=4 / unserved_servings=1が記録される",
		int(rec.get("servings")) == 3 and int(rec.get("ordered_servings")) == 4
		and int(rec.get("unserved_servings")) == 1, str(rec))
	c.check("declined=falseで記録される", rec.get("declined") == false)

	# --- 2. 全員分そろっていても「注文を断る」を選べ、断ると何も動かない ---
	panel = _setup(t, 4, { "meat_ball": 10 })
	panel._on_ingredient_selected("meat_ball", false)
	panel._on_complete_input_pressed()
	c.check("全員分そろっていても両方のボタン相当が成立(達成可能=注文人数)",
		panel._mob_achievable_servings(4) == 4)
	money0 = GameState.money
	rep0 = GameState.reputation
	var stock0: int = int(GameState.inventory.get("meat_ball", 0))
	var soup0: int = int(GameState.soup["remaining_servings"])
	panel._on_group_decline_pressed(4)
	panel._on_next_event_pressed()
	c.check("断ると具材は減らない", int(GameState.inventory.get("meat_ball", 0)) == stock0)
	c.check("断ると鍋残量は減らない", int(GameState.soup["remaining_servings"]) == soup0)
	c.check("断ると所持金は変わらない", GameState.money == money0)
	c.check("断ると評判は変わらない(仕様7)", GameState.reputation == rep0)
	rec = GameState.served[GameState.served.size() - 1]
	c.check("断りはservings=0・declined=trueで記録される",
		int(rec.get("servings")) == 0 and rec.get("declined") == true
		and int(rec.get("ordered_servings")) == 4, str(rec))
	c.check("断りは判定されない(resultが空)", str(rec.get("result", "?")) == "")

	# --- 3. 新鮮2個＋傷み2個を「新鮮4人分」にはしない(仕様3) ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	GameState.add_inventory("offal", 2)
	GameState.day_count = 3
	GameState.add_inventory("offal", 2)
	panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.phase = GameState.Phase.OPEN
	Day1Events._mob_instances[MOB_ID] = { "type": "dock_workers", "count": 4 }
	panel._open = OpenController.new([{ "name": "宵の口", "customers": [MOB_ID] }])
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	var guard3 := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard3 < 50:
		guard3 += 1
		panel._on_next_event_pressed()
	c.check("下準備: offalは新鮮2・傷み2", GameState.fresh_count("offal") == 2 and GameState.damaged_count("offal") == 2)
	panel._on_ingredient_selected("offal", false)   # 新鮮ボタン
	panel._on_complete_input_pressed()
	c.check("新鮮ボタンでは新鮮在庫数(2)が上限。傷みと合算した4にはならない",
		panel._mob_achievable_servings(4) == 2, str(panel._mob_achievable_servings(4)))

	# --- 4. 同じ具材(同バケツ)を2枠選ぶと、在庫数を選んだ回数で割る ---
	panel = _setup(t, 4, { "meat_ball": 6 })
	panel._on_ingredient_selected("meat_ball", false)
	panel._on_ingredient_selected("meat_ball", false)
	panel._on_complete_input_pressed()
	c.check("肉団子6個を2枠で使うと達成可能人数は3(6÷2)",
		panel._mob_achievable_servings(4) == 3, str(panel._mob_achievable_servings(4)))

	# --- 5. 鍋残量が具材より少ない場合(鍋律速) ---
	panel = _setup(t, 4, { "meat_ball": 10 }, 2)
	panel._on_ingredient_selected("meat_ball", false)
	panel._on_complete_input_pressed()
	c.check("鍋残量2が上限になる", panel._mob_achievable_servings(4) == 2)

	# --- 6. 具材を1つも選ばなくても、鍋残量の範囲で提供できる(具材不足はゼロではない) ---
	panel = _setup(t, 4, {})
	panel._on_complete_input_pressed()
	c.check("具材なしでも鍋律速の人数までは提供扱いになる", panel._mob_achievable_servings(4) == 4)

	# --- 7. 名前あり客(servings=1)は無変更で動く(回帰) ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel2 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel2)
	panel2._seed_initial_inventory()
	GameState.phase = GameState.Phase.OPEN
	panel2._open = OpenController.new([{ "name": "宵の口", "customers": ["thug"] }])
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	panel2._load_current_customer()
	var guard7 := 0
	while panel2.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard7 < 50:
		guard7 += 1
		panel2._on_next_event_pressed()
	c.check("名前あり客はis_mobでない", not panel2._is_current_mob_order())
	panel2._on_ingredient_selected("nam_prik_pao")
	panel2._on_complete_input_pressed()
	c.check("名前あり客は[入力完了]1回で即座に進む(確認状態にならない)",
		not panel2._pending_group_choice and panel2.flow.runner.current()["type"] == "SERVE")
	c.check("名前あり客は選んだ瞬間に在庫が減る(即時消費のまま)",
		int(GameState.inventory.get("nam_prik_pao", 0)) == 9)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
