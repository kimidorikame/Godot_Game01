extends RefCounted
## 中身Z：3日目の本番の文（planning/scenario/day3/ の8本）をゲームのデータに入れたことの検証。
##   1. データ：3日目の場面（delivery_man_02・streamer_01・hooker_02）・モブ3組（days."3"）・市場の場面（day3_market）に印の問題が無い・
##      元の文の行が抜けなく入っている・OK の文は外れた札で2通り（OK_MISSING）
##   2. 条件付きの行（{ "if": { fact | not_fact }, "lines" }）：1日目の阿強の3杯目（持ち帰り）を出したか（facts.day1_takeout_served）で
##      阿強の来店・容器の節・最初の行・退店の行が替わる。形の検査。朝のDMも同じ条件で出し分ける
##   3. 名乗る前の名前：配信者は名乗るまで「初めての客」（name_before_reveal）。「ニカ。配信では、その名前」の行から「ニカ」
##   4. 予備の一言（spare_greet）：同じ晩に同じ職種の2組目は、1組目の会話の代わりに予備の一言と注文の行（反応・会計は同じ）
##   5. 市場：張姐（仕込む量の前と、選んだあとの2行）→ 市場 → 市場を出る → 梁伯。払い方は今までどおり（市場を出るときにまとめて払う）
##   6. 3日目を朝から閉店まで本番の画面で通す（1日目の3杯目を出した道・断った道の両方）：元の文の行が順に出る・〔〕が出ない・
##      反応は判定どおりの1行・ニカの名前・朝のDM・タイムラインのニカの 23:00 は接客のあとから

const FACT := "day1_takeout_served"


## 元の文（.md）の「名前「セリフ」」の行の数（〔ゲーム〕の行・表・見出し・反応の行を除く）。from_heading の見出しから to_heading の見出しの前まで。
func _md_lines(file: String, from_heading: String, to_heading: String) -> Array:
	var text := FileAccess.get_file_as_string("res://planning/scenario/day3/" + file)
	var inside := false
	var out := []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			if line.contains(from_heading):
				inside = true
			elif to_heading != "" and line.contains(to_heading):
				inside = false
			continue
		if inside and line.contains("「") and line.ends_with("」") and not line.begins_with("-") and not line.begins_with("|") and not line.begins_with("〔"):
			out.append(line)
	return out


func _texts(events: Array) -> Array:
	return events.filter(func(e): return str(e.get("type", "")) == "GREET").map(func(e): return str(e["text"]))


func _set_takeout(served: bool) -> void:
	if served:
		CustomerMemory.set_fact("delivery_man", FACT, true)
	else:
		(GameState.memory_entry("delivery_man")["facts"] as Dictionary).erase(FACT)


## 今のランナーで、いまの位置までに出た ADJUST の数（複数杯の場面の何杯目か）。
func _adjust_no(s: PlaySession) -> int:
	var n := 0
	if s.flow.runner == null:
		return 0
	for i in range(mini(s.flow.runner.index + 1, s.flow.runner.events.size())):
		if str(s.flow.runner.events[i].get("type", "")) == "ADJUST":
			n += 1
	return n


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var root_before := t.root.get_children()
	ScheduleData.clear_cache()
	Dm.clear_cache()
	Sns.clear_cache()
	News.clear_cache()
	GameState.reset_for_new_game()

	# --- 1. データ ---
	var achang := ScheduleData.episode_data("delivery_man", "delivery_man_02")
	var nika := ScheduleData.episode_data("streamer", "streamer_01")
	var setiya := ScheduleData.episode_data("hooker", "hooker_02")
	for ep in [achang, nika, setiya]:
		c.check("%s：場面データの形・印に問題が無い・元の文の場所（source）がある" % ep["id"], ScheduleData.scene_problems(ep).is_empty()
			and str(ep.get("source", "")).begins_with("planning/scenario/day3/"), str(ScheduleData.scene_problems(ep)))
	# 阿強：条件が真の道・偽の道で、元の文の行がそれぞれ抜けなく入る
	GameState.day_count = 3
	_set_takeout(true)
	var a_true := _texts(Day1Events._talk("delivery_man", achang["greet"])) + _texts(Day1Events._scene_lines("body", "delivery_man", achang["body"]))
	var md_achang := _md_lines("3日目_運び屋.md", "来店・容器", "実装メモ")
	c.check("阿強（3杯目を出した道）：来店・容器 → 雨と注文 → 食事 → 会計・退店の元の文の行（%d行）がそのまま" % md_achang.size(), a_true == md_achang,
		"%d / %d" % [a_true.size(), md_achang.size()])
	_set_takeout(false)
	var a_false := _texts(Day1Events._talk("delivery_man", achang["greet"])) + _texts(Day1Events._scene_lines("body", "delivery_man", achang["body"]))
	var container := _md_lines("3日目_運び屋.md", "来店・容器", "雨と注文")
	var want_false := ["阿強「まだやってる？　布貸して。脚の端子、拭くから」"]
	want_false.append_array(_md_lines("3日目_運び屋.md", "雨と注文", "提供と反応").slice(1))
	want_false.append_array(_md_lines("3日目_運び屋.md", "食事・知らない依頼元", "会計・退店"))
	want_false.append_array(["阿強「ごちそうさん。あの依頼、聞くだけ聞いてみる」", "店主「返事を待つ間は、雨の当たらんとこにいろ」", "阿強「うん。行ってくる」"])
	c.check("阿強（3杯目を断った道）：来店・容器の節（%d行）と退店の最後の3行が出ず、最初の行が「まだやってる？　布貸して。…」・「雨の当たらんとこにいろ」のあとに「うん。行ってくる」" % container.size(),
		a_false == want_false and not a_false.any(func(x): return container.has(x) or str(x).contains("容器")), "%s" % str(a_false.slice(0, 2)))
	var nested := ["a", { "if": { "fact": "x" }, "lines": ["b", { "if": { "not_fact": "y" }, "lines": ["c"] }] }, { "if": { "not_fact": "x" }, "lines": ["d"] }]
	var resolved_off := CustomerMemory.resolve_lines(nested, "thug")
	CustomerMemory.set_fact("thug", "x", true)
	var resolved_on := CustomerMemory.resolve_lines(nested, "thug")
	var other_customer := CustomerMemory.resolve_lines([{ "if": { "fact": "x", "customer": "thug" }, "lines": ["e"] }], "granny")
	c.check("条件の読み口：事実が真なら fact の行・偽（無い）なら not_fact の行。入れ子も開く・customer を指せば別の客の事実",
		resolved_off == ["a", "d"] and resolved_on == ["a", "b", "c"] and other_customer == ["e"], "%s / %s / %s" % [str(resolved_off), str(resolved_on), str(other_customer)])
	var bad_cond := [
		{ "id": "x", "customer": "thug", "greet": ["a", { "if": { "fact": "" }, "lines": ["b"] }], "reactions": {}, "servings": 1 },
		{ "id": "x", "customer": "thug", "greet": ["a", { "if": { "fact": "k", "not_fact": "k" }, "lines": ["b"] }], "reactions": {}, "servings": 1 },
		{ "id": "x", "customer": "thug", "greet": ["a", { "if": { "fact": "k" }, "lines": [] }], "reactions": {}, "servings": 1 },
		{ "id": "x", "customer": "thug", "body": ["a", { "if": { "fact": "k" }, "lines": ["〔ゲーム〕b"] }], "reactions": {}, "servings": 1 },
		{ "id": "x", "customer": "thug", "greet": ["a", { "if": { "fact": "k", "when": 1 }, "lines": ["b"] }], "reactions": {}, "servings": 1 },
		{ "id": "x", "customer": "thug", "greet": ["a", { "if": { "fact": "k", "customer": "no_such" }, "lines": ["b"] }], "reactions": {}, "servings": 1 },
	]
	c.check("条件付きの行の検査：空のキー・fact と not_fact の両方・空の lines・〔ゲーム〕の行・未知のキー・名前あり客でない customer を弾く",
		bad_cond.all(func(ep): return not ScheduleData.scene_problems(ep).is_empty()))
	# 3杯目を出したときの事実：1日目の場面の3杯目（持ち帰り）だけが持つ
	var cups: Array = ScheduleData.episode_cups("delivery_man", "delivery_man_01")
	c.check("1日目の阿強の3杯目（持ち帰り）だけが、出したときに facts.day1_takeout_served を残す（cups[2].sets_facts）",
		cups.size() == 3 and cups[2].get("sets_facts", {}) == { FACT: true } and not cups[0].has("sets_facts") and not cups[1].has("sets_facts"))
	# ニカ：名乗りの印・元の文
	var nika_lines := _texts(Day1Events._talk("streamer", nika["greet"])) + _texts(Day1Events._scene_lines("body", "streamer", nika["body"]))
	var md_nika := _md_lines("3日目_配信者.md", "来店", "実装メモ")
	c.check("ニカ：来店〜会計・退店の元の文の行（%d行）がそのまま・「ニカ。配信では、その名前」の行に reveal_name ニカ" % md_nika.size(),
		nika_lines == md_nika and Day1Events._talk("streamer", nika["greet"]).filter(func(e): return e.has("reveal_name")).map(func(e): return [e["text"], e["reveal_name"]])
			== [["客「ニカ。配信では、その名前」", "ニカ"]], "%d / %d" % [nika_lines.size(), md_nika.size()])
	var md_setiya := _md_lines("3日目_夜の女.md", "来店・裏口", "実装メモ")
	var setiya_lines := _texts(Day1Events._talk("hooker", setiya["greet"])) + _texts(Day1Events._scene_lines("body", "hooker", setiya["body"]))
	c.check("セティヤ：来店・裏口〜会計・退店の元の文の行（%d行）がそのまま" % md_setiya.size(), setiya_lines == md_setiya, "%d / %d" % [setiya_lines.size(), md_setiya.size()])
	c.check("OK の文は外れた札で2通り（ニカ：歯ごたえが外れた／まろやかが外れた）・札が2つとも外れた・減点の OK は1つ目の文",
		nika["reactions"]["OK_MISSING"]["BITE"] == nika["reactions"]["OK"] and str(nika["reactions"]["OK_MISSING"]["MELLOW"][0]).begins_with("ニカ「噛みごたえ、いいね。")
			and (nika["reactions"] as Dictionary).keys().has("GREAT"))
	c.check("OK_MISSING の検査：注文に無い札・空の文を弾く",
		not ScheduleData.scene_problems({ "id": "x", "customer": "streamer", "greet": ["a"], "servings": 1, "reactions": { "OK": ["a"], "OK_MISSING": { "HOT": ["b"] } } }).is_empty()
			and not ScheduleData.scene_problems({ "id": "x", "customer": "streamer", "greet": ["a"], "servings": 1, "reactions": { "OK": ["a"], "OK_MISSING": { "BITE": [] } } }).is_empty())
	# 今日の頼み（遊びに効く変更。別のコミット）：阿強＝辛い＋腹もち・セティヤ＝まろやか＋ごちそう。ニカはデータのまま。いつもの注文は変えない
	c.check("今日の頼み：阿強＝辛い＋腹もち・セティヤ＝まろやか＋ごちそう（order.today_request）。ニカは無し。customers の wanted_tags はそのまま",
		ScheduleData.episode_today_request("delivery_man", "delivery_man_02").get("tags", []) == ["HOT", "FILLING"]
			and ScheduleData.episode_today_request("hooker", "hooker_02").get("tags", []) == ["MELLOW", "TREAT"]
			and ScheduleData.episode_today_request("streamer", "streamer_01").is_empty()
			and ScheduleData.customer_profile("delivery_man")["wanted_tags"] == ["HOT", "POWER"] and ScheduleData.customer_profile("hooker")["wanted_tags"] == ["BITTER", "TREAT"]
			and ScheduleData.customer_profile("streamer")["wanted_tags"] == ["MELLOW", "BITE"])
	c.check("OK の文は外れた札で2通り（阿強：腹もちが外れた／辛さが外れた・セティヤ：ごちそうが外れた／まろやかが外れた）",
		achang["reactions"]["OK_MISSING"]["FILLING"] == achang["reactions"]["OK"] and str(achang["reactions"]["OK_MISSING"]["HOT"][0]).contains("赤いやつ")
			and setiya["reactions"]["OK_MISSING"]["TREAT"] == setiya["reactions"]["OK"] and str(setiya["reactions"]["OK_MISSING"]["MELLOW"][0]).contains("まろやかなのが良かった"))
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	var grade_of := func(additions: Array, wanted: Array, favorite: String) -> String: return str(Judge.grade({ "additions": additions }, GameState.soup, { "wanted_tags": wanted, "favorite": favorite })["grade"])
	c.check("手がかりと札：阿強の GREAT＝辛い調味料＋腹もちの具（米麺・割れた餃子皮）＋豆腐。肉団子では腹もちにならない",
		grade_of.call(["nam_prik_pao", "rice_noodle", "tofu"], ["HOT", "FILLING"], "tofu") == "GREAT" and grade_of.call(["nam_prik_pao", "broken_wrapper", "tofu"], ["HOT", "FILLING"], "tofu") == "GREAT"
			and grade_of.call(["nam_prik_pao", "meat_ball"], ["HOT", "FILLING"], "tofu") != "GOOD")
	c.check("手がかりと札：セティヤの GREAT＝ココナッツミルク＋ごちそうの具＋塩漬けライム（ライムで酸っぱいが増えても、まろやかの頼みは満たしたまま）",
		grade_of.call(["coconut_milk", "shrimp", "pickled_lime"], ["MELLOW", "TREAT"], "pickled_lime") == "GREAT" and grade_of.call(["coconut_milk", "clam"], ["MELLOW", "TREAT"], "pickled_lime") == "GOOD")
	c.check("手がかりと札：ニカの GREAT＝ココナッツミルク＋歯ごたえの具（軟骨・乾燥きくらげ・すじ肉）＋海老。海老は歯ごたえの代わりにならない",
		grade_of.call(["coconut_milk", "cartilage", "shrimp"], ["MELLOW", "BITE"], "shrimp") == "GREAT" and grade_of.call(["coconut_milk", "dried_wood_ear", "shrimp"], ["MELLOW", "BITE"], "shrimp") == "GREAT"
			and grade_of.call(["coconut_milk", "shrimp"], ["MELLOW", "BITE"], "shrimp") != "GREAT")
	# 市場
	var talk := ScheduleData.talk_data("day3_market")
	var parts: Array = talk.get("parts", [])
	var zhang_md := _md_lines("3日目_昼市場.md", "張記肉類加工", "福生豆腐麺房")
	var liang_md := _md_lines("3日目_昼市場.md", "共同水場", "実装メモ")
	c.check("市場の場面：張姐（着いたとき。%d行。仕込む量の印の前は「で、今日はどれ位仕込む？」まで・あとに2行。必須情報の印 new_window_cargo）と梁伯（出るとき。%d行。払う印なし）" % [zhang_md.size(), liang_md.size()],
		parts.size() == 2 and str(parts[0]["when"]) == "arrive" and parts[0]["lines"].filter(func(l): return l is String) == zhang_md
			and parts[0]["lines"][zhang_md.size() - 2] is Dictionary and str(parts[0]["lines"][zhang_md.size() - 3]).ends_with("で、今日はどれ位仕込む？」")
			and parts[0]["must_info"] == ["new_window_cargo"]
			and str(parts[1]["when"]) == "exit" and parts[1]["lines"] == liang_md
			and Rules.day_overrides(3).get("market_scene", "") == "day3_market")
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var exit_scene_3 := Day1Events.has_market_exit_scene()
	var pays_3 := Day1Events.market_exit_pays_in_scene()
	GameState.day_count = 1
	var pays_1 := Day1Events.market_exit_pays_in_scene()
	GameState.day_count = 2
	var exit_scene_2 := Day1Events.has_market_exit_scene()
	c.check("3日目は市場を出たあとの場面がある・払う印は無い（市場を出るときにまとめて払う。1日目だけ会話ごとに払う。2日目は出るときの場面が無い）",
		exit_scene_3 and not pays_3 and pays_1 and not exit_scene_2)
	GameState.day_count = 3
	var before := Day1Events.prep_events({}, false)
	var after := Day1Events.prep_after_tier_events(Day1Events.prep_tier_by_id("medium"), false)
	var types: Array = after.map(func(e): return str(e["type"]))
	var market_at := types.find("MARKET")
	c.check("市場の列：張姐の会話 → 仕込む量（文は張姐の最後の問い）→ 選んだあとの2行（先頭は効果の無い文）→ 鍋の素 → 市場 → 梁伯 → 「水を汲み、炭を買った（炭代−¥40・水代−¥35）。」。PAY は無い",
		before.map(func(e): return str(e["text"])) == zhang_md.slice(0, zhang_md.size() - 2) and str(before.back()["type"]) == "PREP_TIER"
			and after.slice(0, 2).map(func(e): return str(e["text"])) == zhang_md.slice(zhang_md.size() - 2) and str(after[0]["type"]) == "TEXT"
			and str(after[2]["type"]) == "ADD_ITEM" and market_at == 3
			and after.slice(market_at + 1, market_at + 1 + liang_md.size()).map(func(e): return str(e["text"])) == liang_md
			and after.slice(market_at + 1, market_at + 1 + liang_md.size()).all(func(e): return str(e.get("part", "")) == "market_exit")
			and str(after[market_at + 1 + liang_md.size()]["text"]) == "水を汲み、炭を買った（炭代−¥40・水代−¥35）。"
			and not (before + after).any(func(e): return str(e["type"]) == "PAY"))

	# --- 3. 名乗る前の名前 ---
	GameState.reset_for_new_game()
	c.check("配信者は名乗る前は「初めての客」（プロフィールの name は「配信者」のまま）・新人警官は今のまま「新人警官」",
		CustomerMemory.display_name("streamer") == "初めての客" and ScheduleData.customer_display_name("streamer") == "配信者"
			and CustomerMemory.display_name("officer") == "新人警官")
	CustomerMemory.reveal_name("streamer", "ニカ")
	c.check("名乗ったあとは「ニカ」", CustomerMemory.display_name("streamer") == "ニカ")

	# --- 4. モブ（3日目の文）・予備の一言 ---
	var mob_tags := { "inn_clerk": ["MELLOW", "GENTLE"], "general_store_clerk": ["BITTER", "GENTLE"], "street_cleaners": ["SOUR", "FILLING"] }
	var mob_heads := { "inn_clerk": ["宵の口　安宿の夜勤受付", "夜半"], "general_store_clerk": ["夜半　雑貨屋の夜番", "明け方"], "street_cleaners": ["明け方　夜間清掃員", "四組目"] }
	for mob_id in mob_tags:
		var day3: Dictionary = ScheduleData.mob_data_for_day(mob_id, 3)
		var md := _md_lines("3日目_モブ3組.md", mob_heads[mob_id][0], mob_heads[mob_id][1])
		var one := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(day3["greet"], 1))
		var two := ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(day3["greet"], 2))
		c.check("%s：3日目の文（1杯の組 %d行・2杯以上は「…分も」の1行を足す）・会計の後の会話・OK は外れた札で2通り・注文の札はデータのまま %s・GREAT は無い" % [mob_id, one.size(), str(mob_tags[mob_id])],
			two.size() == one.size() + 1 and two + day3["after_talk"] == md and day3["wanted_tags"] == mob_tags[mob_id]
				and (day3["reactions"]["OK_MISSING"] as Dictionary).keys().all(func(k): return (mob_tags[mob_id] as Array).has(k))
				and (day3["reactions"]["OK_MISSING"] as Dictionary).size() == 2 and not (day3["reactions"] as Dictionary).has("GREAT")
				and ScheduleData.marker_problems(two + day3["after_talk"] + day3["spare_greet"].filter(func(l): return l is String), mob_id).is_empty(),
			"%s / %s" % [str(two.size() + (day3["after_talk"] as Array).size()), str(md.size())])
		c.check("%s：予備の一言（spare_greet）は、表の一言＋注文の行＋「…分も」の行。予備の退店の文（spare_farewell。中身Z2）は1行" % mob_id,
			str(day3["spare_greet"][0]) != str(day3["greet"][0]) and (day3["spare_greet"] as Array).back() == (day3["greet"] as Array).back()
				and (day3["spare_farewell"] as Array).size() == 1 and not (day3["after_talk"] as Array).has(day3["spare_farewell"][0]))
		c.check("%s：ほかの日（5日目）は日をまたぐ文のまま" % mob_id, not ScheduleData.mob_data_for_day(mob_id, 5).has("spare_greet"))
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.today_plan = { "day": 3, "slots": [], "mob_instances": { "mob#0": { "type": "inn_clerk", "count": 2 }, "mob#1": { "type": "general_store_clerk", "count": 2 },
		"mob#2": { "type": "street_cleaners", "count": 1 }, "mob#3": { "type": "inn_clerk", "count": 1 } } }
	var first: Dictionary = Day1Events._customer_flavor("mob#0")
	var second: Dictionary = Day1Events._customer_flavor("mob#3")
	var inn3: Dictionary = ScheduleData.mob_data_for_day("inn_clerk", 3)
	c.check("同じ晩に同じ職種の2組目（mob#3。mob#0 と同じ受付）は、予備の一言＋注文の行（1組目の会話は出ない）。注文・反応は同じ",
		not Day1Events.is_repeat_mob_group("mob#0") and Day1Events.is_repeat_mob_group("mob#3") and not Day1Events.is_repeat_mob_group("mob#2")
			and first["greet"] == ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(inn3["greet"], 2))
			and second["greet"] == ["受付「濡れた傘を並べたら、どれが誰のか分からなくなりまして。札を作る前に、夕飯を買いに来ました」", "受付「持ち帰りでお願いします。まろやかな汁に、胃にやさしい具を」"]
			and second["wanted_tags"] == first["wanted_tags"] and second["reactions"] == first["reactions"]
			and Day1Events.mob_after_talk_events("mob#3").map(func(e): return str(e["text"])) == ["受付「ごちそうさまです。傘の札、戻ったら作ります」"]
			and Day1Events.mob_after_talk_events("mob#0").map(func(e): return str(e["text"])) == inn3["after_talk"], str(second["greet"]))

	# --- 5. DM（3日目）---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.customer_memory["delivery_man"] = { "favorite_known": false, "visits": [{ "day": 1, "served": 3, "grade": "GOOD" }], "facts": { FACT: true }, "seen_episodes": [] }
	GameState.customer_memory["hooker"] = { "favorite_known": false, "visits": [{ "day": 2, "served": 1, "grade": "GOOD" }], "facts": {}, "seen_episodes": [] }
	GameState.today_plan = { "day": 3, "slots": [{ "name": "宵の口", "customers": ["delivery_man"], "regular_id": "delivery_man" },
		{ "name": "夜半", "customers": ["streamer"], "regular_id": "streamer" }, { "name": "明け方", "customers": ["hooker"], "regular_id": "hooker" }],
		"mob_instances": {}, "demand_center": 9 }
	var dm_a := Dm.delivered_for_day(3)
	c.check("3日目の朝のDM（3杯目を出した道）：張姐 6:35・阿強 7:10（容器の文）・セティヤ 7:45。来店予告は出ない（阿強・セティヤはDMが代わり・ニカは初来店の前）",
		dm_a.map(func(x): return "%s %s" % [x["from"], x["time"]]) == ["張姐 6:35", "阿強 7:10", "セティヤ 7:45"] and str(dm_a[1]["text"]).begins_with("門のおっさんが容器洗っといたって。")
			and not dm_a.any(func(x): return bool(x.get("preview", false))), str(dm_a.map(func(x): return x["id"])))
	GameState.customer_memory["delivery_man"]["facts"] = {}
	var dm_b := Dm.delivered_for_day(3)
	c.check("3日目の朝のDM（3杯目を断った道）：阿強は「今夜寄る。雨だと次いつ休めるか読めないから、腹にたまるやつ頼む。」",
		dm_b.map(func(x): return str(x["id"])) == ["d3_market", "d3_delivery_man_declined", "d3_hooker"]
			and str(dm_b[1]["text"]) == "今夜寄る。雨だと次いつ休めるか読めないから、腹にたまるやつ頼む。")
	c.check("3日目のDMは本番の文（provisional なし）・仮の3件（d3_market_quiet・d3_officer）は無い・数字と「客足」は書かない",
		Dm.items_for_day(3).all(func(x): return not bool(x.get("provisional", true)) and not str(x["text"]).contains("客足"))
			and not Dm.items_for_day(3).any(func(x): return ["d3_market_quiet", "d3_officer"].has(str(x["id"]))))
	var bad_dm: Dictionary = (Dm.data() as Dictionary).duplicate(true)
	bad_dm["days"]["3"][1]["if"] = { "fact": "" }
	c.check("DMの if の形も検査する", not Dm.problems(bad_dm).is_empty() and Dm.problems().is_empty(), str(Dm.problems()))

	# --- 6. 3日目を朝から閉店まで本番の画面で通す（3杯目を出した道・断った道） ---
	for takeout in [true, false]:
		_play_day3(t, c, takeout)

	ReadState.reset(ReadState.path)
	GameState.reset_for_new_game()
	TestCheck.free_added(t, root_before)
	return c.finish()


func _play_day3(t: SceneTree, c: TestCheck, takeout: bool) -> void:
	var label := "3杯目を出した道" if takeout else "3杯目を断った道"
	ReadState.reset("user://test_read_day3_script.json")
	GameState.reset_for_new_game()
	ScheduleData.clear_cache()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	root.full_prep.auto_advance = false
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	if not takeout:
		play.decline_when = func(): return GameState.day_count == 1 and s.open != null and str(s.open.current_customer()) == "delivery_man" and _adjust_no(s) == 3
	var guard := 0
	var fact_on_day2 = null
	while GameState.day_count < 3 and guard < 12000:
		guard += 1
		if GameState.day_count == 2 and fact_on_day2 == null:
			fact_on_day2 = CustomerMemory.fact("delivery_man", FACT, false)
		if play.step() == "":
			break
	c.check("（%s）Day1・Day2 を遊び、Day3 の朝へ進んだ・facts.%s は %s" % [label, FACT, str(takeout)],
		GameState.day_count == 3 and bool(CustomerMemory.fact("delivery_man", FACT, false)) == takeout and bool(fact_on_day2) == takeout,
		"day=%d fact=%s" % [GameState.day_count, str(CustomerMemory.fact("delivery_man", FACT, null))])
	var day2_ids: Array = Dm.inbox(3).filter(func(x): return int(x["day"]) == 2).map(func(x): return str(x["id"]))
	c.check("（%s）中身Z2：2日目の朝の阿強のDM（容器）は、3杯目を出した道だけ" % label, day2_ids.has("d2_delivery_man") == takeout, str(day2_ids))
	var inbox := Dm.inbox(3).filter(func(x): return int(x["day"]) == 3)
	c.check("（%s）Day3 の朝のDM：張姐・阿強（%s）・セティヤ。阿強・セティヤ・ニカの予告は無い" % [label, "容器の文" if takeout else "断った道の文"],
		inbox.map(func(x): return str(x["id"])).has("d3_market") and inbox.map(func(x): return str(x["id"])).has("d3_delivery_man" if takeout else "d3_delivery_man_declined")
			and not inbox.map(func(x): return str(x["id"])).has("d3_delivery_man_declined" if takeout else "d3_delivery_man")
			and inbox.map(func(x): return str(x["id"])).has("d3_hooker")
			and not inbox.any(func(x): return ["delivery_man", "hooker", "streamer"].has(str(x.get("subject", "")))), str(inbox.map(func(x): return x["id"])))
	var shown_lines := []
	var shown_keys := {}
	var bracket_shown := []
	var reactions := []
	var reacted := {}
	var plan_slots: Array = []
	var plan_mobs := {}
	var served_at_close := []
	var nika_name_at := {}
	var nika23_before := false
	var nika23_after := false
	guard = 0
	while GameState.day_count == 3 and guard < 8000:
		guard += 1
		var box_text := str(root.left.get_node("%DialogueText").text)
		if box_text.contains("〔"):
			bracket_shown.append(box_text)
		var line := s.current_line()
		if GameState.phase == GameState.Phase.OPEN and plan_slots.is_empty():
			plan_slots = (GameState.today_plan["slots"] as Array).duplicate(true)
			plan_mobs = (GameState.today_plan["mob_instances"] as Dictionary).duplicate(true)
		if GameState.phase == GameState.Phase.OPEN and s.open != null:
			var visible := Sns.visible_ids(3, s.timeline_limit(), {}, s.market_talks_done(), s.phone_visits_done_today()).has("d3_exposure_test_2300")
			var cur := str(s.open.current_customer())
			var slot_name := s.open.current_slot_name()
			if (slot_name == "宵の口" or cur == "streamer") and visible:
				nika23_before = true
			if slot_name != "宵の口" and cur != "streamer" and s.open.slot_index >= 1 and visible:
				nika23_after = true
		if str(line.get("type", "")) == "REACT" and str(line.get("text", "")) != "" and s.open != null:
			var key := "%d|%d|%d" % [s.open.slot_index, s.open.index, s.flow.runner.index]
			if not reacted.has(key):
				reacted[key] = true
				var ev: Dictionary = s.flow.runner.current()
				reactions.append({ "grade": str(s.open.current_bowl.get("result", "")), "text": s.current_reaction_text(),
					"pool": ev.get("reactions", {}), "customer": str(ev.get("customer", "")) })
		var name := str(line.get("speaker_name", ""))
		if s.flow.runner != null and str(line.get("text", "")) != "" and str(line.get("type", "")) != "REACT":
			var line_key := "%d|%d|%d|%d|%s" % [GameState.phase, s.open.slot_index if s.open != null else -1, s.open.index if s.open != null else -1,
				s.flow.runner.index, str(line.get("text", ""))]
			if not shown_keys.has(line_key):
				shown_keys[line_key] = true
				shown_lines.append(name + str(line.get("text", "")))
				if str(line.get("speaker", "")) == "streamer":
					nika_name_at[name + str(line.get("text", ""))] = CustomerMemory.display_name("streamer")
		if GameState.phase == GameState.Phase.CLOSE and served_at_close.is_empty():
			served_at_close = GameState.served.duplicate(true)
		if play.step() == "":
			break
	c.check("（%s）Day3 を閉店まで遊び、Day4 の朝へ進んだ" % label, GameState.day_count == 4, "day=%d phase=%d" % [GameState.day_count, GameState.phase])
	c.check("（%s）会話枠に〔〕の文（〔ゲーム〕・実装メモ）が一度も出ない" % label, bracket_shown.is_empty(), str(bracket_shown))
	# 出てくるはずの順（張姐 → 梁伯 → 夜の枠の順に客。モブは出したときだけ椀のあとの会話）
	var talk: Array = ScheduleData.talk_data("day3_market")["parts"]
	var expected: Array = (talk[0]["lines"] as Array).filter(func(l): return l is String)
	expected.append_array(talk[1]["lines"])
	var declined := {}
	for rec in served_at_close:
		if bool(rec.get("declined", false)) or int(rec.get("servings", 0)) <= 0:
			declined[str(rec.get("customer", ""))] = true
	var mob_types := []
	for slot in plan_slots:
		for id in slot["customers"]:
			if str(id).begins_with("mob#"):
				var type_id := str(plan_mobs[id]["type"])
				var count := int(plan_mobs[id]["count"])
				mob_types.append("%s×%d" % [type_id, count])
				var day3 := ScheduleData.mob_data_for_day(type_id, 3)
				var repeat := false
				for other in plan_mobs:
					repeat = repeat or (int(str(other).trim_prefix("mob#")) < int(str(id).trim_prefix("mob#")) and str(plan_mobs[other]["type"]) == type_id)
				expected.append_array(ScheduleData.spoken_lines(ScheduleData.mob_lines_for_count(day3["spare_greet"] if repeat else day3["greet"], count)))
				if not declined.has(str(id)):
					expected.append_array(day3["after_talk"])
			else:
				var ep := ScheduleData.episode_data(str(id), str(slot["episode_id"]))
				expected.append_array(ScheduleData.spoken_lines(CustomerMemory.resolve_lines(ep["greet"], str(id))))
				if not declined.has(str(id)):
					expected.append_array(ScheduleData.spoken_lines(CustomerMemory.resolve_lines(ep["body"], str(id))))
	var got := shown_lines.filter(func(x): return str(x).contains("「") and not str(x).begins_with("「"))
	var first_diff := -1
	for i in range(maxi(got.size(), expected.size())):
		if i >= got.size() or i >= expected.size() or got[i] != expected[i]:
			first_diff = i
			break
	c.check("（%s）Day3 の元の文の行（%d行）が、張姐→梁伯→宵の口→夜半→明け方の順に、抜けも重なりも無く出た（モブ %s）" % [label, expected.size(), str(mob_types)],
		first_diff == -1, "最初に違う行 %d：%s ／ 期待 %s" % [first_diff, str(got[first_diff]) if first_diff >= 0 and first_diff < got.size() else "（無い）",
			str(expected[first_diff]) if first_diff >= 0 and first_diff < expected.size() else "（無い）"])
	c.check("（%s）阿強の容器の行は、3杯目を出した道だけに出る" % label, got.has("阿強「先にこれ。容器、帰ってきたよ」") == takeout
		and got.has("阿強「まだやってる？　布貸して。脚の端子、拭くから」") != takeout and got.has("阿強「うん。行ってくる」") != takeout
		or declined.has("delivery_man"))
	var react_ok := true
	for r in reactions:
		var pool: Array = (r["pool"] as Dictionary).get(r["grade"], []).duplicate()
		if r["grade"] == "OK" and (r["pool"] as Dictionary).get("OK_MISSING") is Dictionary:
			for tag in r["pool"]["OK_MISSING"]:
				pool.append_array(r["pool"]["OK_MISSING"][tag])
		react_ok = react_ok and pool.has(r["text"]) and not str(r["text"]).contains("\n") and not str(r["text"]).contains("〔")
	c.check("（%s）反応は、判定の結果の段の元の文の1行だけ（OK は外れた札の文も。%d回）" % [label, reactions.size()], react_ok and reactions.size() >= 3,
		str(reactions.map(func(r): return "%s %s %s" % [r["customer"], r["grade"], r["text"]])))
	c.check("（%s）ニカの表示名：「誰だか分からん相手には…」の行まで「初めての客」、「ニカ。配信では、その名前」の行から「ニカ」（Day4 の朝も）" % label,
		nika_name_at.get("店主「誰だか分からん相手には、いいとも言えんな」", "") == "初めての客" and nika_name_at.get("客「ニカ。配信では、その名前」", "") == "ニカ"
			and CustomerMemory.display_name("streamer") == "ニカ" and got.has("ニカ「分かった。目の録画、いまは切ってる。撮る前に、もう一回言うね」"),
		str(nika_name_at.get("客「ニカ。配信では、その名前」", "")))
	c.check("（%s）タイムラインのニカの 23:00：宵の口・ニカの接客中は見えず、ニカのあと（夜半のモブ・明け方）は見える" % label, not nika23_before and nika23_after)
	root.queue_free()
