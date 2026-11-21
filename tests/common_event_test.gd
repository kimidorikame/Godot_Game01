extends RefCounted
## 日別の共通イベント（システム整理D-③。Day6の火災＝必須情報#7。DESIGN.md 10.5.5）の検証。
## UI準備AC：6日目の衝突（d6_clash）を外し、火災の場面を明け方の始め（明け方の最初の客の前）に3件（d6_fire・d6_fire_news・d6_dawn）、
## 閉店の前（at:close）に1件（d6_close）置いた。客の抽選に依存せず、必ず届く。営業中に届かなかった分（早仕舞い・客0人）は、
## CLOSEの先頭で取り戻す。_load_current_customer が同じ客で何度呼ばれても二重に前置しない。数値（所持金・評判・在庫・鍋）は不変。
## 再挑戦・新しい周でリセット。試遊のハーネスは part が news／common_event の TEXT だけを読み飛ばす。

const DAWN_IDS := ["d6_fire", "d6_fire_news", "d6_dawn"]
const CLOSE_ID := "d6_close"
const FIRE_FIRST := "店主「……港の方か」"


func _wake_panel(t: SceneTree, day: int, reputation: int = 65):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.reputation = reputation
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（DayPlanができる）
	return panel


func _start_open(panel) -> void:
	GameState.phase = GameState.Phase.OPEN
	panel.session.set_runner_for_phase(GameState.Phase.OPEN)


## 次の客へ（_advance_open_queue_if_customer_done と同じく、進めてから読み込む）。
func _next_customer(panel) -> void:
	panel.session.open.advance_customer()
	panel.session.load_current_customer()


func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _common_texts(events: Array) -> Array:
	var out := []
	for ev in events:
		if str(ev.get("part", "")) == "common_event":
			out.append(str(ev["text"]))
	return out


## その日の共通イベント（id の並び）の画面に出る文（今の状態で開く）。
func _texts_of(ids: Array) -> Array:
	var out := []
	for id in ids:
		out.append_array(News.event_texts(News.event_by_id(6, str(id)), 6))
	return out


## 数値の写し（共通イベントの前後で変わってはいけないもの。来店記録は客が来るので除く）。
func _numbers() -> Dictionary:
	return { "money": GameState.money, "rep": GameState.reputation, "day": GameState.day_count,
		"inventory": GameState.inventory.duplicate(true), "batches": GameState.perishable_batches.duplicate(true),
		"soup": GameState.soup.duplicate(true) if GameState.soup != null else null,
		"dashi": GameState.dashi_units, "ledger": GameState.ledger.size(),
		"plan": GameState.today_plan.duplicate(true), "served": GameState.served.size() }


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	News.clear_cache()
	ScheduleData.clear_cache()
	c.check("6日目の共通イベント：衝突（d6_clash）は無く、明け方に3件・閉店の前に1件。必須情報 warehouse_fire は火災の場面（d6_fire）に付く",
		News.day_entry(6)["events"].map(func(e): return "%s@%s" % [e["id"], e["at"]]) == ["d6_fire@明け方", "d6_fire_news@明け方", "d6_dawn@明け方", "d6_close@close"]
			and News.event_by_id(6, "d6_fire")["must_info"] == ["warehouse_fire"] and News.event_by_id(6, "d6_clash").is_empty())

	# --- 1. Day6：宵の口・夜半の始めには何も前置されない ---
	var panel = _wake_panel(t, 6)
	_start_open(panel)
	var first_customer: String = str(panel.session.open.current_customer())
	var events1: Array = panel.session.flow.runner.events
	c.check("宵の口の最初の客の列は customer_events のまま（共通イベントは前置されない）",
		_common_texts(events1).is_empty() and _norm(events1) == _norm(Day1Events.customer_events(first_customer)))
	c.check("宵の口の始めでは再生済みは空", panel.session.played_events.is_empty())
	var guard := 0
	while panel.session.open.slot_index < 2 and guard < 60:
		guard += 1
		_next_customer(panel)
		if panel.session.open.slot_index < 2:
			c.check("%s の%d人目：共通イベントは前置されない" % [panel.session.open.current_slot_name(), panel.session.open.index + 1],
				_common_texts(panel.session.flow.runner.events).is_empty())

	# --- 2. 明け方の最初の客の前に、火災の場面（3件）が続けて前置される ---
	c.check("（前提）夜半の客を進み終えて明け方に入った", panel.session.open.slot_index == 2 and panel.session.open.index == 0
		and panel.session.open.current_slot_name() == "明け方")
	var dawn_texts := _common_texts(panel.session.flow.runner.events)
	c.check("明け方の最初の客の前に、火災 → 速報と仕入れの連絡 → 明け方の始め の行が前置される",
		dawn_texts == _texts_of(DAWN_IDS) and dawn_texts[0] == FIRE_FIRST and str(panel.session.flow.runner.events[0]["event_id"]) == "d6_fire", str(dawn_texts))
	c.check("再生済みは 火災 → 速報 → 明け方の始め の順", panel.session.played_events == DAWN_IDS)
	var snapshot2 = _norm(panel.session.flow.runner.events)
	panel.session.load_current_customer()
	c.check("明け方の最初の客を組み直しても、火災は二重にならない", _norm(panel.session.flow.runner.events) == snapshot2
		and panel.session.played_events == DAWN_IDS)
	if panel.session.open.current_slot_customers().size() > 1:
		_next_customer(panel)
		c.check("明け方の2人目：共通イベントは前置されない", _common_texts(panel.session.flow.runner.events).is_empty())

	# --- 3. 閉店：閉店の前の場面（d6_close）だけが出る ---
	panel.session.flow.force_phase(GameState.Phase.CLOSE)
	var close_ev: Array = panel.session.flow.runner.events
	c.check("閉店：閉店の前の場面（d6_close）→ 閉店の語り。明け方の場面は二重に出ない",
		_common_texts(close_ev) == _texts_of([CLOSE_ID]) and _norm(close_ev.slice(_texts_of([CLOSE_ID]).size())) == _norm(Day1Events.close_events())
			and panel.session.played_events == DAWN_IDS + [CLOSE_ID], str(_common_texts(close_ev)))
	panel.free()

	# --- 4. 早仕舞い・客が来ない日：CLOSEの先頭で、未再生の共通イベントを時系列で取り戻す（鍋が尽きた晩も同じ） ---
	for case in [["通常の評判", 65], ["低い評判（モブが少ない）", -40]]:
		var p5 = _wake_panel(t, 6, int(case[1]))
		# 営業を一度も始めずに閉店（客0人＝早仕舞いの極端な例）
		p5.session.flow.force_phase(GameState.Phase.CLOSE)
		var ev5: Array = p5.session.flow.runner.events
		var want := _texts_of(DAWN_IDS + [CLOSE_ID])
		c.check("%s・客0人：CLOSEの先頭に 火災 → 速報 → 明け方の始め → 閉店の前 が届く（必須情報#7）" % case[0],
			_common_texts(ev5) == want and str(ev5[0]["part"]) == "common_event", str(_common_texts(ev5)))
		c.check("%s：その後ろに閉店の語りが続く" % case[0], _norm(ev5.slice(want.size())) == _norm(Day1Events.close_events()))
		c.check("%s：再生済みに4件入る" % case[0], p5.session.played_events == DAWN_IDS + [CLOSE_ID])
		p5.free()
	var p5b = _wake_panel(t, 6)
	_start_open(p5b)
	GameState.soup = null   # 鍋が尽きた晩（宵の口のうちに閉める）
	p5b.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("宵の口で早仕舞い（鍋が尽きた晩）：CLOSEで火災の場面から閉店の前まで、1回ずつ取り戻す",
		_common_texts(p5b.session.flow.runner.events) == _texts_of(DAWN_IDS + [CLOSE_ID]))
	p5b.free()
	# 早仕舞いの理由・未提供版の退店の後ろに共通イベントが続く（順序：理由 → 未提供版 → 共通イベント → 閉店の語り）
	var p5c = _wake_panel(t, 6)
	p5c.session.closed_early_reason = "（今日はここで店じまいにする。）"
	p5c.session.pending_close_lines = [{ "type": "GREET", "customer": "x", "text": "未提供の退店", "part": "reaction" }]
	p5c.session.flow.force_phase(GameState.Phase.CLOSE)
	var texts5c := []
	for ev in p5c.session.flow.runner.events:
		texts5c.append(str(ev.get("text", "")))
	var n5c := _texts_of(DAWN_IDS + [CLOSE_ID]).size()
	c.check("順序：理由 → 未提供版の退店 → 共通イベント → 閉店の語り",
		texts5c.slice(0, 3) == ["（今日はここで店じまいにする。）", "未提供の退店", FIRE_FIRST]
			and texts5c[2 + n5c] == "看板の灯を落とす。", str(texts5c))
	p5c.free()

	# --- 5. 数値は変えない（所持金・評判・在庫・鍋・需要・客の構成・帳簿） ---
	var p6 = _wake_panel(t, 6)
	GameState.add_inventory("tofu", 3)
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	p6.session.pay_operating_cost()   # 運営費（水と炭）は開店の前に引く（市場を出るとき）。数値の比較はそのあとから
	var numbers_before := _numbers()
	p6.session.set_runner_for_phase(GameState.Phase.OPEN)
	p6.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("CLOSEで火災の場面を取り戻しても数値は不変（所持金・評判・在庫・鍋・DayPlan・帳簿）", _numbers() == numbers_before)
	p6.free()

	# --- 6. Day6以外は何も前置されず、従来と同一（中身AE：Day7 は閉店の前の場面〔d7_close〕だけ。営業中の共通イベントは無い） ---
	for day in [1, 2, 3, 4, 5, 7]:
		var p7 = _wake_panel(t, day)
		_start_open(p7)
		var customer7: String = str(p7.session.open.current_customer())
		c.check("Day%d：最初の客の列は customer_events のまま（共通イベントなし）" % day,
			_norm(p7.session.flow.runner.events) == _norm(Day1Events.customer_events(customer7)) and p7.session.played_events.is_empty())
		p7.session.flow.force_phase(GameState.Phase.CLOSE)
		if day == 7:
			var close7: Array = p7.session.flow.runner.events
			c.check("Day7：CLOSEは閉店の前の場面（店主の3行。中身AE）のあと、従来の閉店の列",
				_common_texts(close7) == ["店主「……箱は、またここだな」", "店主「明日の道は、明日見るか」", "店主「よし。今日はここまで」"]
					and _norm(close7.slice(3)) == _norm(Day1Events.close_events()) and p7.session.played_events == ["d7_close"], str(_common_texts(close7)))
		else:
			c.check("Day%d：CLOSEは従来の閉店の列" % day, _norm(p7.session.flow.runner.events) == _norm(Day1Events.close_events()))
		p7.free()

	# --- 7. 再挑戦（朝へ戻す）：再生済みがリセットされ、最初から再生し直す ---
	var p8 = _wake_panel(t, 6)
	p8.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("（前提）火災の場面を再生した", p8.session.played_events == DAWN_IDS + [CLOSE_ID])
	c.check("朝（Day6）へ戻せる", p8.session.retry_from_morning(6) and GameState.day_count == 6)
	c.check("再挑戦：再生済みと前置の記録がリセットされる", p8.session.played_events.is_empty() and p8.session.slot_event_ids.is_empty())
	p8.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("再挑戦後も、火災の場面がもう一度出る（1回だけ）", _common_texts(p8.session.flow.runner.events) == _texts_of(DAWN_IDS + [CLOSE_ID])
		and p8.session.played_events == DAWN_IDS + [CLOSE_ID])
	p8.session.new_run()
	c.check("新しい周：再生済みはリセット（Day1）", p8.session.played_events.is_empty() and GameState.day_count == 1)
	p8.free()

	# --- 8. ニュースタブ：過ぎた日の出来事は載り、今日の分は再生した分だけ載る ---
	var p9 = _wake_panel(t, 6)
	p9._phone_tab = "news"
	c.check("Day6の朝（まだ再生していない）：出来事は載らない", not p9._format_phone().contains("出来事："))
	p9.session.flow.force_phase(GameState.Phase.CLOSE)
	p9._phone_tab = "news"
	var tab9: String = p9._format_phone()
	c.check("火災の場面を再生した後：出来事が載る（条件付きの行・show_dm・show_news は画面に出る文で）",
		tab9.contains("港の方か") and not tab9.contains("show_dm") and not tab9.contains("mob_served"))
	p9.free()
	GameState.reset_for_new_game()
	GameState.day_count = 7
	c.check("Day7のタブには、過ぎたDay6の出来事（火災）が載る", News.tab_text(7).contains("港の方か") and not News.tab_text(7).contains("show_"))

	# --- 9. at が wake／close の共通イベント（データを差し替えて確認） ---
	var custom := News.data().duplicate(true)
	custom["days"]["2"]["events"] = [ { "id": "w", "at": "wake", "lines": ["朝の出来事"], "must_info": [], "provisional": true } ]
	custom["days"]["3"]["events"] = [ { "id": "c", "at": "close", "lines": ["閉店後の出来事"], "must_info": [], "provisional": true } ]
	News._cache = custom
	News._loaded_id = Rules.news()
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var wake_texts := []
	for ev in Day1Events.wake_events():
		wake_texts.append(str(ev.get("text", "")))
	var news_count := News.morning_events(2).size()
	c.check("at:wake の共通イベントは朝のニュースの後に出る",
		wake_texts[2 + news_count] == "朝の出来事" and wake_texts[3 + news_count].begins_with("炭代¥40・水代¥35は"))
	var p10 = _wake_panel(t, 2)
	c.check("朝に出した共通イベントは再生済みになる", p10.session.played_events == ["w"])
	p10.free()
	var p10b = _wake_panel(t, 3)
	_start_open(p10b)
	p10b.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("at:close の共通イベントは閉店の語りの前（CLOSEの先頭）に出る",
		_common_texts(p10b.session.flow.runner.events) == ["閉店後の出来事"] and str(p10b.session.flow.runner.events[0]["part"]) == "common_event")
	p10b.free()
	News.clear_cache()

	# --- 10. 試遊のハーネス：読み飛ばすのは part が news または common_event の TEXT だけ ---
	var harness = load("res://planning/playtest_2026_10_11/playthroughs.gd").new()
	c.check("part:news の TEXT は読み飛ばす", harness.is_display_only({ "type": "TEXT", "text": "x", "part": "news" }))
	c.check("part:common_event の TEXT は読み飛ばす",
		harness.is_display_only({ "type": "TEXT", "text": "x", "part": "common_event", "event_id": "e" }))
	c.check("part の無い TEXT は読み飛ばさない（操作として数える）", not harness.is_display_only({ "type": "TEXT", "text": "x" }))
	c.check("他の part の TEXT は読み飛ばさない", not harness.is_display_only({ "type": "TEXT", "text": "x", "part": "body" }))
	c.check("TEXT 以外（GREET・REACT・ADJUST）は part が news でも読み飛ばさない",
		not harness.is_display_only({ "type": "GREET", "text": "x", "part": "news" })
			and not harness.is_display_only({ "type": "ADJUST", "part": "common_event" }))
	c.check("null・辞書でないものは読み飛ばさない", not harness.is_display_only(null) and not harness.is_display_only("x"))

	News.clear_cache()
	GameState.reset_for_new_game()
	return c.finish()
