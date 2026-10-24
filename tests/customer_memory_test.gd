extends RefCounted
## 来店記録（F5・DESIGN.md 10.8.5。フェーズ4-4b-1コミット①）の検証。
## 対象：GameState.customer_memory、CustomerMemory（記録の書き手）、DebugPanelの記録の呼び出し
## （来店・提供・断り）、好物を知った順（known_favorite_ids）、保存の往復と再挑戦、新しい周と
## 日次リセット、封筒の版4。記録するだけで、台詞・判定・好物の開示の時刻は変えていない。

func _setup(t: SceneTree, customers: Array, inventory: Dictionary):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": customers }])
	for id in inventory:
		GameState.add_inventory(id, int(inventory[id]))
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel.session.load_current_customer()
	return panel


func _drive_to_adjust(panel) -> void:
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel.session.next_event()


func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var saved_path = load("res://scripts/morning_save.gd").get("save_path")
	load("res://scripts/morning_save.gd").set("save_path", "user://customer_memory_test.dat")

	# --- 1. 記録の基本（CustomerMemoryを直接）：来店・同日の冪等・見た場面の重複なし ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	CustomerMemory.arrive("thug", "宵の口", "thug_03")
	var visits := CustomerMemory.visits_of("thug")
	c.check("来店で記録が1件できる（served=0・grade空）",
		visits.size() == 1 and int(visits[0]["served"]) == 0 and str(visits[0]["grade"]) == "")
	c.check("来店の記録にday・slot・episode_idが入る",
		int(visits[0]["day"]) == 3 and str(visits[0]["slot"]) == "宵の口"
			and str(visits[0]["episode_id"]) == "thug_03")
	c.check("見た場面（seen_episodes）に入る",
		GameState.customer_memory["thug"]["seen_episodes"] == ["thug_03"])
	CustomerMemory.arrive("thug", "宵の口", "thug_03")
	c.check("同じ日に何度arriveしても来店は増えない（冪等）", CustomerMemory.visits_of("thug").size() == 1)
	GameState.day_count = 4
	CustomerMemory.arrive("thug", "夜半", "thug_03")
	c.check("次の日の来店は新しい1件になる", CustomerMemory.visits_of("thug").size() == 2
		and str(CustomerMemory.last_visit("thug")["slot"]) == "夜半")
	c.check("同じ場面idはseen_episodesに重複しない", GameState.customer_memory["thug"]["seen_episodes"] == ["thug_03"])
	CustomerMemory.arrive("thug", "宵の口", "thug_04")
	c.check("別の場面idはseen_episodesに足される（同日再arriveでも場面だけ足される）",
		GameState.customer_memory["thug"]["seen_episodes"] == ["thug_03", "thug_04"])

	# --- 2. 提供の記録：served・grades・ingredients・grade（評価した杯の最悪値） ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	CustomerMemory.arrive("delivery_man", "宵の口", "delivery_man_01")
	CustomerMemory.record_serve("delivery_man", "宵の口", "delivery_man_01", 1, "GOOD", ["nam_prik_pao", "tofu"])
	var v1 := CustomerMemory.last_visit("delivery_man")
	c.check("1杯目：served=1・grade=GOOD・grades・ingredients",
		int(v1["served"]) == 1 and str(v1["grade"]) == "GOOD" and v1["grades"] == ["GOOD"]
			and v1["ingredients"] == [["nam_prik_pao", "tofu"]])
	CustomerMemory.record_serve("delivery_man", "宵の口", "delivery_man_01", 1, "BAD", ["offal"])
	c.check("2杯目がBADなら代表のgradeはBAD（最悪値）",
		str(CustomerMemory.last_visit("delivery_man")["grade"]) == "BAD")
	CustomerMemory.record_serve("delivery_man", "宵の口", "delivery_man_01", 1, "", ["tofu"])
	var v3 := CustomerMemory.last_visit("delivery_man")
	c.check("評価なしの杯（持ち帰り）もservedに数える（3杯）", int(v3["served"]) == 3)
	c.check("評価なしの杯はgrade（最悪値）に含めない（BADのまま）", str(v3["grade"]) == "BAD")
	c.check("gradesには評価なしを空文字で残す・ingredientsは杯ごとの配列",
		v3["grades"] == ["GOOD", "BAD", ""] and v3["ingredients"] == [["nam_prik_pao", "tofu"], ["offal"], ["tofu"]])
	c.check("来店は1件のまま（杯ごとに追記）", CustomerMemory.visits_of("delivery_man").size() == 1)
	c.check("worst_grade：GREAT/GOODならGOOD・評価なしだけなら空・空配列は空",
		CustomerMemory.worst_grade(["GREAT", "GOOD"]) == "GOOD" and CustomerMemory.worst_grade(["", ""]) == ""
			and CustomerMemory.worst_grade([]) == "" and CustomerMemory.worst_grade(["GREAT", "OK", "GOOD"]) == "OK")
	GameState.reset_for_new_game()
	GameState.day_count = 1
	CustomerMemory.record_serve("thug", "宵の口", "thug_01", 1, "", ["tofu"])
	c.check("評価なしの杯だけの来店は、servedが増えgradeは空",
		int(CustomerMemory.last_visit("thug")["served"]) == 1 and str(CustomerMemory.last_visit("thug")["grade"]) == "")

	# --- 3. モブ・未知のidは記録しない ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.today_plan["mob_instances"]["mob#0"] = { "type": "dock_workers", "count": 3 }
	CustomerMemory.arrive("mob#0", "夜半", "")
	CustomerMemory.record_serve("mob#0", "夜半", "", 3, "GOOD", ["tofu"])
	CustomerMemory.arrive("no_such_customer", "夜半", "")
	c.check("モブ・プロフィールの無い客は記録されない", GameState.customer_memory.is_empty())

	# --- 4. facts（足す手段だけ。今は使わない） ---
	GameState.reset_for_new_game()
	CustomerMemory.set_fact("granny", "promise", true)
	c.check("factsを足して読める・無い事実は既定値",
		CustomerMemory.fact("granny", "promise") == true and CustomerMemory.fact("granny", "x", 5) == 5
			and CustomerMemory.fact("nobody", "x", 7) == 7)

	# --- 5. 好物を知った順：known_favorite_idsは「知った順」（来店の順ではない） ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	CustomerMemory.arrive("granny", "明け方", "granny_01")   # 先に来店（記録は老婆が先）
	GameState.mark_favorite_known("thug")                    # 先に知ったのはチンピラ
	GameState.mark_favorite_known("granny")
	c.check("知った順（thug→granny）。来店の順（granny→thug）ではない",
		GameState.known_favorite_ids() == ["thug", "granny"], str(GameState.known_favorite_ids()))
	c.check("knows_favoriteがfavorite_knownを読む",
		GameState.memory_entry("granny")["favorite_known"] == true and GameState.knows_favorite("granny")
			and GameState.knows_favorite("thug") and not GameState.knows_favorite("officer"))
	GameState.mark_favorite_known("thug")
	c.check("二度知らせても並び・来店記録は変わらない", GameState.known_favorite_ids() == ["thug", "granny"]
		and CustomerMemory.visits_of("granny").size() == 1)

	# --- 6. DebugPanel経由：単発の客（チンピラ）。来店で記録・提供で更新・好物の開示は従来どおり ---
	var panel = _setup(t, ["thug"], { "coconut_milk": 5, "tofu": 5 })
	var tv := CustomerMemory.last_visit("thug")
	c.check("来店した時点で記録がある（served=0・場面thug_01・枠は宵の口）",
		int(tv.get("served", -1)) == 0 and str(tv.get("episode_id", "")) == "thug_01"
			and str(tv.get("slot", "")) == "宵の口" and int(tv.get("day", 0)) == 1, str(tv))
	panel.session.load_current_customer()
	c.check("同じ客をもう一度ロードしても来店は増えない", CustomerMemory.visits_of("thug").size() == 1)
	_drive_to_adjust(panel)
	c.check("提供前は好物を知らない", not GameState.knows_favorite("thug"))
	panel.session.select_ingredient("coconut_milk")
	panel.session.select_ingredient("tofu")
	panel.session.complete_input()
	panel.session.next_event()   # SERVE→REACT（提供が適用される）
	tv = CustomerMemory.last_visit("thug")
	c.check("提供で記録が更新される（served=1・入れた具材）",
		int(tv["served"]) == 1 and tv["ingredients"] == [["coconut_milk", "tofu"]], str(tv))
	c.check("記録のgradeは判定結果と同じ",
		str(tv["grade"]) == str(panel.session.open.current_bowl.get("result", "?")) and tv["grades"] == [tv["grade"]])
	c.check("好物は提供の瞬間に知った扱いになる（従来どおり）。favorite_knownも一致",
		GameState.knows_favorite("thug") and GameState.memory_entry("thug")["favorite_known"] == true)

	# --- 7. 断り：来店の記録は残り、servedは0のまま ---
	var panel2 = _setup(t, ["granny"], { "herbal_sauce": 5, "offal": 5 })
	_drive_to_adjust(panel2)
	panel2.session.decline_customer()
	panel2.session.next_event()
	var gv := CustomerMemory.last_visit("granny")
	c.check("[客を断る]：来店の記録は残り、served=0・gradeは空",
		CustomerMemory.visits_of("granny").size() == 1 and int(gv["served"]) == 0 and str(gv["grade"]) == "")
	c.check("断った客の好物は知った扱いにならない（従来どおり）",
		not GameState.knows_favorite("granny") and GameState.memory_entry("granny")["favorite_known"] == false)

	# --- 8. 早仕舞い：来店済みの客の記録は残り、まだ来ていない客は記録されない ---
	var panel3 = _setup(t, ["thug", "granny"], { "coconut_milk": 5, "tofu": 5 })
	panel3.session.flow.force_phase(GameState.Phase.CLOSE)   # 1人目の途中で閉店（鍋切れ・早仕舞いと同じ経路）
	c.check("途中で閉店：来店済みの客（チンピラ）の記録は残る（served=0）",
		CustomerMemory.visits_of("thug").size() == 1 and int(CustomerMemory.last_visit("thug")["served"]) == 0)
	c.check("まだ来ていない客（老婆）は記録されない", not GameState.customer_memory.has("granny"))

	# --- 9. 配達員（3杯）：1件の来店に3杯分。好物の開示は退店時（1・2杯目の途中ではfalse） ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel4 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel4)
	GameState.phase = GameState.Phase.OPEN
	panel4.session.open = OpenController.new([{ "name": "宵の口", "customers": ["delivery_man"] }])
	GameState.add_inventory("nam_prik_pao", 10)
	GameState.add_inventory("offal", 5)
	GameState.add_inventory("tofu", 5)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel4.session.load_current_customer()
	var picks := [["nam_prik_pao", "offal", "tofu"], ["nam_prik_pao", "tofu"], ["nam_prik_pao", "tofu"]]
	var ai := 0
	var guard := 0
	var known_during := false
	while str(panel4.session.open.current_customer()) == "delivery_man" and guard < 400:
		guard += 1
		if panel4.session.flow.runner.status == EventRunner.Status.WAITING_INPUT:
			for id in picks[ai]:
				panel4.session.select_ingredient(id)
			ai += 1
			panel4.session.complete_input()
		else:
			panel4.session.next_event()
			if GameState.memory_entry("delivery_man")["favorite_known"] == true and ai < 3:
				known_during = true
	var dv := CustomerMemory.last_visit("delivery_man")
	c.check("配達員の来店は1件（3杯分が追記される）", CustomerMemory.visits_of("delivery_man").size() == 1
		and int(dv["served"]) == 3 and (dv["grades"] as Array).size() == 3 and (dv["ingredients"] as Array).size() == 3)
	c.check("杯ごとの具材が入れた順に記録される", dv["ingredients"] == picks, str(dv["ingredients"]))
	c.check("代表のgradeは評価した杯の最悪値", str(dv["grade"]) == CustomerMemory.worst_grade(dv["grades"]))
	c.check("見た場面はdelivery_man_01（3杯列）", str(dv["episode_id"]) == "delivery_man_01"
		and GameState.customer_memory["delivery_man"]["seen_episodes"] == ["delivery_man_01"])
	c.check("好物は1・2杯目の途中では知った扱いにならず（favorite_known=false）、退店時にtrue",
		not known_during and GameState.memory_entry("delivery_man")["favorite_known"] == true
			and GameState.knows_favorite("delivery_man"))

	# --- 10. 評価なしの杯（judge:false）：servedに数え、grade（最悪値）には含めない ---
	var panel5 = _setup(t, ["thug"], { "tofu": 5 })
	panel5.session._serve_customer({ "customer": "thug", "sale": 45, "servings": 1, "judge": false,
		"wanted_tags": [], "favorite": "", "aggregate": true })
	var uv := CustomerMemory.last_visit("thug")
	c.check("judge:falseの杯：served=1・grade空・gradesに空文字",
		int(uv["served"]) == 1 and str(uv["grade"]) == "" and uv["grades"] == [""], str(uv))

	# --- 11. 保存の往復：to_dict→from_dict（好物を知った順も保たれる）・深いコピー ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	CustomerMemory.arrive("granny", "宵の口", "granny_01")
	CustomerMemory.record_serve("granny", "宵の口", "granny_01", 1, "GREAT", ["herbal_sauce", "offal"])
	GameState.mark_favorite_known("thug")
	GameState.mark_favorite_known("granny")
	var summary_before := Result.summarize([], [], 0)
	var story_before := Result.format_story(summary_before, GameState.known_favorite_ids())
	c.check("format_storyは好物を知った客を知った順に、表示名で並べる",
		story_before.contains("好物を知った客: チンピラ、老婆"), story_before)
	var d := GameState.to_dict()
	GameState.reset_for_new_game()
	GameState.from_dict(d)
	c.check("to_dict→from_dictでcustomer_memoryが一致する",
		_norm(GameState.customer_memory) == _norm(d["customer_memory"]))
	c.check("往復後も好物を知った順（thug→granny）が保たれ、format_storyも同じ",
		GameState.known_favorite_ids() == ["thug", "granny"]
			and Result.format_story(summary_before, GameState.known_favorite_ids()) == story_before)
	d["customer_memory"]["granny"]["visits"][0]["served"] = 99
	c.check("from_dict後に元の辞書を書き換えても影響しない（深いコピー）",
		int(CustomerMemory.last_visit("granny")["served"]) == 1)
	var d2 := GameState.to_dict()
	GameState.customer_memory["granny"]["visits"][0]["served"] = 55
	c.check("to_dict後に状態を書き換えても辞書に入らない",
		int(d2["customer_memory"]["granny"]["visits"][0]["served"]) == 1)

	# --- 12. 封筒：版4・来店記録の型検査・ファイルの往復（型と並びが保たれる） ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	CustomerMemory.arrive("granny", "宵の口", "granny_01")
	CustomerMemory.record_serve("granny", "宵の口", "granny_01", 1, "GOOD", ["offal"])
	GameState.mark_favorite_known("thug")
	GameState.mark_favorite_known("granny")
	var today_plan_stub := { "day": 2, "demand_center": 11, "mob_instances": {}, "slots": [] }
	GameState.today_plan = today_plan_stub
	var env := MorningSave.capture("")
	c.check("封筒の版は5以上（4-4b-1で4。4-4b-2で5）", int(env["version"]) == MorningSave.VERSION and MorningSave.VERSION >= 4)
	c.check("来店記録を持つ封筒は有効", MorningSave.is_valid(env))
	var old := env.duplicate(true)
	old["version"] = 3
	c.check("版3の保存は読めない扱い（新規ゲーム）", not MorningSave.is_valid(old))
	c.check("今の封筒の版はVERSION（古い版は読めない）", MorningSave.is_valid(env) and int(env["version"]) == MorningSave.VERSION)
	# 4-4b-1①の時点の封筒（旧known_favoritesの余分なキーが付いた版4）も、版は同じなので読める
	# （余分なキーはfrom_dictが無視する。版を2回上げない）。
	var legacy := env.duplicate(true)
	legacy["state"]["known_favorites"] = { "granny": true }
	c.check("旧known_favoritesの余分なキーが付いた版4の封筒も有効", MorningSave.is_valid(legacy))
	GameState.reset_for_new_game()
	MorningSave.apply(legacy)
	c.check("余分なキーは無視され、来店記録から好物を知った客が戻る", GameState.knows_favorite("granny")
		and GameState.known_favorite_ids() == ["thug", "granny"] and not GameState.get("known_favorites") is Dictionary)

	var no_mem := env.duplicate(true)
	no_mem["state"].erase("customer_memory")
	c.check("customer_memoryの欠けは無効", not MorningSave.is_valid(no_mem))
	var bad := env.duplicate(true)
	bad["state"]["customer_memory"]["granny"]["favorite_known"] = 1
	c.check("favorite_knownがboolでなければ無効", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["customer_memory"]["granny"]["visits"][0]["day"] = 2.0
	c.check("来店のdayが整数でなければ無効（JSONで小数になる型崩れ）", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["customer_memory"]["granny"]["visits"] = {}
	c.check("visitsが配列でなければ無効", not MorningSave.is_valid(bad))
	bad = env.duplicate(true)
	bad["state"]["customer_memory"]["granny"]["seen_episodes"] = [1]
	c.check("seen_episodesが文字列の配列でなければ無効", not MorningSave.is_valid(bad))
	MorningSave.delete_file()
	c.check("ファイルへ書ける", MorningSave.write_file(env))
	var back := MorningSave.read_file()
	c.check("ファイルを通した往復で来店記録が一致する（型も保たれる）",
		not back.is_empty() and back["state"]["customer_memory"] == env["state"]["customer_memory"]
			and typeof(back["state"]["customer_memory"]["granny"]["visits"][0]["day"]) == TYPE_INT)
	GameState.reset_for_new_game()
	MorningSave.apply(back)
	c.check("ファイルから戻しても好物を知った順（thug→granny）が保たれる",
		GameState.known_favorite_ids() == ["thug", "granny"]
			and Result.format_story(summary_before, GameState.known_favorite_ids()) == story_before)
	MorningSave.delete_file()

	# --- 13. 再挑戦：戻した朝より後の来店・好物の開示を持ち越さない。知った順も保たれる ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.mark_favorite_known("thug")
	var panel6 = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel6)   # Day2の朝を記録（チンピラは既に好物を知っている）
	var morning_story := Result.format_story(summary_before, GameState.known_favorite_ids())
	CustomerMemory.arrive("granny", "宵の口", "granny_02")
	CustomerMemory.record_serve("granny", "宵の口", "granny_02", 1, "GREAT", ["offal"])
	GameState.mark_favorite_known("granny")
	c.check("（前提）朝より後に老婆の来店・好物の開示が入った",
		GameState.known_favorite_ids() == ["thug", "granny"] and CustomerMemory.visits_of("granny").size() == 1)
	GameState.money = 0
	panel6.session.game_over("テスト用ゲームオーバー")
	c.check("再挑戦できる", panel6.session.retry_from_morning())
	c.check("戻した朝より後の来店記録を持ち越さない（老婆の来店・記録が無い）",
		not GameState.customer_memory.has("granny") or CustomerMemory.visits_of("granny").is_empty())
	c.check("戻した朝より後の好物の開示を持ち越さない（知ったのはチンピラだけ）",
		GameState.known_favorite_ids() == ["thug"] and not GameState.knows_favorite("granny"))
	c.check("戻した朝のformat_storyは朝の時点と同じ",
		Result.format_story(summary_before, GameState.known_favorite_ids()) == morning_story)

	# --- 14. 新しい周では消え、日次リセットでは消えない ---
	GameState.reset_for_new_game()
	CustomerMemory.arrive("thug", "宵の口", "thug_01")
	GameState.mark_favorite_known("thug")
	GameState.reset_for_new_day()
	c.check("日次リセットでは来店記録も好物も消えない（7日間を通して残る）",
		CustomerMemory.visits_of("thug").size() == 1 and GameState.knows_favorite("thug"))
	GameState.reset_for_new_game()
	c.check("新しい周（reset_for_new_game）で来店記録が空になる",
		GameState.customer_memory.is_empty() and GameState.known_favorite_ids().is_empty())

	load("res://scripts/morning_save.gd").set("save_path", saved_path)
	GameState.reset_for_new_game()
	for p in [panel, panel2, panel3, panel4, panel5, panel6]:
		if is_instance_valid(p):
			p.free()
	return c.finish()
