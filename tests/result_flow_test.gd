extends RefCounted
## 結果画面（フェーズ4-2コミット②・DESIGN.md 10.6）の検証。
## 対象：最終日の流れ（NEXT_DAY→RESULT。reset_for_new_gameは呼ばれない）、RESULTでの
## [次のPhase]、結果画面の3ブロックと選択肢（もう一度／最後の朝から／新しい周）の状態
## （日数・現金・day_records・morning_snapshots）、retry_from_morning(day)が後の日の
## 朝の記録を捨てること、Day1の記録が無い周で[もう一度]が使えないこと。
##
## 7日分は、各日のWAKEを_set_runner_for_phaseで実際に通して朝を記録し、日ごとの記録は
## record_dayで足す（営業そのものはここでは検証しない。最終日のNEXT_DAYだけ実際のadvance_phase）。

# 成績の数値を出してはいけない語（物語の欄・DESIGN.md 10.6）。
const STORY_FORBIDDEN := ["GOOD", "GREAT", "OK", "BAD", "率", "杯", "現金", "¥", "廃棄", "未提供", "%"]


func _setup(t: SceneTree, money: int, day: int = 1):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（Day1の朝が記録される）
	return panel


## いまの朝（WAKE済み）から最終日のRESULTまで進める。各日のWAKEを通して朝を記録し
## （所持金は1000+日番号にそろえる＝朝の辞書の値を手計算できる）、最終日以外の日の
## 記録を足し、最後だけ実際のadvance_phase（day_endingが最終日の記録を足す）。
func _play_to_result(panel, start_day: int) -> void:
	for d in range(start_day, GameState.FINAL_DAY + 1):
		if d > start_day:
			GameState.day_count = d
			GameState.money = 1000 + d
			panel.session.set_runner_for_phase(GameState.Phase.WAKE)
		if d < GameState.FINAL_DAY:
			GameState.record_day({ "day": d, "served_cups": d, "planned_cups": d,
				"judged_planned_cups": d, "quality_counts": { "GOOD": d },
				"regular_visits": ["granny"], "closing_money": 1000 + d,
				"opening_reputation": 30 + d, "closing_reputation": 31 + d })
	GameState.phase = GameState.Phase.NEXT_DAY
	panel.session.flow.advance_phase()


func _keys(d: Dictionary) -> Array:
	var ks := d.keys()
	ks.sort()
	return ks


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var daily: int = GameState.DAILY_OPERATING_COST

	# --- 1. 最終日の流れ：NEXT_DAYの先でRESULTに入る。reset_for_new_gameは呼ばれない ---
	var panel = _setup(t, 600, 1)
	var fired := { "ending": 0, "restarted": 0 }
	panel.session.flow.day_ending.connect(func(): fired["ending"] += 1)
	panel.session.flow.game_restarted.connect(func(): fired["restarted"] += 1)
	GameState.mark_favorite_known("granny")
	var day1_env: Dictionary = GameState.morning_of(1)
	c.check("（前提）Day1の朝が記録されている", not day1_env.is_empty())
	_play_to_result(panel, 1)
	c.check("最終日のNEXT_DAYの先はRESULT", GameState.phase == GameState.Phase.RESULT)
	c.check("日数は最終日のまま（進まない）", GameState.day_count == GameState.FINAL_DAY)
	c.check("day_endingは最終日も発火する（1回）", fired["ending"] == 1)
	c.check("game_restartedは発火しない", fired["restarted"] == 0)
	c.check("最終日の記録がday_recordsに入る（7日分）",
		GameState.day_records.size() == GameState.FINAL_DAY
			and int(GameState.day_records[GameState.FINAL_DAY - 1]["day"]) == GameState.FINAL_DAY)
	c.check("reset_for_new_gameは呼ばれていない（朝の記録が全日分残る）",
		_keys(GameState.morning_snapshots) == [1, 2, 3, 4, 5, 6, 7], str(_keys(GameState.morning_snapshots)))
	var phase_before := GameState.phase
	panel.session.flow.advance_phase()
	panel._btn_next_phase.pressed.emit()
	c.check("RESULTでは[次のPhase]が効かない（フェーズも日数も変わらない）",
		GameState.phase == phase_before and GameState.day_count == GameState.FINAL_DAY)

	# --- 2. 結果画面の3ブロック ---
	var events: Array = panel.session.flow.runner.events
	c.check("結果画面のイベントはTEXT3本（成績・目標・物語）",
		events.size() == 3 and events.all(func(e): return str(e["type"]) == "TEXT"), str(events.size()))
	var report := str(events[0]["text"])
	var goals_text := str(events[1]["text"])
	var story := str(events[2]["text"])
	c.check("1枚目は店の成績（現金・GOOD以上率・常連GREAT・未提供・廃棄）",
		report.contains("店の成績") and report.contains("GOOD以上率") and report.contains("常連GREAT")
			and report.contains("未提供") and report.contains("廃棄"), report)
	c.check("2枚目は目標（5項目。未達でも続きのプレイは失われない旨）",
		goals_text.contains("目標") and goals_text.contains("完走") and goals_text.contains("標準")
			and goals_text.contains("挑戦") and goals_text.contains("料理") and goals_text.contains("常連")
			and goals_text.contains("失われない"), goals_text)
	c.check("3枚目は物語の欄（街で起きたこと／客との間に残ったこと）",
		story.contains("街で起きたこと") and story.contains("客との間に残ったこと"), story)
	var hits := STORY_FORBIDDEN.filter(func(w): return story.contains(w))
	c.check("物語の欄には成績の数値・語を出さない", hits.is_empty(), "%s / %s" % [str(hits), story])
	c.check("物語の欄に、わかっている事実（好物を知った客・来た常連）は表示名で出る（idは出ない）",
		story.contains("老婆") and not story.contains("granny"), story)
	var summary := Result.summarize(GameState.day_records, GameState.ledger, GameState.money)
	c.check("成績ブロックはResult.summarize()の整形と一致する", report == Result.format_report(summary))

	# --- 3. 選択肢の表示・有効無効 ---
	c.check("RESULTでは選択肢の行が見える", panel._result_row.visible)
	c.check("[もう一度][最後の朝][新しい周]は押せる・[終わる]は押せない",
		not panel._btn_run_again.disabled and not panel._btn_last_morning.disabled
			and not panel._btn_new_run.disabled and panel._btn_end.disabled)
	c.check("[もう一度]の文言に『Day1の客・需要のみ同じ。2日目以降は評判次第で変わる』",
		panel._btn_run_again.text.contains("Day1の客・需要のみ同じ")
			and panel._btn_run_again.text.contains("2日目以降は評判次第で変わる"), panel._btn_run_again.text)
	c.check("GAME_OVER用の[同じ朝からやり直す]はRESULTでは押せない", panel._btn_retry.disabled)

	# --- 4. もう一度（Day1の朝から）：Day1の朝・累計も戻る。直後に詰んでもDay1へ戻る ---
	panel.session.run_again()
	c.check("もう一度：Day1のWAKE", GameState.day_count == 1 and GameState.phase == GameState.Phase.WAKE)
	c.check("もう一度：所持金はDay1の朝の値（600）から運営費後",
		GameState.money == 600 - daily, str(GameState.money))
	c.check("もう一度：累計（day_records）はDay1の朝の値＝空", GameState.day_records.is_empty())
	c.check("もう一度：Day1より後の朝の記録は捨てられる（Day1だけ）",
		_keys(GameState.morning_snapshots) == [1], str(_keys(GameState.morning_snapshots)))
	c.check("もう一度：Day1のDayPlanは保存したものと同一",
		GameState.today_plan["slots"] == day1_env["state"]["today_plan"]["slots"]
			and GameState.today_plan["mob_instances"] == day1_env["state"]["today_plan"]["mob_instances"])
	c.check("もう一度：選択肢の行は隠れる", not panel._result_row.visible)
	GameState.money = 0
	panel.session.game_over("テスト用ゲームオーバー")
	c.check("もう一度の直後に詰んでも、再挑戦はDay1の朝へ戻る（最後の朝へ飛ばない）",
		panel.session.retry_from_morning() and GameState.day_count == 1
			and GameState.money == 600 - daily
			and _keys(GameState.morning_snapshots) == [1])

	# --- 5. もう一度を続けて2回：同じ状態へ戻る ---
	_play_to_result(panel, 1)
	c.check("（前提）やり直した周も最終日のRESULTへ入る",
		GameState.phase == GameState.Phase.RESULT and GameState.day_records.size() == 7)
	panel.session.run_again()
	c.check("2回目のもう一度：Day1・同じ所持金・累計空・記録はDay1だけ",
		GameState.day_count == 1 and GameState.money == 600 - daily
			and GameState.day_records.is_empty() and _keys(GameState.morning_snapshots) == [1])
	c.check("2回目のもう一度：DayPlanも同じ",
		GameState.today_plan["slots"] == day1_env["state"]["today_plan"]["slots"])

	# --- 6. 最後の朝からやり直す → その後にもう一度 ---
	_play_to_result(panel, 1)
	var day7_env: Dictionary = GameState.morning_of(7)
	panel.session.last_morning()
	c.check("最後の朝：最終日のWAKE・所持金は最終日の朝の値(1007)から運営費後",
		GameState.day_count == 7 and GameState.phase == GameState.Phase.WAKE
			and GameState.money == 1007 - daily, str(GameState.money))
	c.check("最後の朝：累計は最終日の朝の値（6日分）",
		GameState.day_records.size() == 6 and int(GameState.day_records[5]["day"]) == 6)
	c.check("最後の朝：朝の記録は全日分のまま（Day1の記録が残る）",
		_keys(GameState.morning_snapshots) == [1, 2, 3, 4, 5, 6, 7])
	c.check("最後の朝：最終日のDayPlanは保存したものと同一",
		GameState.today_plan["slots"] == day7_env["state"]["today_plan"]["slots"])
	_play_to_result(panel, 7)
	c.check("（前提）最後の朝からやり直して最終日を終えるとまたRESULT（7日分・二重に数えない）",
		GameState.phase == GameState.Phase.RESULT and GameState.day_records.size() == 7)
	panel.session.run_again()
	c.check("最後の朝の後のもう一度：Day1・累計空・記録はDay1だけ",
		GameState.day_count == 1 and GameState.money == 600 - daily
			and GameState.day_records.is_empty() and _keys(GameState.morning_snapshots) == [1])

	# --- 7. retry_from_morning(day)：指定した日より後の朝の記録を捨てる ---
	_play_to_result(panel, 1)
	var ok3: bool = panel.session.retry_from_morning(3)
	c.check("retry_from_morning(3)でDay3の朝へ戻れる", ok3 and GameState.day_count == 3)
	c.check("Day3へ戻すと、Day4〜7の朝の記録は捨てられる（1〜3だけ）",
		_keys(GameState.morning_snapshots) == [1, 2, 3], str(_keys(GameState.morning_snapshots)))
	c.check("Day3の朝の累計は2日分", GameState.day_records.size() == 2)
	GameState.money = 0
	panel.session.game_over("テスト用ゲームオーバー")
	c.check("Day3へ戻した直後に詰んでも、再挑戦はDay3の朝（Day7へ飛ばない）",
		panel.session.retry_from_morning() and GameState.day_count == 3)
	c.check("存在しない日（9）を指定すると何もしない",
		not panel.session.retry_from_morning(9) and GameState.day_count == 3)

	# --- 8. 新しい周：全て初期化。その後の再挑戦も新しい周の朝へ戻る ---
	_play_to_result(panel, 3)
	var restarted_before: int = fired["restarted"]
	GameState.reputation = 77
	panel.session.new_run()
	c.check("新しい周：Day1のWAKE・所持金は初期現金から運営費後・評判は初期値",
		GameState.day_count == 1 and GameState.phase == GameState.Phase.WAKE
			and GameState.money == GameState.INITIAL_MONEY - daily
			and GameState.reputation == GameState.INITIAL_REPUTATION, str(GameState.money))
	c.check("新しい周：累計空・好物の記録も初期化・朝の記録は新しいDay1の朝だけ",
		GameState.day_records.is_empty() and GameState.known_favorite_ids().is_empty()
			and _keys(GameState.morning_snapshots) == [1])
	c.check("新しい周：帳簿は新しい周のWAKE（運営費・確保）だけ",
		GameState.ledger.size() == 2
			and GameState.ledger.all(func(r): return str(r["category"]) in ["daily_cost", "reserve"]),
		str(GameState.ledger))
	c.check("新しい周：game_restartedが1回発火する", fired["restarted"] == restarted_before + 1)
	GameState.money = 0
	panel.session.game_over("テスト用ゲームオーバー")
	c.check("新しい周の後の再挑戦は、新しい周のDay1の朝へ戻る（前の周のDay7ではない）",
		panel.session.retry_from_morning() and GameState.day_count == 1
			and GameState.money == GameState.INITIAL_MONEY - daily
			and GameState.day_records.is_empty() and _keys(GameState.morning_snapshots) == [1])

	# --- 9. Day1の朝の記録が無い周（続きから始めた周）：[もう一度]は押せず、理由を出す ---
	_play_to_result(panel, 1)
	GameState.morning_snapshots.erase(1)
	panel._refresh()
	c.check("Day1の記録が無いと[もう一度]は押せない", panel._btn_run_again.disabled)
	c.check("理由がボタンに出る（Day1の朝の記録が無い）",
		panel._btn_run_again.text.contains("記録が無い") and panel._btn_run_again.tooltip_text != "",
		panel._btn_run_again.text)
	c.check("[最後の朝][新しい周]は押せる", not panel._btn_last_morning.disabled
		and not panel._btn_new_run.disabled)
	var day_before: int = GameState.day_count
	c.check("Day1を指定しても何もしない", not panel.session.retry_from_morning(1) and GameState.day_count == day_before)

	# --- 10. RESULT以外では選択肢の行は隠れている ---
	var panel2 = _setup(t, 600, 1)
	c.check("通常の朝では選択肢の行は隠れている", not panel2._result_row.visible)

	# --- 11. GAME_OVERの出口（先に直す②）：最後の朝・Day1の朝から・新しい周 ---
	var over = _setup(t, 600, 1)
	var over_fired := { "restarted": 0 }
	over.session.flow.game_restarted.connect(func(): over_fired["restarted"] += 1)
	GameState.money = 0
	over.session.game_over("テスト用ゲームオーバー")
	c.check("GAME_OVERでは選択肢の行が見える", over._result_row.visible)
	c.check("GAME_OVER（Day1の記録あり）：[直近の朝][Day1の朝から][新しい周]と仮の[同じ朝から]が押せる",
		not over._btn_last_morning.disabled and not over._btn_run_again.disabled
			and not over._btn_new_run.disabled and not over._btn_retry.disabled and over._btn_end.disabled)
	c.check("GAME_OVER：Day1の記録があるとき[Day1の朝から]の文面は通常のもの",
		over._btn_run_again.text.contains("Day1の客・需要のみ同じ"), over._btn_run_again.text)
	over.session.run_again()
	c.check("GAME_OVER→Day1の朝から：Day1のWAKE・運営費後の現金・GAME_OVERの理由は消える",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
			and GameState.money == GameState.INITIAL_MONEY - daily and over.session.game_over_reason == "",
		str(GameState.money))
	c.check("GAME_OVER→Day1の朝から：結果行は隠れる", not over._result_row.visible)

	# 続きから始めた周：Day1の記録が無い（Day2の朝だけ持つ）
	GameState.morning_snapshots.clear()
	GameState.day_count = 2
	GameState.money = 700
	GameState.record_morning(MorningSave.capture("昨日の一言"))
	GameState.money = 0
	over.session.game_over("テスト用ゲームオーバー")
	c.check("GAME_OVER（Day1の記録なし）：[Day1の朝から]も押せる（出口を塞がない）",
		not over._btn_run_again.disabled and not over._btn_last_morning.disabled
			and not over._btn_new_run.disabled)
	c.check("GAME_OVER（Day1の記録なし）：新しい周と同じ動作だと文面で分かる",
		over._btn_run_again.text.contains("新しい周と同じ") and over._btn_run_again.tooltip_text != "",
		over._btn_run_again.text)
	over.session.last_morning()
	c.check("GAME_OVER→直近の朝：Day2の朝へ戻る", GameState.phase == GameState.Phase.WAKE
		and GameState.day_count == 2)
	GameState.money = 0
	over.session.game_over("テスト用ゲームオーバー")
	var restarts_before: int = over_fired["restarted"]
	over.session.run_again()
	c.check("Day1の記録なしの[Day1の朝から]は新しい周になる（Day1・初期値・累計空・朝の記録は新Day1だけ）",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
			and GameState.money == GameState.INITIAL_MONEY - daily
			and GameState.reputation == GameState.INITIAL_REPUTATION
			and GameState.day_records.is_empty() and _keys(GameState.morning_snapshots) == [1]
			and over_fired["restarted"] == restarts_before + 1)

	# 朝の記録がまったく無い：[直近の朝]は押せないが、Day1の朝から・新しい周は押せる
	GameState.morning_snapshots.clear()
	GameState.money = 0
	over.session.game_over("テスト用ゲームオーバー")
	c.check("GAME_OVER（記録が空）：[直近の朝][同じ朝から]は押せず、[Day1の朝から][新しい周]は押せる",
		over._btn_last_morning.disabled and over._btn_retry.disabled
			and not over._btn_run_again.disabled and not over._btn_new_run.disabled)
	over.session.run_again()
	c.check("GAME_OVER（記録が空）→Day1の朝から：新しい周のDay1のWAKE",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
			and _keys(GameState.morning_snapshots) == [1])
	GameState.morning_snapshots.clear()
	GameState.money = 0
	over.session.game_over("テスト用ゲームオーバー")
	over.session.new_run()
	c.check("GAME_OVER（記録が空）→新しい周：新しい周のDay1のWAKE",
		GameState.phase == GameState.Phase.WAKE and GameState.day_count == 1
			and _keys(GameState.morning_snapshots) == [1])

	# スマホ中は押せない
	GameState.money = 0
	over.session.game_over("テスト用ゲームオーバー")
	over._phone_mode = true
	over._refresh()
	c.check("GAME_OVER中でもスマホ画面を開いている間は出口を押せない",
		over._btn_run_again.disabled and over._btn_last_morning.disabled and over._btn_new_run.disabled)
	over._phone_mode = false

	# RESULTの挙動は変わらない：Day1の記録が無ければ[もう一度]は押せない・文面は「使えません」
	var res = _setup(t, 600, 1)
	_play_to_result(res, 1)
	GameState.morning_snapshots.erase(1)
	res._refresh()
	c.check("RESULT：Day1の記録が無いと[もう一度]は押せず、文面は「使えません」のまま",
		res._btn_run_again.disabled and res._btn_run_again.text.contains("使えません"))
	c.check("RESULT：[最後の朝]の文面は従来のまま", res._btn_last_morning.text == "最後の朝からやり直す")

	GameState.reset_for_new_game()
	for p in [panel, panel2, over, res]:
		if is_instance_valid(p):
			p.free()
	return c.finish()
