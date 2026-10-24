extends RefCounted
## 朝のニュースの提示とニュースタブ（システム整理D-②。DESIGN.md 10.5.5）の検証。
## WAKE のイベント列に、その日のニュースとDM（TEXT）が「スマホを見る。」の後へ必ず差し込まれる。
## ニュースの無い日は従来の列と同一。再挑戦・続きから・新しい周で同じ表示。ニュースタブは今日と
## 過ぎた日だけ（未来の日は見せない）。表示だけで、ゲームの数値・保存には触れない。


func _wake_panel(t: SceneTree, day: int):
	GameState.reset_for_new_game()
	GameState.day_count = day
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む
	return panel


func _texts(events: Array) -> Array:
	var out := []
	for ev in events:
		out.append(str(ev.get("text", "")))
	return out


func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	News.clear_cache()
	ScheduleData.clear_cache()

	# --- 1. 各日のWAKE：スマホを見る → ニュース（見出し→本文）→ DM → 従来の語り の順 ---
	for day in range(1, 8):
		GameState.reset_for_new_game()
		GameState.day_count = day
		var events := Day1Events.wake_events()
		var types := []
		for ev in events:
			types.append(str(ev["type"]))
		var news := News.morning_events(day)
		c.check("Day%d：ニュースの行が1つ以上ある" % day, not news.is_empty())
		c.check("Day%d：先頭は効果の無いTEXT、2番目は「スマホを見る。」（WAIT_INPUT）" % day,
			types[0] == "TEXT" and types[1] == EventRunner.TYPE_WAIT_INPUT and str(events[1]["text"]) == "スマホを見る。")
		c.check("Day%d：ニュース・DMは「スマホを見る。」の直後、従来の語りの前に並ぶ" % day,
			events.slice(2, 2 + news.size()) == news
				and str(events[2 + news.size()]["text"]).begins_with("共同水道と炭屋")
				and str(events[events.size() - 1]["text"]) == "さて、準備へ向かうか。")
		var all_news := true
		for ev in news:
			all_news = all_news and str(ev["type"]) == "TEXT" and str(ev["part"]) == "news"
		c.check("Day%d：差し込む行は効果の無いTEXT（part:news）だけ" % day, all_news)
		var headline := str(News.day_entry(day)["news"][0]["headline"])
		c.check("Day%d：見出しが「ニュース：…」で含まれる" % day, _texts(events).has("ニュース：" + headline))
		c.check("Day%d：必須情報の印のある項目がすべて朝に出る" % day, _must_info_headlines_present(day, events))

	# --- 2. 必須情報が朝に届く（Day6の衝突・火災は共通イベント）。DMも出る ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	c.check("DM（市場の顔なじみ）もニュースの後に出る",
		_texts(Day1Events.wake_events()).has("DM（市場の顔なじみ）：今日は入荷が遅れてる。早めに来な"))
	GameState.day_count = 1
	c.check("DMの無い日（Day1）はDMが出ない", not str(_texts(Day1Events.wake_events())).contains("DM（"))

	# --- 3. ニュースの無い日は従来の列と同一 ---
	News._cache = { "id": "week7", "days": {} }
	News._loaded_id = Rules.news()
	GameState.reset_for_new_game()
	var plain := Day1Events.wake_events()
	c.check("ニュースの無い日：従来の4イベント（目が覚めた→スマホ→水道→準備）",
		plain.size() == 4 and str(plain[1]["text"]) == "スマホを見る。"
			and str(plain[2]["text"]).begins_with("共同水道と炭屋") and str(plain[3]["text"]) == "さて、準備へ向かうか。")
	c.check("ニュースの無いデータのニュースタブは「まだ届いていません」", News.tab_text(3) == "ニュース：まだ届いていません")
	News.clear_cache()

	# --- 4. 実際のWAKE（前日の成績の一言があるとき）：成績 → 目が覚めた → スマホ → ニュース ---
	var p4 = _wake_panel(t, 3)
	var ev4: Array = p4.session.flow.runner.events
	c.check("パネルのWAKEにも差し込まれる（Day3：迂回輸送の見出し）",
		_texts(ev4).has("ニュース：迂回輸送で市内の物流が混乱。歓楽街では客足が落ちている"))
	p4.free()
	GameState.reset_for_new_game()
	GameState.day_count = 3
	var p4b = load("res://scenes/debug_panel.tscn").instantiate()
	p4b.session.last_day_summary_text = "【前日の成績】テスト"
	t.root.add_child(p4b)
	# _ready()がWAKEを組むときに前日の成績の一言を先頭へ差す
	c.check("前日の成績の一言があれば先頭、その後に 目が覚めた → スマホ → ニュース",
		str(p4b.session.flow.runner.events[0]["text"]).begins_with("【前日の成績】")
			and str(p4b.session.flow.runner.events[1]["text"]).begins_with("……目が覚めた")
			and str(p4b.session.flow.runner.events[2]["text"]) == "スマホを見る。"
			and str(p4b.session.flow.runner.events[3]["text"]).begins_with("ニュース："))
	p4b.free()

	# --- 5. 再挑戦（朝へ戻す）・続きから・新しい周で、同じ表示 ---
	var p5 = _wake_panel(t, 3)
	var first_events = _norm(p5.session.flow.runner.events)
	GameState.day_count = 5   # 先へ進んだことにして、朝へ戻す
	c.check("朝（Day3）へ戻せる", p5.retry_from_morning(3) and GameState.day_count == 3)
	c.check("再挑戦：同じ朝のWAKEのイベント列が同一（ニュースも同じ）", _norm(p5.session.flow.runner.events) == first_events)
	p5.session.pending_continue = GameState.morning_of(3)
	p5._on_continue_pressed()
	c.check("続きから読み込んだ朝も同じ表示", _norm(p5.session.flow.runner.events) == first_events)
	p5._on_new_run_pressed()
	c.check("新しい周：Day1の朝のニュース（ストの見出し）",
		GameState.day_count == 1 and _texts(p5.session.flow.runner.events).has("ニュース：第八码頭で夜間荷役がストに入った"))
	p5.free()

	# --- 6. ニュースタブ：今日と過ぎた日だけ。未来は見せない。ニュースとDMは別の見出し ---
	var p6 = _wake_panel(t, 2)   # Day2の朝の記録を持つ周
	GameState.day_count = 4      # 先へ進んだことにして、Day4の時点のタブを見る
	p6._phone_tab = "news"
	var tab: String = p6._format_phone()
	c.check("ニュースタブに今日（Day4）の見出しと本文が出る", tab.contains("◆今日（Day4）◆") and tab.contains("現場を撮った動画が拡散"))
	c.check("過ぎた日（Day1〜3）の分も読み返せる",
		tab.contains("◆Day3◆") and tab.contains("◆Day2◆") and tab.contains("◆Day1◆")
			and tab.contains("第八码頭で夜間荷役がストに入った") and tab.contains("検問が始まった"))
	c.check("未来の日（Day5以降）は出ない", not tab.contains("◆Day5◆") and not tab.contains("運営会社の変更")
		and not tab.contains("強行搬出") and not tab.contains("放火"))
	c.check("新しい日が上（Day4 → Day3 → Day2 → Day1）",
		tab.find("◆今日（Day4）◆") < tab.find("◆Day3◆") and tab.find("◆Day3◆") < tab.find("◆Day2◆")
			and tab.find("◆Day2◆") < tab.find("◆Day1◆"))
	c.check("DMはニュースと別の行（DM（…）：）", tab.contains("DM（市場の顔なじみ）：") and tab.contains("【仮】"))
	# 再挑戦で戻した朝より後の日は見えない
	GameState.day_count = 6
	p6.retry_from_morning(2)
	p6._phone_tab = "news"
	var back_tab: String = p6._format_phone()
	c.check("Day2の朝へ戻すと、Day3以降の分は見えない（Day1・Day2だけ）",
		back_tab.contains("◆今日（Day2）◆") and back_tab.contains("◆Day1◆")
			and not back_tab.contains("◆Day3◆") and not back_tab.contains("迂回輸送"))
	p6.free()

	# --- 7. 表示だけ：数値・保存・読み出しは副作用なし ---
	GameState.reset_for_new_game()
	GameState.day_count = 5
	var before := GameState.to_dict()
	for i in range(3):
		Day1Events.wake_events()
		News.morning_events(5)
		News.tab_text(5)
	c.check("何度呼んでも状態（GameState）が変わらない", GameState.to_dict() == before)
	c.check("ニュースで保存の版を上げていない（日番号から引く静的データで、保存する状態は無い。版は4-7①の6）", MorningSave.VERSION == 6)

	News.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()


## その日のニュースで must_info の印のある項目の見出しが、WAKEの列に全部含まれるか。
func _must_info_headlines_present(day: int, events: Array) -> bool:
	var texts := _texts(events)
	for item in News.day_entry(day)["news"]:
		if not (item["must_info"] as Array).is_empty() and not texts.has("ニュース：" + str(item["headline"])):
			return false
	return true
