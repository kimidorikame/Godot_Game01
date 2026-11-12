extends RefCounted
## UI準備V2：会話枠の自前の折り返し（UiLeftSide.paginate。30字×3行）の行頭禁則（追い出し）。
##   1. 次の行の頭に禁則の文字が来るときは、前の行の最後の字を次の行へ送る。送った字も禁則の文字なら、さらにさかのぼる。
##   2. 1日目の会話枠に出る文（常連・モブの1日目の文・市場の会話）のどれも、行の頭に禁則の文字が来ない。
##      UI準備V の報告にあった9か所も直っている。


func _all_lines(pages: Array) -> Array:
	var out := []
	for page in pages:
		out.append_array(str(page).split("\n"))
	return out


func _bad_heads(text: String) -> Array:
	var lines := _all_lines(UiLeftSide.paginate(text))
	var bad := []
	for i in range(1, lines.size()):
		if str(lines[i]) != "" and UiLeftSide.KINSOKU_HEAD.contains(str(lines[i]).substr(0, 1)):
			bad.append(str(lines[i]).substr(0, 6))
	return bad


## 1日目の会話枠に出る文（名前を除いた本文）。
func _day1_texts() -> Array:
	var raw := []
	for pair in [["delivery_man", "delivery_man_01"], ["thug", "thug_01"], ["granny", "granny_01"]]:
		var ep := ScheduleData.episode_data(pair[0], pair[1])
		for key in ["greet", "body"]:
			raw.append_array(ScheduleData.spoken_lines(ep.get(key, [])))
		for r in (ep.get("reactions", {}) as Dictionary).values():
			raw.append_array(r)
		for cup in ScheduleData.episode_cups(pair[0], pair[1]):
			raw.append_array(ScheduleData.spoken_lines(cup.get("after_talk", [])))
			if cup.has("serve"):
				raw.append(str(cup["serve"]))
			for r in (cup.get("reactions", {}) as Dictionary).values():
				raw.append_array(r)
	for mob in ["dock_workers", "inn_clerk"]:
		var form := ScheduleData.mob_data_for_day(mob, 1)
		raw.append_array(ScheduleData.spoken_lines(form["greet"]))
		raw.append_array(ScheduleData.spoken_lines(form["after_talk"]))
		for key in form["reactions"]:
			var r = form["reactions"][key]
			if r is Array:
				raw.append_array(r)
			elif r is Dictionary:
				for v in (r as Dictionary).values():
					raw.append_array(v)
	for part in ScheduleData.talk_data("day1_market")["parts"]:
		raw.append_array(ScheduleData.spoken_lines(part["lines"]))
	var texts := []
	for line in raw:
		texts.append(str(PlaySession.split_speaker(str(line))["text"]))
	return texts


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()

	# --- 1. 追い出しの決まり ---
	var t30 := "あ".repeat(30)
	c.check("30字ちょうどは1行のまま・31字目が普通の字なら次の行へ（今までどおり）",
		UiLeftSide.paginate(t30) == [t30] and UiLeftSide.paginate(t30 + "い") == [t30 + "\nい"])
	c.check("31字目が「。」なら、前の行の最後の1字を連れて次の行へ（29字＋「あ。」）",
		UiLeftSide.paginate(t30 + "。") == ["あ".repeat(29) + "\nあ。"], str(UiLeftSide.paginate(t30 + "。")))
	c.check("「。」」が続くときは、さらにさかのぼる（行の頭に「」」も「。」も来ない）",
		UiLeftSide.paginate("あ".repeat(29) + "。」") == ["あ".repeat(28) + "\nあ。」"], str(UiLeftSide.paginate("あ".repeat(29) + "。」")))
	var all_ng := true
	for ch in UiLeftSide.KINSOKU_HEAD:
		all_ng = all_ng and _bad_heads(t30 + ch + "いうえ").is_empty() and _bad_heads("「" + "あ".repeat(28) + ch + "」いう").is_empty()
	c.check("禁則の文字（%s）のどれも行の頭に来ない" % UiLeftSide.KINSOKU_HEAD, all_ng)
	c.check("90字で3行ちょうどの文の次に「。」が来ると、追い出しで4行になり2ページ目へ（ページが増えるのはよい）", UiLeftSide.paginate("あ".repeat(90) + "。").size() == 2)

	# --- 2. 1日目の会話枠に出る文 ---
	var texts := _day1_texts()
	var bad := {}
	var multi := 0
	for text in texts:
		var b := _bad_heads(text)
		if not b.is_empty():
			bad[text] = b
		if UiLeftSide.paginate(text).size() > 1:
			multi += 1
	c.check("1日目の会話枠に出る文（%d本）のどれも、行の頭に禁則の文字が来ない" % texts.size(), texts.size() > 250 and bad.is_empty(), str(bad))
	for line in ["「俺が探してるの覚えててさ。『あったよ』って写真が来たんだよ。缶と瓶の真ん中に、こいつが置いてあんの」",
			"「お、残業の明細来た。八番の荷、ちゃんとうちの班についてる！」"]:
		c.check("UI準備V の報告の行が直った：%s" % line.substr(0, 12), texts.has(line) and _bad_heads(line).is_empty(), str(UiLeftSide.paginate(line)))
	c.check("1日目の文で、2ページ以上になるのは %d 本（追い出しで行が増えた分も含む）" % multi, multi <= 3)
	print("  1日目の会話枠の文：%d本・2ページ以上：%d本" % [texts.size(), multi])

	ScheduleData.clear_cache()
	return c.finish()
