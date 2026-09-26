extends RefCounted
## ②拒否と部分提供（BALANCE_REDESIGN_PLAN.md §6）の検証。対象はモブ客の団体オーダーだけ。
## 経済数値・判定ロジック・名前あり客/配達員のフローは変更していないことも合わせて確認する。

const MOB_ID := "mob_test"


## 行の中の現在のボタンtextを読み取り、その場でfree()する（queue_free()は次のアイドル
## フレームまで実removeが遅延するため、フレームを進めないヘッドレステスト内で
## _update_options_row()を何度も呼ぶと、古いボタンがget_children()に残り続けて
## しまう。テスト内で複数回ボタン内容を確認する箇所だけ、この関数で都度きれいにする）。
func _button_texts(row: HBoxContainer) -> Array:
	var texts := []
	for child in row.get_children():
		texts.append(str(child.text))
	for child in row.get_children():
		child.free()
	return texts


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
	c.check("断りは判定されない(resultsは空扱い)", rec.get("results", {}) == { "": 0 }, str(rec))

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

	# --- 8. 「挑戦する」を選ぶと、達成可能分をレシピ1として即確定し、残りを新しい具材で
	#        レシピ2として提供できる。最終的にrecord_servedは1件に統合される（団体客の
	#        分割提供：最大2レシピ）。
	panel = _setup(t, 4, { "meat_ball": 3, "offal": 10, "nam_prik_pao": 10 })
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("meat_ball", false)
	_button_texts(panel._options_row)   # 具材選択中に積んだボタンを掃除（queue_free()の遅延対策）
	panel._on_complete_input_pressed()
	c.check("レシピ1: 達成可能人数は3(肉団子律速)", panel._mob_achievable_servings(4) == 3)
	var btn_texts_1 := _button_texts(panel._options_row)
	c.check("レシピ1では3択(提供/断る/挑戦する)が出る", btn_texts_1.size() == 3, str(btn_texts_1))
	var served_before8: int = GameState.served.size()
	panel._on_group_retry_pressed(3, 4)
	panel._on_next_event_pressed()   # SERVE -> REACT（レシピ1確定・レシピ2のADJUSTを差し込む）
	c.check("挑戦する選択直後はまだrecord_servedされない(レシピ2待ち)",
		GameState.served.size() == served_before8)
	c.check("肉団子は3個消費される(在庫0)", not GameState.inventory.has("meat_ball"))
	c.check("レシピ番号が2に進む", panel._mob_recipe_number == 2)
	panel._on_next_event_pressed()   # REACT -> 新しいADJUST(new_bowl)
	c.check("レシピ2のADJUSTに入る(WAITING_INPUT)",
		panel.flow.runner.current()["type"] == "ADJUST"
		and panel.flow.runner.status == EventRunner.Status.WAITING_INPUT)
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("offal", false)
	_button_texts(panel._options_row)   # 具材選択中に積んだボタンを掃除
	panel._on_complete_input_pressed()
	c.check("レシピ2: 達成可能人数は残り1", panel._mob_achievable_servings(1) == 1)
	var btn_texts_2 := _button_texts(panel._options_row)
	c.check("レシピ2は2択のみ(挑戦するは出ない・最大2レシピ)",
		btn_texts_2.size() == 2, str(btn_texts_2))
	panel._on_group_serve_pressed(1, 1)
	panel._on_next_event_pressed()   # SERVE -> REACT（レシピ2確定・ここでflush）
	c.check("2レシピぶんが1件のrecord_servedにまとまる",
		GameState.served.size() == served_before8 + 1)
	var rec8: Dictionary = GameState.served[GameState.served.size() - 1]
	c.check("servings=4(3+1) / ordered_servings=4(元の総注文人数) / unserved_servings=0",
		int(rec8.get("servings")) == 4 and int(rec8.get("ordered_servings")) == 4
		and int(rec8.get("unserved_servings")) == 0, str(rec8))
	c.check("declined=falseで記録される", rec8.get("declined") == false)
	c.check("resultsはGOODが4件(両レシピともHOT+POWER一致)",
		int(rec8.get("results", {}).get("GOOD", 0)) == 4, str(rec8.get("results")))
	c.check("_log_quality_countsのGOODも合計4(レシピごとの二重加算をしていない)",
		int(panel._log_quality_counts.get("GOOD", 0)) == 4, str(panel._log_quality_counts))

	# --- 9. 挑戦した2回目も鍋残量律速で不足する場合、record_servedのunserved_servingsは
	#        両レシピ合計後の最終的な不足人数になる。レシピ2は達成可能0でも「断る」だけは
	#        出る（挑戦するボタンは最大2レシピの打ち止めで出ない）。
	panel = _setup(t, 4, { "meat_ball": 3, "offal": 10, "nam_prik_pao": 10 }, 3)
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("meat_ball", false)
	panel._on_complete_input_pressed()
	c.check("レシピ1: 達成可能人数は3(鍋残量3)", panel._mob_achievable_servings(4) == 3)
	var served_before9: int = GameState.served.size()
	panel._on_group_retry_pressed(3, 4)
	panel._on_next_event_pressed()   # SERVE -> REACT
	panel._on_next_event_pressed()   # REACT -> 新しいADJUST
	c.check("鍋残量は使い切って0", int(GameState.soup["remaining_servings"]) == 0)
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("offal", false)
	_button_texts(panel._options_row)   # 具材選択中に積んだボタンを掃除
	panel._on_complete_input_pressed()
	c.check("レシピ2: 鍋残量0なので達成可能人数は0", panel._mob_achievable_servings(1) == 0)
	var btn_texts_9 := _button_texts(panel._options_row)
	c.check("達成可能0のレシピ2は「断る」のみ(提供も挑戦するも出ない)",
		btn_texts_9.size() == 1 and btn_texts_9[0] == "注文を断る", str(btn_texts_9))
	panel._on_group_decline_pressed(1)
	panel._on_next_event_pressed()   # SERVE -> REACT（レシピ2は断り。ここでflush）
	var rec9: Dictionary = GameState.served[GameState.served.size() - 1]
	c.check("2レシピ合計でservings=3 / ordered_servings=4 / unserved_servings=1",
		int(rec9.get("servings")) == 3 and int(rec9.get("ordered_servings")) == 4
		and int(rec9.get("unserved_servings")) == 1, str(rec9))
	c.check("全体としては1レシピぶん提供できたのでdeclined=false", rec9.get("declined") == false)
	c.check("record_servedはこのケースも1件のみ",
		GameState.served.size() == served_before9 + 1)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
