extends RefCounted
## UI準備Y：名乗ったあとの名前。場面の行の配列で、名乗った行のすぐあとに { "reveal_name": "<名前>" } を置くと、その行が出た時点から
## その客の表示名（CustomerMemory.display_name）が変わる。名乗ったことは来店記録の facts.revealed_name に残る（朝のセーブに入る）。
##   1. データの形：officer_01 の「リンです。皆、そう呼びます」のあと。印は直前の行の Event に reveal_name として付く。検査が弾くもの
##   2. 名乗る前は「新人警官」、名乗ったあとは客ノート・連絡先のカード・DMの相手の名前・結果画面・会話ログの要約・話し手が「リン」
##   3. 朝のセーブ：名乗ったあとの朝の封筒から戻しても「リン」。名乗る前の朝の封筒から戻せば「新人警官」（セーブの版は変えない）
##   4. ニカ（streamer）にも同じ形が使える（場面データを差し込んで確かめる）


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()

	# --- 1. データの形 ---
	var officer := ScheduleData.episode_data("officer", "officer_01")
	var body: Array = officer["body"]
	var at := body.find("警官「リンです。皆、そう呼びます」")
	c.check("officer_01：「リンです。皆、そう呼びます」のすぐあとに { reveal_name: リン }・場面の検査に問題なし",
		at >= 0 and body[at + 1] is Dictionary and body[at + 1] == { "reveal_name": "リン" } and ScheduleData.scene_problems(officer).is_empty(),
		str(ScheduleData.scene_problems(officer)))
	c.check("会話枠に出す行（spoken_lines）には印が入らない・行の数は今までどおり44",
		ScheduleData.spoken_lines(body).size() == 44 and not ScheduleData.spoken_lines(body).has({ "reveal_name": "リン" }))
	GameState.day_count = 2
	var after := Day1Events.after_serve_events("officer", "officer_01", { "served": true, "grade": "GOOD" })
	var marked := after.filter(func(e): return e.has("reveal_name"))
	c.check("提供後の列：印は「リンです」の行の Event に reveal_name として付く（印だけの Event は作らない）",
		marked.size() == 1 and str(marked[0]["text"]) == "警官「リンです。皆、そう呼びます」" and str(marked[0]["reveal_name"]) == "リン"
			and str(marked[0]["type"]) == "GREET" and after.size() == 44)
	c.check("読み口：先頭の印は捨てる・〔演出〕は落とす・印は直前の行に付く",
		ScheduleData.spoken_lines_with_reveal([{ "reveal_name": "X" }, "a", "〔演出〕b", { "reveal_name": "Y" }]) == [{ "text": "a", "reveal_name": "Y" }])
	var bad_first := { "id": "x", "customer": "officer", "greet": [{ "reveal_name": "リン" }, "a"], "reactions": {}, "servings": 1 }
	var bad_keys := { "id": "x", "customer": "officer", "greet": ["a", { "reveal_name": "リン", "x": 1 }], "reactions": {}, "servings": 1 }
	var bad_empty := { "id": "x", "customer": "officer", "body": ["a", { "reveal_name": "" }], "reactions": {}, "servings": 1 }
	var bad_mob := { "id": "x", "customer": "no_such_customer", "greet": ["a", { "reveal_name": "リン" }], "reactions": {}, "servings": 1 }
	c.check("検査：印が先頭・余分なキー・空の名前・名前あり客でない場面は弾く",
		not ScheduleData.scene_problems(bad_first).is_empty() and not ScheduleData.scene_problems(bad_keys).is_empty()
			and not ScheduleData.scene_problems(bad_empty).is_empty() and not ScheduleData.scene_problems(bad_mob).is_empty())

	# --- 2. 名乗る前と後 ---
	GameState.reset_for_new_game()
	GameState.day_count = 4
	# 4日目の宵の口に新人警官が来る計画（来店予告の DM が新人警官から届く＝DMの相手の名前を見る）
	GameState.today_plan = { "day": 4, "demand_center": 9, "mob_instances": {},
		"slots": [{ "name": "宵の口", "customers": ["officer"], "regular_id": "officer", "episode_id": "officer_02", "today_request": {} }] }
	var s := PlaySession.new()
	t.root.add_child(s)
	GameState.memory_entry("officer")["visits"] = [{ "day": 2, "slot": "宵の口", "served": 1, "grade": "GOOD", "grades": ["GOOD"],
		"ingredients": [], "episode_id": "officer_01" }]
	c.check("名乗る前：表示名は「新人警官」（プロフィールの name）", CustomerMemory.display_name("officer") == "新人警官"
		and str(s.contact_card("customer:officer")["name"]) == "新人警官")
	s._apply_event(marked[0])
	var note_names: Array = (s.phone_notes()["regulars"] as Array).map(func(r): return str(r["name"]))
	var threads := s.dm_threads().filter(func(th): return str(th["key"]) == "customer:officer")
	var summary := Result.summarize([], [], 0)
	summary["regular_visit_days"] = { "officer": 1 }
	var story := Result.format_story(summary, ["officer"], s.display_names())
	c.check("名乗った行が出たら：表示名・客ノート・連絡先のカード・DMの相手の名前（4日目の朝の新人警官の来店予告）・結果画面が「リン」",
		CustomerMemory.display_name("officer") == "リン" and note_names.has("リン") and not note_names.has("新人警官")
			and str(s.contact_card("customer:officer")["name"]) == "リン" and threads.size() == 1 and str(threads[0]["name"]) == "リン"
			and story.contains("リン") and not story.contains("新人警官"), "%s / %s / %s" % [str(note_names), str(threads), story])
	c.check("会話ログの話し手（名前の付かない行）と注文の要約も「リン」", s.log_speaker("officer") == "リン"
		and TalkLog._summary_line("officer", GameState.memory_entry("officer")["visits"][0]).contains("リン"))
	c.check("来店記録の facts.revealed_name に残る（プロフィールの name は変えない）",
		str(CustomerMemory.fact("officer", "revealed_name", "")) == "リン" and ScheduleData.customer_display_name("officer") == "新人警官")
	c.check("ほかの客は変わらない（中身Z：配信者は名乗る前の名前「初めての客」）", CustomerMemory.display_name("thug") == "レックス" and CustomerMemory.display_name("streamer") == "初めての客")

	# --- 3. 朝のセーブ ---
	var after_envelope: Dictionary = MorningSave.capture("")
	GameState.reset_for_new_game()
	c.check("（前提）新しいゲームでは「新人警官」", CustomerMemory.display_name("officer") == "新人警官")
	var before_envelope: Dictionary = MorningSave.capture("")
	MorningSave.apply(after_envelope)
	c.check("名乗ったあとの朝の封筒（版は今のまま）から戻しても「リン」", MorningSave.is_valid(after_envelope)
		and int(after_envelope["version"]) == MorningSave.VERSION and CustomerMemory.display_name("officer") == "リン")
	MorningSave.apply(before_envelope)
	c.check("名乗る前の朝の封筒から戻せば「新人警官」（再挑戦で名乗る前に戻る）", CustomerMemory.display_name("officer") == "新人警官")

	# --- 4. ニカにも同じ形が使える ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	ScheduleData._episode_cache["streamer/streamer_01"] = { "id": "streamer_01", "customer": "streamer", "servings": 1,
		"greet": ["配信者「こんばんは」"], "reactions": { "GOOD": ["配信者「おいしい」"] },
		"body": ["店主「名前は」", "配信者「ニカです」", { "reveal_name": "ニカ" }, "ニカ「また来ます」"] }
	c.check("ニカの場面にも印が置ける（検査に問題なし）", ScheduleData.scene_problems(ScheduleData.episode_data("streamer", "streamer_01")).is_empty())
	var nika := Day1Events.after_serve_events("streamer", "streamer_01", { "served": true, "grade": "GOOD" })
	for ev in nika:
		s._apply_event(ev)
	c.check("ニカが名乗ったら表示名が「ニカ」", nika.filter(func(e): return e.has("reveal_name")).size() == 1 and CustomerMemory.display_name("streamer") == "ニカ")
	s.free()

	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
