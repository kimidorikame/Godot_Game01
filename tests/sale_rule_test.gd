extends RefCounted
## F3 販売判定・品質判定（DESIGN.md 10.3.1・10.3.2・10.3.6）の検証。
## 対象：SaleRule（具・味のどちらかが欠けた椀は提供不可）、Judge v2（一致1個＋好物は
## OKのまま）、名前あり客の[客を断る]操作。経済数値・既存の残量/濃さ判定は変更していない
## ことも合わせて確認する。

func _setup(t: SceneTree, customers: Array, inventory: Dictionary):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel._load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 名前あり客(thug: MELLOW+GENTLE要求・好物meat_ball)：何も入れていない椀は
	#         [入力完了]が無効かつハンドラを呼んでも進まない ---
	var panel = _setup(t, ["thug"], { "nam_prik_pao": 5, "meat_ball": 5 })
	panel._refresh()
	c.check("具材を何も選んでいない椀は[入力完了]が無効", panel._btn_complete_input.disabled)
	var before_type: String = str(panel.flow.runner.current().get("type", ""))
	panel._on_complete_input_pressed()
	c.check("ハンドラを直接呼んでも進まない(二重防御)",
		str(panel.flow.runner.current().get("type", "")) == before_type)

	# --- 2. 味付けだけ(nam_prik_pao=HOT。具の軸を持たない)は不可 ---
	panel._on_ingredient_selected("nam_prik_pao")
	c.check("味付けのみの椀は[入力完了]が無効(具が無い)", panel._btn_complete_input.disabled)
	panel._on_complete_input_pressed()
	c.check("味付けのみでは進まない",
		str(panel.flow.runner.current().get("type", "")) == before_type)

	# --- 3. 廃棄して作り直し、具だけ(meat_ball=POWER。味の軸を持たない)も不可 ---
	panel._on_discard_pressed()
	panel._on_ingredient_selected("meat_ball", false)
	c.check("具のみの椀は[入力完了]が無効(味付けが無い)", panel._btn_complete_input.disabled)

	# --- 4. 両方入れれば[入力完了]が有効になり、通常どおり進む ---
	panel._on_ingredient_selected("nam_prik_pao")
	c.check("味・具の両方が入れば[入力完了]が有効になる", not panel._btn_complete_input.disabled)
	panel._on_complete_input_pressed()
	c.check("両方入れれば進む(SERVEへ)",
		str(panel.flow.runner.current().get("type", "")) == "SERVE")

	# --- 5. モブ客：具のみ(味の軸を持たない)の椀は達成可能人数が0になる ---
	panel = _setup(t, ["mob_sale_test"], { "meat_ball": 10 })
	GameState.today_plan["mob_instances"]["mob_sale_test"] = { "type": "dock_workers", "count": 4 }
	panel._on_ingredient_selected("meat_ball", false)
	c.check("具のみの椀はモブの達成可能人数も0になる(SaleRuleはモブにも効く)",
		panel._mob_achievable_servings(4) == 0)

	# --- 6. [客を断る]：達成可能でも問答無用で断れる。判定・消費・売上が一切発生しない ---
	panel = _setup(t, ["thug"], { "nam_prik_pao": 5, "meat_ball": 5 })
	var money0: int = GameState.money
	var stock0: int = int(GameState.inventory.get("meat_ball", 0))
	var soup0: int = int(GameState.soup["remaining_servings"])
	var served_before: int = GameState.served.size()
	panel._on_customer_decline_pressed()
	panel._on_next_event_pressed()   # SERVE -> REACT
	c.check("断ると具材は減らない", int(GameState.inventory.get("meat_ball", 0)) == stock0)
	c.check("断ると鍋残量は減らない", int(GameState.soup["remaining_servings"]) == soup0)
	c.check("断ると所持金は変わらない", GameState.money == money0)
	c.check("record_servedが1件増える", GameState.served.size() == served_before + 1)
	var rec: Dictionary = GameState.served[GameState.served.size() - 1]
	c.check("断りはservings=0・declined=true・result=空で記録される",
		int(rec.get("servings")) == 0 and rec.get("declined") == true
		and str(rec.get("result", "?")) == "", str(rec))

	# --- 7. モブは既存どおり、全員分そろっていても「注文を断る」を選べる(回帰) ---
	panel = _setup(t, ["mob_sale_test2"], { "nam_prik_pao": 10, "meat_ball": 10 })
	GameState.today_plan["mob_instances"]["mob_sale_test2"] = { "type": "dock_workers", "count": 4 }
	panel._on_ingredient_selected("nam_prik_pao")
	panel._on_ingredient_selected("meat_ball", false)
	panel._on_complete_input_pressed()
	c.check("モブは達成可能=注文人数でも断るボタン相当が成立する(回帰)",
		panel._mob_achievable_servings(4) == 4)

	# --- 8. Judge v2：一致1個+好物ありはOKのまま(GOODへは上がらない) ---
	GameState.reset_for_new_game()
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	var open := OpenController.new([])
	open.current_bowl = { "additions": ["meat_ball"] }   # POWERのみ一致、好物ありのつもり
	var result_1match := open.judge_bowl(["POWER", "MELLOW"], "meat_ball")
	c.check("一致1個+好物ありはOKのまま(GOODにならない)", result_1match == "OK", result_1match)

	# --- 9. Judge v2：一致2個+好物ありはGREAT(回帰。3-1以前と変わらない) ---
	open.current_bowl = { "additions": ["nam_prik_pao", "meat_ball"] }
	var result_2match := open.judge_bowl(["HOT", "POWER"], "meat_ball")
	c.check("一致2個+好物ありはGREAT(回帰)", result_2match == "GREAT", result_2match)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
