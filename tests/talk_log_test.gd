extends RefCounted
## 会話ログと注文の要約（フェーズ4・手順4-7②。DESIGN.md 10.4）の検証。
## 行は「プレイヤーに見えた」ときに1回ずつ記録される（_load_current_customer の再呼び出し・再描画で
## 二重にならない／最初のイベントの記録漏れが無い）。WAKE でクリア・再挑戦で空から。上限で古い行を捨てる。
## 記録は状態を読むだけ：ゲームの数値・乱数に触れない（reaction_variant は判定時に固定済みの値を読む）。
## 注文の要約は来店記録と場面の注文から組む（保存状態は増えない）。スマホの「ログ」タブ。

const STOCK := ["nam_prik_pao", "offal", "meat_ball", "coconut_milk", "tofu"]


func _setup(t: SceneTree, day: int = 2):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.reputation = 65
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（最初のイベントを記録する）
	return panel


func _start_open(panel) -> void:
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.phase = GameState.Phase.OPEN
	panel.session.open = OpenController.new([{ "name": "宵の口", "customers": ["thug", "granny"] }])
	for id in STOCK:
		GameState.add_inventory(id, 9)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	panel.session.load_current_customer()
	var guard := 0
	while panel.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 100:
		guard += 1
		panel.session.next_event()


func _texts() -> Array:
	var out := []
	for e in TalkLog.entries:
		out.append(str(e["text"]))
	return out


func _count(text: String) -> int:
	return _texts().count(text)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()
	News.clear_cache()

	# --- 1. 最初のイベント（index 0）の記録漏れが無く、再描画で二重にならない ---
	var panel = _setup(t, 2)
	c.check("WAKE の最初のイベント（index 0）が記録されている", _texts()[0] == "……目が覚めた。まだ薄暗い店の奥。", str(_texts()))
	c.check("最初の行の kind は narration・日が入る", TalkLog.entries[0]["kind"] == "narration" and TalkLog.entries[0]["day"] == 2
		and TalkLog.entries[0]["speaker"] == "")
	var size_before := TalkLog.entries.size()
	for i in range(10):
		panel._refresh()
	c.check("再描画を繰り返しても行は増えない", TalkLog.entries.size() == size_before)

	# --- 2. 朝のニュース・DMは news として記録される ---
	panel.session.next_event()       # 「スマホを見る。」（入力待ち）
	panel.session.complete_input()
	guard_loop(panel, 6)
	var kinds := {}
	for e in TalkLog.entries:
		kinds[str(e["text"])] = str(e["kind"])
	c.check("ニュースの見出しは kind:news", kinds.get("ニュース：港湾局とスト側の協議が物別れ。第八码頭の周辺で検問が始まった") == "news", str(kinds))
	c.check("DMも kind:news", kinds.get("DM（市場の顔なじみ）：今日は入荷が遅れてる。早めに来な") == "news")
	panel.free()

	# --- 3. 客の接客：同じ客を何度組み直しても二重にならず、台詞の順に記録される ---
	var p3 = _setup(t, 2)
	TalkLog.clear()
	p3.session.logged_positions = {}
	_start_open(p3)
	var greet_text: String = Day1Events.customer_events("thug")[0]["text"]
	c.check("客の最初の GREET（index 0）が talk・話し手は表示名で1回だけ記録される",
		_count(greet_text) == 1 and TalkLog.entries.filter(func(e): return e["text"] == greet_text)[0]["kind"] == "talk"
			and TalkLog.entries.filter(func(e): return e["text"] == greet_text)[0]["speaker"] == "チンピラ")
	var size3 := TalkLog.entries.size()
	p3.session.load_current_customer()
	p3.session.load_current_customer()
	p3._refresh()
	c.check("同じ客で _load_current_customer を3回呼んでも、行は増えない（二重にならない）", TalkLog.entries.size() == size3 and _count(greet_text) == 1)
	var guard3 := 0
	while p3.session.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard3 < 100:
		guard3 += 1
		p3.session.next_event()   # 組み直した列を ADJUST まで読み直す（もう一度読んでも行は増えない）
	var adjust_text := "（味を調える）"
	c.check("読み直しても、客の GREET と ADJUST の文は1回ずつ", _count(greet_text) == 1 and _count(adjust_text) == 1)

	# --- 4. 提供：SERVE と反応が1回ずつ。反応は判定後の文。抽選は引かない ---
	p3.session.select_ingredient("coconut_milk")
	p3.session.select_ingredient("tofu")
	p3.session.complete_input()
	var serve_entries: Array = TalkLog.entries.filter(func(e): return e["kind"] == "serve")
	c.check("SERVE の文が kind:serve で1回", serve_entries.size() == 1 and serve_entries[0]["text"] == "「はいよ、お待ち。」", str(TalkLog.entries))
	p3.session.next_event()   # REACT
	var reaction: String = p3.session.current_reaction_text()
	var reaction_entries: Array = TalkLog.entries.filter(func(e): return e["kind"] == "reaction")
	c.check("反応が kind:reaction・話し手＝客で、_current_reaction_text() の文のまま1回", reaction != ""
		and reaction_entries.size() == 1 and reaction_entries[0]["text"] == reaction and reaction_entries[0]["speaker"] == "チンピラ")
	seed(4242)
	var before_state := JSON.stringify([GameState.to_dict(), p3.session.open.current_bowl])
	for i in range(20):
		p3._refresh()
		p3.session.record_visible_event()
	var rng_after := randi()
	seed(4242)
	var rng_expected := randi()
	c.check("記録は乱数を引かない（再描画・記録を繰り返しても乱数列が進まない）", rng_after == rng_expected)
	c.check("記録は状態（GameState・椀）を変えない・反応文も変わらない（reaction_variant は固定済み）",
		JSON.stringify([GameState.to_dict(), p3.session.open.current_bowl]) == before_state and p3.session.current_reaction_text() == reaction)
	c.check("反応は何度再描画しても1回のまま", TalkLog.entries.filter(func(e): return e["kind"] == "reaction").size() == 1)
	p3.free()

	# --- 5. 選択（CHOICE）は選んだ選択肢のラベルを kind:choice で記録する ---
	ScheduleData._episode_cache["thug/thug_02"] = { "id": "thug_02", "customer": "thug", "greet": ["来店"], "servings": 1,
		"reactions": { "GOOD": ["R:GOOD"], "OK": ["R"], "GREAT": ["R"], "BAD": ["R"] }, "body": ["本文1"],
		"choices": [ { "id": "message", "options": [ { "id": "yes", "label": "預かる", "set": {} },
			{ "id": "no", "label": "本人に言ってくれ", "set": {} } ] } ], "closing": { "default": ["締め"] } }
	var p5 = _setup(t, 2)
	_start_open(p5)
	p5.session.select_ingredient("coconut_milk")
	p5.session.select_ingredient("tofu")
	p5.session.complete_input()
	p5.session.next_event()   # REACT
	p5.session.next_event()   # 本文1
	p5.session.next_event()   # CHOICE（入力待ち）
	p5.session.choose_story_option("message", "no")
	var choice_entries: Array = TalkLog.entries.filter(func(e): return e["kind"] == "choice")
	c.check("選んだ選択肢のラベルが kind:choice で1回（話し手なし）",
		choice_entries.size() == 1 and choice_entries[0]["text"] == "本人に言ってくれ" and choice_entries[0]["speaker"] == "")
	c.check("本文・締めの行も talk として記録される", _count("本文1") == 1 and _count("締め") == 1)
	p5.free()
	ScheduleData.clear_cache()

	# --- 6. WAKE でクリア・再挑戦で空から ---
	var p6 = _setup(t, 2)
	_start_open(p6)
	c.check("（前提）営業中でログが溜まっている", TalkLog.entries.size() >= 3, str(TalkLog.entries.size()))
	var lines_first_day := TalkLog.entries.size()
	c.check("朝（Day2）へ戻すとログは空から（朝の最初の行だけ）", p6.session.retry_from_morning(2) and TalkLog.entries.size() <= 3
		and _texts()[0] == "……目が覚めた。まだ薄暗い店の奥。" and lines_first_day > TalkLog.entries.size())
	p6.session.flow.force_phase(GameState.Phase.WAKE)
	c.check("WAKE に入るたびに今日の分としてクリアされる", _texts()[0] == "……目が覚めた。まだ薄暗い店の奥。" and TalkLog.entries.size() <= 3)
	p6.free()

	# --- 7. 上限：超えたら古い行から捨てる ---
	TalkLog.clear()
	for i in range(TalkLog.MAX_LINES + 50):
		TalkLog.add(1, "narration", "", "行%d" % i)
	c.check("上限（%d行）を超えない・古い行から捨て・新しい行は残る" % TalkLog.MAX_LINES,
		TalkLog.entries.size() == TalkLog.MAX_LINES and TalkLog.entries[0]["text"] == "行50"
			and TalkLog.entries[TalkLog.MAX_LINES - 1]["text"] == "行%d" % (TalkLog.MAX_LINES + 49))
	TalkLog.add(1, "narration", "", "")
	c.check("空の本文は足さない", TalkLog.entries.size() == TalkLog.MAX_LINES)
	TalkLog.clear()

	# --- 8. 注文の要約：来店記録と場面の注文から全日分を組む（新しい日が上） ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	ScheduleData._episode_cache["thug/thug_02"] = { "id": "thug_02", "customer": "thug", "greet": ["g"], "servings": 1,
		"reactions": {}, "order": { "today_request": { "tags": ["HOT", "POWER"], "label": "辛め" } } }
	GameState.customer_memory = {
		"thug": { "favorite_known": false, "facts": {}, "seen_episodes": [], "visits": [
			{ "day": 1, "slot": "夜半", "served": 1, "grade": "GOOD", "grades": ["GOOD"], "ingredients": [["coconut_milk", "tofu"]], "episode_id": "thug_01" },
			{ "day": 2, "slot": "明け方", "served": 1, "grade": "OK", "grades": ["OK"], "ingredients": [["nam_prik_pao", "offal"]], "episode_id": "thug_02" },
			{ "day": 3, "slot": "夜半", "served": 0, "grade": "", "grades": [], "ingredients": [], "episode_id": "thug_03" } ] },
		"delivery_man": { "favorite_known": true, "facts": {}, "seen_episodes": [], "visits": [
			{ "day": 1, "slot": "宵の口", "served": 3, "grade": "GOOD", "grades": ["GOOD", "OK", ""],
				"ingredients": [["nam_prik_pao", "tofu"], ["nam_prik_pao", "offal"], ["coconut_milk", "tofu"]], "episode_id": "delivery_man_01" } ] },
	}
	var summary := TalkLog.order_summary_lines()
	c.check("来店ごとに1行・全日分（4来店）", summary.size() == 4, str(summary))
	c.check("新しい日が上（Day3 → Day2 → Day1）", str(summary[0]).begins_with("Day3 ") and str(summary[1]).begins_with("Day2 ")
		and str(summary[2]).begins_with("Day1 ") and str(summary[3]).begins_with("Day1 "))
	c.check("同じ日は枠の順の新しい方が上（Day1：夜半のチンピラ → 宵の口の配達員）",
		str(summary[2]).contains("チンピラ") and str(summary[3]).contains("配達員"))
	c.check("今日の頼みのある来店：いつもの／今日（ラベル付き）・出した具材・評価",
		str(summary[1]) == "Day2 明け方　チンピラ：いつもの MELLOW/GENTLE ／ 今日 HOT/POWER（辛め） → 出した：%s → OK" % RecipeBook.ingredient_text(["nam_prik_pao", "offal"]),
		str(summary[1]))
	c.check("今日の頼みの無い来店は「いつもの」だけ", str(summary[2]).contains("いつもの MELLOW/GENTLE → 出した：") and not str(summary[2]).contains("今日 "))
	c.check("今日の来店でまだ出していなければ「まだ出していない」", str(summary[0]).ends_with("→ まだ出していない"), str(summary[0]))
	GameState.day_count = 4
	c.check("過ぎた日で出していなければ「出さなかった」", TalkLog.order_summary_lines()[0].ends_with("→ 出さなかった"))
	c.check("複数杯の来店は杯ごとに「具材（評価）」を並べる（評価なしの杯は「評価なし」）",
		str(summary[3]).contains("%s（GOOD）／%s（OK）／%s（評価なし）" % [RecipeBook.ingredient_text(["nam_prik_pao", "tofu"]),
			RecipeBook.ingredient_text(["nam_prik_pao", "offal"]), RecipeBook.ingredient_text(["coconut_milk", "tofu"])]), str(summary[3]))
	var memory_before := JSON.stringify(GameState.customer_memory)
	TalkLog.order_summary_lines()
	TalkLog.tab_text()
	c.check("要約は来店記録を読むだけ（書き換えない）", JSON.stringify(GameState.customer_memory) == memory_before)
	ScheduleData.clear_cache()

	# --- 9. スマホの「ログ」タブ（4つ目）：注文の要約と今日の会話ログ ---
	var p9 = _setup(t, 2)
	p9._phone_mode = true
	p9._phone_tab = "log"
	p9._refresh()
	var tab: String = p9._format_phone()
	c.check("ログタブに 注文の要約 と 今日の会話ログ の見出しがある", tab.contains("◆注文の要約◆") and tab.contains("◆今日の会話ログ◆"))
	c.check("今日の会話ログに朝の行が出る", tab.contains("……目が覚めた。"))
	var tab_labels := []
	for child in p9._options_row.get_children():
		if not child.is_queued_for_deletion():
			tab_labels.append(child.text)
	c.check("スマホのタブは レシピ／ニュース／SNS／ログ ＋ 閉じる", tab_labels == ["レシピ", "ニュース", "SNS", "ログ", "閉じる"], str(tab_labels))
	p9.free()

	# --- 10. 記録は保存状態を増やさない ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var d := GameState.to_dict()
	c.check("会話ログは保存の項目ではない（朝の保存に入らない）", not d.has("talk_log") and MorningSave.VERSION == 6)

	TalkLog.clear()
	News.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()


## ニュース・DMの行を読み進める（スマホの次の TEXT を n 回）。
func guard_loop(panel, n: int) -> void:
	for i in range(n):
		panel.session.next_event()
