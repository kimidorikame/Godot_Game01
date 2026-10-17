extends RefCounted
## 提供後の場面データのキー（システム整理C1-①。DESIGN.md 10.5.3・10.8.6）の検証。
## pre_order／body／body_unserved／closing／must_info の読み口（無い・形が不正なら「無い」と同じ）、
## 形の検査 ScheduleData.scene_problems()、pre_order を customer_events に差す位置。
## 既存の21場面はこれらのキーを持たず、customer_events は従来と同一（episode_data_test の記録照合）。


func _scene(extra: Dictionary) -> Dictionary:
	var ep := { "id": "x_01", "customer": "x", "greet": ["g"], "reactions": {}, "servings": 1 }
	ep.merge(extra, true)
	return ep


func _lines(events: Array, type: String) -> Array:
	var out := []
	for ev in events:
		if str(ev.get("type", "")) == type:
			out.append(str(ev.get("text", "")))
	return out


func _choice(id: String) -> Dictionary:
	return { "id": id, "options": [ { "id": "1", "label": "x" }, { "id": "2", "label": "y" } ] }


func _choice_with_set(id: String, key: String) -> Dictionary:
	return { "id": id, "options": [
		{ "id": "1", "label": "x", "set": { key: true } }, { "id": "2", "label": "y", "set": { key: false } } ] }


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()

	# --- 1. 読み口：キーが無い・形が不正なら「無い」と同じ（クラッシュしない） ---
	c.check("実データ：どの読み口も空（21場面は新キーを持たない）",
		ScheduleData.episode_pre_order("thug", "thug_01").is_empty()
			and ScheduleData.episode_body("thug", "thug_01").is_empty()
			and ScheduleData.episode_body_unserved("thug", "thug_01").is_empty()
			and ScheduleData.episode_closing("thug", "thug_01").is_empty()
			and ScheduleData.episode_must_info("thug", "thug_01").is_empty())
	c.check("無い場面・空idも空", ScheduleData.episode_body("thug", "thug_99").is_empty()
		and ScheduleData.episode_closing("", "").is_empty() and ScheduleData.episode_must_info("thug", "").is_empty())
	ScheduleData._episode_cache["x/x_01"] = _scene({
		"pre_order": ["前1", "", 3, "前2"], "body": ["本1", "本2"], "body_unserved": ["未1"],
		"closing": { "default": ["締め"], "bad": "文字列", "message:keep": ["差分", ""], "empty": [] },
		"must_info": ["info_a", 7] })
	c.check("pre_order：文字列の行だけ（空文字・数値は捨てる）", ScheduleData.episode_pre_order("x", "x_01") == ["前1", "前2"])
	c.check("body・body_unservedが読める", ScheduleData.episode_body("x", "x_01") == ["本1", "本2"]
		and ScheduleData.episode_body_unserved("x", "x_01") == ["未1"])
	c.check("closing：行の配列のキーだけ（配列でない・空のキーは捨てる）",
		ScheduleData.episode_closing("x", "x_01") == { "default": ["締め"], "message:keep": ["差分"] },
		str(ScheduleData.episode_closing("x", "x_01")))
	c.check("must_info：文字列だけ", ScheduleData.episode_must_info("x", "x_01") == ["info_a"])
	ScheduleData._episode_cache["x/x_02"] = _scene({ "pre_order": "文字列", "body": 5, "closing": ["配列"], "must_info": {} })
	c.check("形が不正なキーは「無い」と同じ", ScheduleData.episode_pre_order("x", "x_02").is_empty()
		and ScheduleData.episode_body("x", "x_02").is_empty() and ScheduleData.episode_closing("x", "x_02").is_empty()
		and ScheduleData.episode_must_info("x", "x_02").is_empty())
	ScheduleData.clear_cache()

	# --- 2. 形の検査（scene_problems） ---
	var good := _scene({
		"reactions": { "GREAT": ["a"], "GOOD": ["a"], "OK": ["a"], "BAD": ["a"], "UNSERVED": ["u"] },
		"pre_order": ["p"], "body": ["b"], "body_unserved": ["bu"], "must_info": ["m"],
		"choices": [ { "id": "message", "options": [
			{ "id": "keep", "label": "預かる", "set": { "holding_message": true } },
			{ "id": "ask", "label": "本人に", "set": { "holding_message": false } } ] } ],
		"closing": { "default": ["d"], "message:keep": ["k"], "request_honored:true": ["h"] },
		"sets_facts": { "takeout_recipient_known": true } })
	c.check("正しい場面データは問題なし", ScheduleData.scene_problems(good).is_empty(), str(ScheduleData.scene_problems(good)))
	c.check("新キーの無い場面も問題なし", ScheduleData.scene_problems(_scene({})).is_empty())
	var bad_cases := {
		"reactionsの未知キー": { "reactions": { "FINE": ["a"] } },
		"reactionsの値が配列でない": { "reactions": { "GREAT": "a" } },
		"bodyが文字列": { "body": "本文" },
		"bodyに空文字": { "body": ["a", ""] },
		"pre_orderが数値の配列": { "pre_order": [1] },
		"choicesが3つ": { "choices": [ _choice("a"), _choice("b"), _choice("c") ] },
		"choicesのidが重複": { "choices": [ _choice("a"), _choice("a") ] },
		"選択肢が3つ": { "choices": [ { "id": "a", "options": [
			{ "id": "1", "label": "x" }, { "id": "2", "label": "y" }, { "id": "3", "label": "z" } ] } ] },
		"選択肢のidが重複": { "choices": [ { "id": "a", "options": [
			{ "id": "1", "label": "x" }, { "id": "1", "label": "y" } ] } ] },
		"選択肢にlabelが無い": { "choices": [ { "id": "a", "options": [
			{ "id": "1" }, { "id": "2", "label": "y" } ] } ] },
		"setが辞書でない": { "choices": [ { "id": "a", "options": [
			{ "id": "1", "label": "x", "set": [1] }, { "id": "2", "label": "y" } ] } ] },
		"sets_factsが3個": { "sets_facts": { "a": true, "b": true, "c": true } },
		"setとsets_factsの合計が3個": { "choices": [ _choice_with_set("m", "k1"), _choice_with_set("n", "k2") ],
			"sets_facts": { "k3": true } },
		"同じ事実を両方に書く": { "choices": [ _choice_with_set("m", "k1") ], "sets_facts": { "k1": true } },
		"closingにdefaultが無い": { "closing": { "x": ["a"] } },
		"closingのキーが対応しない": { "closing": { "default": ["a"], "message:keep": ["b"] } },
		"closingの値が配列でない": { "closing": { "default": "a" } },
		"must_infoとbodyがあるのにbody_unservedが無い": { "must_info": ["m"], "body": ["b"] },
	}
	for label in bad_cases:
		c.check("検査が弾く：" + label, not ScheduleData.scene_problems(_scene(bad_cases[label])).is_empty())
	c.check("must_infoがあってもbodyが無ければbody_unservedは要らない",
		ScheduleData.scene_problems(_scene({ "must_info": ["m"] })).is_empty())
	c.check("同じ事実のキーを2つの選択で使っても、重複を除いて1個として数える",
		ScheduleData.scene_problems(_scene({ "choices": [ _choice_with_set("m", "k1"), _choice_with_set("n", "k1") ] })).is_empty(),
		str(ScheduleData.scene_problems(_scene({ "choices": [ _choice_with_set("m", "k1"), _choice_with_set("n", "k1") ] }))))

	# --- 3. pre_order：前回の2行(callback)と注文(greet)の間に、GREETとして差す ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	ScheduleData._episode_cache["officer/officer_01"] = _scene({ "id": "officer_01", "customer": "officer",
		"greet": ["注文1"] })
	var plain := Day1Events.customer_events("officer")
	ScheduleData._episode_cache["officer/officer_01"] = _scene({ "id": "officer_01", "customer": "officer",
		"greet": ["注文1", "注文2"], "pre_order": ["前置き1", "前置き2"],
		"callback": { "first": ["初来店1", "初来店2"] } })
	var events := Day1Events.customer_events("officer")
	var greets := _lines(events, "GREET")
	c.check("callback → pre_order → greet の順に並ぶ（その後に新人警官の共通会話が続く）",
		greets.slice(0, 6) == ["初来店1", "初来店2", "前置き1", "前置き2", "注文1", "注文2"], str(greets))
	var types := []
	for ev in events:
		types.append(str(ev["type"]))
	c.check("列の形は GREET×6 → ADJUST → SERVE → REACT",
		types.slice(0, 9) == ["GREET", "GREET", "GREET", "GREET", "GREET", "GREET", "ADJUST", "SERVE", "REACT"], str(types))
	c.check("pre_orderが無い場面は従来の列（GREET → ADJUST → SERVE → REACT）",
		str(plain[0]["type"]) == "GREET" and str(plain[1]["type"]) == "ADJUST"
			and str(plain[2]["type"]) == "SERVE" and str(plain[3]["type"]) == "REACT", str(plain))
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
