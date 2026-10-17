extends RefCounted
## レシピ保存と「いつもの」（フェーズ4・手順4-7①。DESIGN.md 10.4・10.4.1）の検証。
## 保存レシピ（最大3枠・名前は候補6つ・朝の保存に含む＝版6）、「いつもの」の引き当て、適用が
## 「具材ボタンを順に押したのと同じ処理」であること（在庫・鮮度の確認と消費は省略しない）、
## 椀が空のときだけ・新鮮な在庫が足りるときだけ有効、保存は提供後〜その客の最後の行まで、
## 同一注文の入力操作が30%以上短縮されること。
## 場面データはキャッシュへ注入しない箇所以外は実データ（Day2のチンピラ＝thug_02。基本注文 MELLOW/GENTLE）。

const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]


func _visit(day: int, grades: Array, cups: Array) -> Dictionary:
	var served := 0
	for g in grades:
		served += 1
	return { "day": day, "slot": "宵の口", "served": served, "grade": "", "grades": grades,
		"ingredients": cups, "episode_id": "thug_01" }


func _memory_with(visits: Array) -> void:
	GameState.customer_memory["thug"] = { "favorite_known": false, "facts": {}, "seen_episodes": [], "visits": visits.duplicate(true) }


## Day2のWAKEを通し、チンピラ→老婆の接客のADJUST待ちまで進める。seed_value で乱数列をそろえる。
func _setup(t: SceneTree, seed_value: int = 1, visits: Array = []):
	seed(seed_value)
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": ["thug", "granny"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	if not visits.is_empty():
		_memory_with(visits)
	panel._load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel._on_next_event_pressed()
	return panel


func _row_buttons(panel) -> Array:
	var out := []
	for child in panel._recipe_row.get_children():
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _labels(buttons: Array) -> Array:
	var out := []
	for b in buttons:
		out.append(b.text)
	return out


func _json(value) -> String:
	return JSON.stringify(value)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()

	# --- 1. 枠数と名前の候補（データから） ---
	c.check("保存レシピの枠数は3（week7.json の recipe_slots）", Rules.recipe_slots() == 3 and RecipeBook.slot_count() == 3)
	var names := RecipeBook.names()
	c.check("名前の候補は6つ（10.4.1）で、名前とタグがある",
		names.size() == 6 and names[0]["name"] == "港湾夜勤の赤油つみれ湯" and names[0]["tags"] == ["HOT", "POWER"]
			and names[5]["name"] == "割れ雲呑皮のまかない湯" and (names[2]["tags"] as Array).size() == 3)
	c.check("椀のタグを含む候補を先頭に並べる（HOT/POWER → 赤油つみれ湯）",
		RecipeBook.names_ordered(["HOT", "POWER", "SOUR"])[0]["id"] == "red_oil_meatball")
	c.check("MELLOW/GENTLE → 椰子豆腐湯が先頭。残りは全部ある（6つ）",
		RecipeBook.names_ordered(["MELLOW", "GENTLE"])[0]["id"] == "coconut_tofu" and RecipeBook.names_ordered(["MELLOW", "GENTLE"]).size() == 6)
	c.check("どの候補にも合わない椀はデータの順のまま（名前は表示だけで選べる）",
		_json(RecipeBook.names_ordered([])) == _json(names))

	# --- 2. 保存・上書き・最大3枠 ---
	GameState.reset_for_new_game()
	c.check("空き枠（0）へ保存できる", RecipeBook.save(0, "A", ["coconut_milk", "tofu"]) and GameState.saved_recipes.size() == 1)
	c.check("枠を飛ばした保存（2番）はできない", not RecipeBook.save(2, "C", ["tofu", "offal"]) and GameState.saved_recipes.size() == 1)
	c.check("次の空き枠（1・2）へ保存できる", RecipeBook.save(1, "B", ["offal", "tofu"]) and RecipeBook.save(2, "C", ["meat_ball", "tofu", "offal"])
		and GameState.saved_recipes.size() == 3)
	c.check("4枠目はできない（最大3枠）", not RecipeBook.save(3, "D", ["tofu", "offal"]) and GameState.saved_recipes.size() == 3)
	c.check("保存済みの枠は上書きできる", RecipeBook.save(0, "A2", ["tofu", "offal"]) and GameState.saved_recipes[0]["name"] == "A2"
		and GameState.saved_recipes[0]["ingredients"] == ["tofu", "offal"] and GameState.saved_recipes.size() == 3)
	var before_bad := _json(GameState.saved_recipes)
	c.check("不正なレシピ（具材なし・4個・名前なし・空の具材id）は保存しない",
		not RecipeBook.save(0, "X", []) and not RecipeBook.save(0, "X", ["a", "b", "c", "d"])
			and not RecipeBook.save(0, "", ["tofu"]) and not RecipeBook.save(0, "X", [""]) and _json(GameState.saved_recipes) == before_bad)
	var src := ["tofu", "offal"]
	RecipeBook.save(1, "B2", src)
	src.append("meat_ball")
	c.check("保存は具材の配列を複製する（元を書き換えても保存は変わらない）", GameState.saved_recipes[1]["ingredients"] == ["tofu", "offal"])

	# --- 3. 朝の保存：項目・往復・版6・型検査・旧版の拒否 ---
	c.check("saved_recipes は朝の保存の項目（SAVED_FIELDS）", GameState.SAVED_FIELDS.has("saved_recipes"))
	var d := GameState.to_dict()
	GameState.reset_for_new_game()
	c.check("新しい周では空に戻る", GameState.saved_recipes.is_empty())
	GameState.from_dict(d)
	c.check("to_dict→from_dict で戻る（深いコピー）", GameState.saved_recipes.size() == 3 and GameState.saved_recipes[2]["name"] == "C")
	(d["saved_recipes"][0]["ingredients"] as Array).append("zzz")
	c.check("戻した後に元の辞書を書き換えても変わらない", GameState.saved_recipes[0]["ingredients"] == ["tofu", "offal"])
	var env := MorningSave.capture("")
	c.check("封筒の版は6で、保存レシピを持つ封筒は有効", MorningSave.VERSION == 6 and int(env["version"]) == 6 and MorningSave.is_valid(env))
	var v5 := env.duplicate(true)
	v5["version"] = 5
	c.check("版5以前の保存は読めない扱い（新規ゲーム）", not MorningSave.is_valid(v5))
	var not_array := env.duplicate(true)
	not_array["state"]["saved_recipes"] = {}
	c.check("saved_recipes が配列でないと弾く", not MorningSave.is_valid(not_array))
	var missing := env.duplicate(true)
	missing["state"].erase("saved_recipes")
	c.check("saved_recipes が無い封筒は弾く", not MorningSave.is_valid(missing))
	var too_many := env.duplicate(true)
	too_many["state"]["saved_recipes"].append({ "name": "D", "ingredients": ["tofu"] })
	c.check("枠数（3）を超えると弾く", not MorningSave.is_valid(too_many))
	for bad in [{ "name": 5, "ingredients": ["tofu"] }, { "name": "x", "ingredients": "tofu" }, { "name": "x", "ingredients": [] },
			{ "name": "x", "ingredients": ["a", "b", "c", "d"] }, { "name": "x", "ingredients": [1] }, "x"]:
		var bad_env := env.duplicate(true)
		bad_env["state"]["saved_recipes"][0] = bad
		c.check("不正なレシピ %s を弾く" % str(bad), not MorningSave.is_valid(bad_env))
	var saved_path := MorningSave.save_path
	MorningSave.save_path = "user://recipe_test.dat"
	MorningSave.delete_file()
	c.check("ファイルへ書いて読むと保存レシピが型ごと戻る", MorningSave.write_file(env)
		and _json(MorningSave.read_file()["state"]["saved_recipes"]) == _json(GameState.saved_recipes))
	MorningSave.delete_file()
	MorningSave.save_path = saved_path

	# --- 4. 再挑戦：戻した朝より後の保存は消える ---
	var p4 = _setup(t)
	c.check("（前提）Day2の朝の記録がある。その朝に保存レシピは無い", GameState.morning_snapshots.has(2) and GameState.saved_recipes.is_empty())
	RecipeBook.save(0, "朝のあと", ["tofu", "offal"])
	c.check("朝のあとに保存した", GameState.saved_recipes.size() == 1)
	c.check("朝へ戻すと、その保存は消える", p4.retry_from_morning(2) and GameState.saved_recipes.is_empty())
	p4.free()

	# --- 5. 「いつもの」の引き当て ---
	GameState.reset_for_new_game()
	GameState.day_count = 4
	_memory_with([
		_visit(1, ["GOOD"], [["coconut_milk", "tofu"]]),
		_visit(2, [], []),
		_visit(3, ["GOOD", "", "OK"], [["a1", "a2"], ["b1"], ["c1", "c2"]]),
		_visit(4, ["BAD"], [["today1", "today2"]]),
	])
	c.check("複数杯の来店は最後に評価した杯（OK）の具材。今日（Day4）の来店は含めない",
		RecipeBook.usual_for("thug") == ["c1", "c2"], str(RecipeBook.usual_for("thug")))
	GameState.day_count = 3
	c.check("Day3：今日の来店を除き、断った来店（Day2）を飛ばして Day1 の料理",
		RecipeBook.usual_for("thug") == ["coconut_milk", "tofu"])
	GameState.day_count = 1
	c.check("過去の来店が無ければ空", RecipeBook.usual_for("thug").is_empty() and RecipeBook.usual_for("granny").is_empty())
	GameState.day_count = 4
	_memory_with([_visit(2, [""], [["x1", "x2"]])])
	c.check("評価のない杯（持ち帰りなど）だけの来店は引かない", RecipeBook.usual_for("thug").is_empty())
	var usual := RecipeBook.usual_for("thug")
	GameState.customer_memory.clear()
	c.check("来店記録の無い客・モブは空", RecipeBook.usual_for("thug").is_empty() and RecipeBook.usual_for("mob#0").is_empty() and usual.is_empty())

	# --- 6. 在庫の検査：新鮮な在庫だけ。同じ具材は個数ぶん。名前あり客の人数ぶん ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	GameState.add_inventory("tofu", 2)
	GameState.add_inventory("offal", 1)
	c.check("足りていれば適用できる", RecipeBook.can_apply(["tofu", "offal"], 1) and RecipeBook.shortage(["tofu", "offal"], 1).is_empty())
	c.check("同じ具材を2回使う料理は2個ぶん要る（tofu 2個ならOK、3回は不足）",
		RecipeBook.can_apply(["tofu", "tofu"], 1) and RecipeBook.shortage(["tofu", "tofu", "tofu"], 1) == ["tofu"])
	c.check("1杯の人数（servings）ぶん要る（servings 2 なら tofu 2個で offal は不足）",
		RecipeBook.shortage(["tofu", "offal"], 2) == ["offal"])
	c.check("具材なし・4個は適用できない", not RecipeBook.can_apply([], 1) and not RecipeBook.can_apply(["tofu", "tofu", "offal", "tofu"], 1))
	GameState.day_count = GameState.SPOIL_DAMAGED_DAY   # 1日目の購入分が傷んだ側になる
	c.check("傷んだ在庫は数えない（傷んだ側しか無いと不足）",
		GameState.damaged_count("tofu") == 2 and GameState.fresh_count("tofu") == 0 and RecipeBook.shortage(["tofu"], 1) == ["tofu"]
			and not RecipeBook.can_apply(["tofu"], 1))

	# --- 7. 適用は「具材ボタンを順に押したのと同じ処理」：additions・在庫・来店記録・帳簿まで同一 ---
	var old_visits := [_visit(1, ["GOOD"], [["coconut_milk", "tofu", "meat_ball"]])]
	for case in [["保存レシピ（2つ）", ["coconut_milk", "tofu"], false], ["「いつもの」（3つ）", ["coconut_milk", "tofu", "meat_ball"], true]]:
		var ids: Array = case[1]
		var manual = _setup(t, 77, old_visits)
		for id in ids:
			manual._on_ingredient_selected(id)
		var manual_bowl := _json(manual._open.current_bowl)
		seed(555)
		manual._on_complete_input_pressed()
		manual._on_next_event_pressed()
		var manual_state := _json(GameState.to_dict())
		var manual_extra := _json([GameState.served, GameState.ledger, manual._open.current_bowl])
		manual.free()
		var by_recipe = _setup(t, 77, old_visits)
		if case[2]:
			by_recipe._on_recipe_apply_pressed(RecipeBook.usual_for("thug"))
		else:
			GameState.saved_recipes = [{ "name": "テスト", "ingredients": ids.duplicate() }]
			by_recipe._on_recipe_apply_pressed(GameState.saved_recipes[0]["ingredients"])
		c.check("%s：適用後の椀（additions・鮮度の印）が手で押した場合と同一" % case[0], _json(by_recipe._open.current_bowl) == manual_bowl,
			_json(by_recipe._open.current_bowl))
		seed(555)
		by_recipe._on_complete_input_pressed()
		by_recipe._on_next_event_pressed()
		var recipe_state_dict := GameState.to_dict()
		recipe_state_dict["saved_recipes"] = []   # 保存レシピそのものはこの比較の対象外（手の側に無い）
		var manual_dict = JSON.parse_string(manual_state)
		manual_dict["saved_recipes"] = []
		var diff_keys := []
		var recipe_norm = JSON.parse_string(_json(recipe_state_dict))   # JSONを通した形にそろえて比べる
		for key in recipe_norm:
			if _json(recipe_norm[key]) != _json(manual_dict.get(key)):
				diff_keys.append(key)
		c.check("%s：提供後のGameState（在庫・腐敗・所持金・評判・来店記録・帳簿・DayPlan）まで同一" % case[0],
			diff_keys.is_empty(), str(diff_keys))
		c.check("%s：提供記録・帳簿・椀の判定も同一（レシピの使用は記録しない）" % case[0],
			_json([GameState.served, GameState.ledger, by_recipe._open.current_bowl]) == manual_extra)
		by_recipe.free()

	# --- 8. 無効になる条件：椀が空でない／在庫不足／傷んだ側しか無い／ADJUST以外 ---
	GameState.saved_recipes = []
	var p8 = _setup(t, 5, old_visits)
	GameState.saved_recipes = [{ "name": "保存A", "ingredients": ["coconut_milk", "tofu"] }]
	p8._refresh()
	var labels := _labels(_row_buttons(p8))
	c.check("ADJUSTに「いつもの」と保存レシピのボタンが出る（具材の並びだけ。前回の評価・予測は出さない）",
		labels == ["いつもの（%s）" % RecipeBook.ingredient_text(["coconut_milk", "tofu", "meat_ball"]),
			"保存A（%s）" % RecipeBook.ingredient_text(["coconut_milk", "tofu"])]
			and not str(labels).contains("GOOD") and not str(labels).contains("前回") and not str(labels).contains("合う"),
		str(labels))
	p8._on_ingredient_selected("offal")
	p8._on_recipe_apply_pressed(["coconut_milk", "tofu"])
	c.check("椀が空でないと適用されない（途中の椀には使えない）", p8._open.current_bowl["additions"] == ["offal"])
	c.check("椀が空でない間はボタンも出ない", _row_buttons(p8).is_empty())
	p8._on_discard_pressed()
	p8._refresh()
	c.check("[廃棄する]で空にすると、また出る", not _row_buttons(p8).is_empty())
	# 在庫不足：tofu を0に
	GameState.inventory.erase("tofu")
	GameState.perishable_batches.erase("tofu")
	p8._refresh()
	var short_buttons := _row_buttons(p8)
	var short_text := str(_labels(short_buttons))
	c.check("在庫が足りない具材はラベルに出て、ボタンは無効", short_text.contains("足りない：豆腐")
		and short_buttons.all(func(b): return b.disabled), short_text)
	var stock_before := _json([GameState.inventory, GameState.perishable_batches])
	p8._on_recipe_apply_pressed(["coconut_milk", "tofu"])
	c.check("足りないときは適用されない（一部だけ入る状態を作らない。在庫も不変）",
		(p8._open.current_bowl["additions"] as Array).is_empty() and _json([GameState.inventory, GameState.perishable_batches]) == stock_before)
	# 傷んだ側しか無い（tofu は傷んだ3個だけ）
	GameState.day_count = GameState.SPOIL_DAMAGED_DAY
	GameState.add_inventory("tofu", 0)
	GameState.inventory["tofu"] = 3
	GameState.perishable_batches["tofu"] = [{ "day": 1, "count": 3, "unit_price": 8 }]
	p8._on_recipe_apply_pressed(["coconut_milk", "tofu"])
	c.check("傷んだ側しか無い具材は自動では使わない（適用されない）",
		(p8._open.current_bowl["additions"] as Array).is_empty() and GameState.inventory["tofu"] == 3)
	GameState.day_count = 2
	# ADJUST 以外では出ない・効かない
	p8.free()
	var p8b = _setup(t, 5, old_visits)
	p8b._on_ingredient_selected("coconut_milk")
	p8b._on_ingredient_selected("tofu")
	p8b._on_complete_input_pressed()
	var money_serving: int = GameState.money
	p8b._on_recipe_apply_pressed(["coconut_milk", "tofu"])
	c.check("SERVE／REACT の最中（ADJUSTでない）には適用できない", p8b._open.current_bowl["additions"] == ["coconut_milk", "tofu"]
		and GameState.money == money_serving)
	p8b.free()

	# --- 9. 保存ボタン：提供後〜その客の最後の行まで。段階（保存 → 枠 → 名前）。モブ・断りは対象外 ---
	var p9 = _setup(t, 9)
	c.check("ADJUST中は保存ボタンを出さない（まだ提供前）", not p9._can_save_recipe_now())
	p9._on_ingredient_selected("coconut_milk")
	p9._on_ingredient_selected("tofu")
	p9._on_complete_input_pressed()
	p9._on_next_event_pressed()   # REACT（thug_02 の最後のイベント）
	var last_event: bool = p9.flow.runner.index == p9.flow.runner.events.size() - 1
	c.check("提供後（その客の最後の行でも）保存できる", p9._can_save_recipe_now() and last_event)
	p9._refresh()
	c.check("[レシピを保存] のボタンが出る", _labels(_row_buttons(p9)).size() == 1 and str(_labels(_row_buttons(p9))[0]).begins_with("レシピを保存"))
	p9._on_recipe_save_pressed()
	var slot_labels := _labels(_row_buttons(p9))
	c.check("段階：枠（空き3枠。やめる付き）", slot_labels.size() == 4 and str(slot_labels[0]) == "枠1：空き" and slot_labels[3] == "やめる", str(slot_labels))
	var slot_buttons := _row_buttons(p9)
	c.check("空きの先頭だけ選べる（飛ばした枠は無効）", not slot_buttons[0].disabled and slot_buttons[1].disabled and slot_buttons[2].disabled)
	p9._on_recipe_slot_selected(0)
	var name_labels := _labels(_row_buttons(p9))
	c.check("段階：名前（候補6つ＋やめる。椀のタグを含む候補が先頭）", name_labels.size() == 7 and name_labels[6] == "やめる")
	p9._on_recipe_save_cancel_pressed()
	c.check("やめると何も保存せず最初の段階へ", GameState.saved_recipes.is_empty() and p9._recipe_save_stage == "")
	p9._on_recipe_save_pressed()
	p9._on_recipe_slot_selected(0)
	p9._on_recipe_name_selected("終電後の椰子豆腐湯")
	c.check("名前を選ぶと枠1へ保存（具材はその椀の追加）", GameState.saved_recipes == [{ "name": "終電後の椰子豆腐湯", "ingredients": ["coconut_milk", "tofu"] }],
		_json(GameState.saved_recipes))
	p9._on_recipe_save_pressed()
	p9._on_recipe_slot_selected(0)
	p9._on_recipe_name_selected("港湾夜勤の赤油つみれ湯")
	c.check("保存済みの枠は上書きできる", GameState.saved_recipes.size() == 1 and GameState.saved_recipes[0]["name"] == "港湾夜勤の赤油つみれ湯")
	c.check("保存はゲームの数値に触れない（評価・所持金は提供の結果のまま）", str(p9._open.current_bowl["result"]) != "")
	p9.free()
	# 複数杯の各杯・その客の最後の行まで
	ScheduleData._episode_cache["thug/thug_02"] = { "id": "thug_02", "customer": "thug", "greet": ["来店"],
		"cups": [ { "reactions": { "GOOD": ["R1"], "OK": ["R1"], "GREAT": ["R1"], "BAD": ["R1"] }, "after_talk": ["1杯目のあと", "もう1行"] },
			{ "tags": ["HOT", "POWER"], "reactions": {}, "after_talk": ["退店"] } ] }
	var p9b = _setup(t, 9)
	p9b._on_ingredient_selected("coconut_milk")
	p9b._on_ingredient_selected("tofu")
	p9b._on_complete_input_pressed()
	p9b._on_next_event_pressed()   # 1杯目のREACT
	c.check("複数杯：1杯目の提供後に保存できる", p9b._can_save_recipe_now())
	p9b._on_next_event_pressed()   # 1杯目のあと
	p9b._on_next_event_pressed()   # もう1行（1杯目の最後の会話）
	c.check("複数杯：その杯の最後の会話の行まで保存できる", p9b._can_save_recipe_now())
	p9b._on_next_event_pressed()   # 2杯目のADJUST（new_bowl）
	c.check("次の杯のADJUSTに入ると、保存の対象は消える（椀が新しくなる）", not p9b._can_save_recipe_now() and p9b._recipe_save_stage == "")
	p9b._on_ingredient_selected("nam_prik_pao")
	p9b._on_ingredient_selected("offal")
	p9b._on_complete_input_pressed()
	p9b._on_next_event_pressed()   # 2杯目のREACT（反応なし）
	p9b._on_next_event_pressed()   # 退店（その客の最後の行）
	c.check("複数杯：その客の最後の行まで保存できる", p9b._can_save_recipe_now()
		and p9b.flow.runner.index == p9b.flow.runner.events.size() - 1)
	p9b.free()
	ScheduleData.clear_cache()
	# モブ・断った客
	var p9c = _setup(t, 9)
	p9c._on_customer_decline_pressed()
	p9c._on_next_event_pressed()
	c.check("断った客（判定なし）は保存できない", not p9c._can_save_recipe_now())
	p9c._open = OpenController.new([{ "name": "宵の口", "customers": ["mob#0"] }])
	p9c._open.current_bowl["result"] = "GOOD"
	p9c._open.current_bowl["additions"] = ["tofu", "offal"]
	c.check("モブの団体注文の杯は対象外（分割提供との整合が重い）", not p9c._can_save_recipe_now())
	p9c.free()

	# --- 10. 30%短縮：具材ボタンの押下＋レシピボタン＋[入力完了] を数える ---
	var counts := {}
	for case in [["追加2つ", ["coconut_milk", "tofu"]], ["追加3つ", ["coconut_milk", "tofu", "meat_ball"]]]:
		var ids: Array = case[1]
		var manual_presses := ids.size() + 1   # 具材ボタン×n ＋ [入力完了]
		var recipe_presses := 1 + 1            # レシピボタン ＋ [入力完了]
		var shorter := float(manual_presses - recipe_presses) / float(manual_presses)
		counts[case[0]] = [manual_presses, recipe_presses, shorter]
		c.check("%s：手%d回 → レシピ%d回（%d%%短縮）で30%%以上" % [case[0], manual_presses, recipe_presses, int(round(shorter * 100.0))],
			shorter >= 0.3)
		# 実際にレシピボタン1回＋[入力完了]で、手で押した場合と同じ椀が提供まで進む
		var pr = _setup(t, 3)
		GameState.saved_recipes = [{ "name": "短縮", "ingredients": ids.duplicate() }]
		var presses := 0
		pr._on_recipe_apply_pressed(GameState.saved_recipes[0]["ingredients"])
		presses += 1
		pr._on_complete_input_pressed()
		presses += 1
		pr._on_next_event_pressed()   # REACT（提供の確認。操作回数には数えない：手の側も同じ）
		c.check("%s：レシピ経路は %d 回の操作で提供まで進む" % [case[0], presses],
			presses == recipe_presses and str(pr._open.current_bowl.get("result", "")) != "" and pr._open.current_bowl["additions"] == ids)
		pr.free()
	c.check("最小でも33%短縮（追加2つ：3回→2回）、追加3つは50%（4回→2回）",
		is_equal_approx(float(counts["追加2つ"][2]), 1.0 / 3.0) and is_equal_approx(float(counts["追加3つ"][2]), 0.5))

	# --- 11. スマホのレシピタブ ---
	var p11 = _setup(t, 11, old_visits)
	GameState.saved_recipes = [{ "name": "終電後の椰子豆腐湯", "ingredients": ["coconut_milk", "tofu"] }]
	p11._phone_tab = "recipe"
	var tab: String = p11._format_phone()
	c.check("保存レシピの名前・具材・空き枠が出る", tab.contains("終電後の椰子豆腐湯") and tab.contains(RecipeBook.ingredient_text(["coconut_milk", "tofu"]))
		and tab.contains("枠2：（空き）") and tab.contains("1/3枠"))
	c.check("客ごとの「いつもの」が表示名と具材の並びで出る（評価は出さない）",
		tab.contains("チンピラ：" + RecipeBook.ingredient_text(["coconut_milk", "tofu", "meat_ball"])) and not tab.contains("GOOD") and not tab.contains("まだ記録がありません"), tab)
	p11.free()
	GameState.reset_for_new_game()
	var p11b = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(p11b)
	p11b._phone_tab = "recipe"
	c.check("何も無いとき：空き枠と「まだありません」", p11b._format_phone().contains("枠1：（空き）") and p11b._format_phone().contains("まだありません"))
	p11b.free()

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
