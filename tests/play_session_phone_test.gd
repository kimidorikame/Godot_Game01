extends RefCounted
## PlaySession（UI準備A⑥：スマホ・レシピ・会話ログ・既読スキップ）の検証。
## 対象：開店のレシピ（いつもの・保存レシピのボタンの中身、提供後の保存の段階）、スマホ（レシピ・ニュース・
## ログ）の中身、既読スキップ（PlaySession だけで動く）。画面の表示（文面・ボタン）は既存のスイート
## （recipe_test・read_state_test・talk_log_test・news_*）が確かめる。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 開店のレシピ：いつもの・保存レシピのボタンの中身と、提供後の保存 ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	CustomerMemory.arrive("officer", "宵の口", "officer_01")
	CustomerMemory.record_serve("officer", "宵の口", "officer_01", 1, "GOOD", ["nam_prik_pao", "tofu"])
	GameState.day_count = 2
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	var s: PlaySession = panel.session
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	for id in ["nam_prik_pao", "offal", "coconut_milk", "tofu"]:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer"] }])
	s.load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		s.next_event()
	var buttons: Array = s.recipe_adjust_buttons()
	c.check("椀が空のADJUST：『いつもの』のボタンの中身（直近の料理・足りない品目なし・出せる）が1つ出る",
		buttons.size() == 1 and buttons[0]["kind"] == "usual" and buttons[0]["ingredients"] == ["nam_prik_pao", "tofu"]
			and buttons[0]["missing"].is_empty() and buttons[0]["can_apply"], str(buttons))
	GameState.inventory["tofu"] = 0
	GameState.perishable_batches.erase("tofu")
	var short: Array = s.recipe_adjust_buttons()
	c.check("在庫が足りなければ missing に品目が入り、出せない", short[0]["missing"] == ["tofu"] and not short[0]["can_apply"], str(short))
	GameState.add_inventory("tofu", 9)
	s.apply_recipe(buttons[0]["ingredients"])
	c.check("apply_recipe()：具材ボタンを順に押したのと同じに椀へ入り、椀が空でなくなるのでボタンは消える",
		(s.open.current_bowl["additions"] as Array) == ["nam_prik_pao", "tofu"] and s.recipe_adjust_buttons().is_empty())
	c.check("提供前は保存できない（判定済みの椀が無い）", s.recipe_save_view() == { "can_save": false })
	s.complete_input()
	guard = 0
	while str(s.open.current_bowl.get("result", "")) == "" and guard < 20:
		guard += 1
		s.next_event()
	var view: Dictionary = s.recipe_save_view()
	c.check("提供後：保存できる・段階はボタン待ち・保存する具材・3枠（すべて空き）・名前の候補",
		view["can_save"] and view["stage"] == "" and view["ingredients"] == ["nam_prik_pao", "tofu"]
			and view["slots"].size() == 3 and view["slots"][0]["selectable"] and not view["slots"][1]["selectable"]
			and not view["names"].is_empty(), str(view))
	s.start_recipe_save()
	c.check("start_recipe_save()：枠を選ぶ段階", s.recipe_save_view()["stage"] == "slot")
	s.select_recipe_slot(0)
	c.check("select_recipe_slot(0)：名前を選ぶ段階・選んだ枠が session に入る", s.recipe_save_view()["stage"] == "name" and s.recipe_save_slot == 0)
	var chosen: String = s.recipe_save_view()["names"][0]
	s.select_recipe_name(chosen)
	c.check("select_recipe_name()：枠0に保存され、段階はボタン待ちに戻る",
		GameState.saved_recipes.size() == 1 and str(GameState.saved_recipes[0]["name"]) == chosen
			and s.recipe_save_view()["stage"] == "")
	var phone: Dictionary = s.phone_recipes()
	c.check("スマホのレシピ：保存レシピ（枠ごとの名前・タグ・具材。空き枠は名前が空）と、客ごとの『いつもの』",
		phone["slots"].size() == 3 and phone["slots"][0]["name"] == chosen and phone["slots"][0]["ingredients"] == ["nam_prik_pao", "tofu"]
			and phone["slots"][1]["name"] == "" and phone["usual"].any(func(u): return u["customer"] == "officer"), str(phone))
	s.start_recipe_save()
	s.cancel_recipe_save()
	c.check("cancel_recipe_save()：段階がボタン待ちへ戻る", s.recipe_save_view()["stage"] == "")

	# --- 2. スマホ：ニュース・会話ログ ---
	var news: Array = s.phone_news()
	var days: Array = news.map(func(x): return x["day"])
	var sorted_desc := days.duplicate()
	sorted_desc.sort()
	sorted_desc.reverse()
	c.check("スマホのニュース：今日と過ぎた日だけ（未来の日は出ない）・新しい日が上・各日に項目がある",
		days == sorted_desc and days.all(func(d): return d <= GameState.day_count)
			and news.all(func(x): return x.has("news") and x.has("events") and x.has("is_today")), str(days))
	var entries: Array = s.talk_log_entries()
	c.check("スマホのログ：今日の会話ログが構造（日・種類・話し手・本文）で読める。コピーを返す",
		not entries.is_empty() and entries[0].has("text") and entries[0].has("speaker") and entries.size() == TalkLog.entries.size())
	entries.clear()
	c.check("返ったコピーを変えても記録は変わらない", not TalkLog.entries.is_empty())
	panel.free()

	# --- 3. 既読スキップ：PlaySession だけで動く（画面の描き直しに頼らず、見えた行を session が記録する） ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	TalkLog.clear()
	var s2 := PlaySession.new()
	t.root.add_child(s2)
	s2.start()
	var steps := s2.skip_read()
	c.check("skip_read()：WAKEの語りを進める（フェーズをまたがない・上限以内）。見えた行は session が会話ログへ記録する",
		GameState.phase == GameState.Phase.WAKE and steps >= 0 and steps <= PlaySession.SKIP_READ_LIMIT
			and TalkLog.entries.size() >= 1, "%d歩／ログ%d行" % [steps, TalkLog.entries.size()])
	s2.free()

	GameState.reset_for_new_game()
	return c.finish()
