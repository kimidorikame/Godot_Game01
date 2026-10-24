extends RefCounted
## 日別の共通イベント（システム整理D-③。Day6の衝突と火災＝必須情報#7。DESIGN.md 10.5.5）の検証。
## 客の抽選に依存せず、必ず届く：衝突は宵の口の始め、火災は夜半の始めに、その時間帯の最初の客の前へ
## TEXTで前置する。営業中に届かなかった分（早仕舞い・客0人）は、CLOSEの先頭で取り戻す。
## _load_current_customer が同じ客で何度呼ばれても二重に前置しない。数値（所持金・評判・在庫・鍋）は不変。
## 再挑戦・新しい周でリセット。試遊のハーネスは part が news／common_event の TEXT だけを読み飛ばす。

const CLASH := "（遠くで怒号が上がった。ピケの列と会社側がぶつかったらしい。）"
const FIRE1 := "（遠方の空が赤い。サイレンが重なって聞こえる。）"
const FIRE2 := "（倉庫が燃えている、と誰かが言った。）"


func _wake_panel(t: SceneTree, day: int, reputation: int = 65):
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.reputation = reputation
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（DayPlanができる）
	return panel


func _start_open(panel) -> void:
	GameState.phase = GameState.Phase.OPEN
	panel._set_runner_for_phase(GameState.Phase.OPEN)


## 次の客へ（_advance_open_queue_if_customer_done と同じく、進めてから読み込む）。
func _next_customer(panel) -> void:
	panel.session.open.advance_customer()
	panel._load_current_customer()


func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _common_texts(events: Array) -> Array:
	var out := []
	for ev in events:
		if str(ev.get("part", "")) == "common_event":
			out.append(str(ev["text"]))
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

	# --- 1. Day6：営業の始め（宵の口の最初の客）の前に衝突が前置される ---
	var panel = _wake_panel(t, 6)
	_start_open(panel)
	var first_customer: String = str(panel.session.open.current_customer())
	var events1: Array = panel.session.flow.runner.events
	c.check("宵の口の最初の客の列の先頭に衝突のTEXT（part:common_event・効果の無いTEXT）",
		_common_texts(events1) == [CLASH] and str(events1[0]["type"]) == "TEXT"
			and str(events1[0]["part"]) == "common_event" and str(events1[0]["event_id"]) == "d6_clash")
	c.check("その後ろは従来どおりの客の列（customer_events）",
		_norm(events1.slice(1)) == _norm(Day1Events.customer_events(first_customer)))
	c.check("再生済みに衝突が入る", panel.session.played_events == ["d6_clash"])

	# --- 2. 同じ客で _load_current_customer を何度呼んでも、二重に前置しない（同じ列を組み直す） ---
	var snapshot1 = _norm(panel.session.flow.runner.events)
	panel._load_current_customer()
	panel._load_current_customer()
	c.check("同じ客で3回呼んでも、列は同じ（衝突は1回だけ）",
		_norm(panel.session.flow.runner.events) == snapshot1 and _common_texts(panel.session.flow.runner.events) == [CLASH])
	c.check("再生済みの記録は1件のまま（二重に数えない）", panel.session.played_events == ["d6_clash"])

	# --- 3. 宵の口の2人目以降には前置されない。夜半の最初の客の前に火災が前置される ---
	var in_slot0: int = panel.session.open.current_slot_customers().size()
	var guard := 0
	while panel.session.open.slot_index == 0 and guard < 30:
		guard += 1
		_next_customer(panel)
		if panel.session.open.slot_index == 0:
			c.check("宵の口の%d人目：共通イベントは前置されない" % (panel.session.open.index + 1),
				_common_texts(panel.session.flow.runner.events).is_empty())
	c.check("（前提）宵の口の客を進み終えて夜半に入った", panel.session.open.slot_index == 1 and panel.session.open.index == 0 and in_slot0 >= 1)
	c.check("夜半の最初の客の前に火災（2行・ひとつの出来事）が前置される",
		_common_texts(panel.session.flow.runner.events) == [FIRE1, FIRE2], str(_common_texts(panel.session.flow.runner.events)))
	c.check("再生済みは 衝突 → 火災 の順", panel.session.played_events == ["d6_clash", "d6_fire"])
	var snapshot2 = _norm(panel.session.flow.runner.events)
	panel._load_current_customer()
	c.check("夜半の最初の客を組み直しても、火災は二重にならない", _norm(panel.session.flow.runner.events) == snapshot2
		and panel.session.played_events == ["d6_clash", "d6_fire"])
	guard = 0
	while panel.session.open.slot_index == 1 and guard < 30:
		guard += 1
		_next_customer(panel)
	c.check("明け方：共通イベントは前置されない（Day6の分はもう再生済み）",
		panel.session.open.slot_index == 2 and _common_texts(panel.session.flow.runner.events).is_empty())

	# --- 4. 全部届いた日のCLOSEは従来どおり（取り戻しなし） ---
	var played_before: Array = panel.session.played_events.duplicate()
	panel.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("全部再生済みの日のCLOSEは従来の閉店の列と同一（二重に出ない）",
		_norm(panel.session.flow.runner.events) == _norm(Day1Events.close_events()) and panel.session.played_events == played_before)
	panel.free()

	# --- 5. 早仕舞い・客が来ない日：CLOSEの先頭で、未再生の共通イベントを時系列で取り戻す ---
	for case in [["通常の評判", 65], ["低い評判（モブが少ない）", -40]]:
		var p5 = _wake_panel(t, 6, int(case[1]))
		# 営業を一度も始めずに閉店（客0人＝早仕舞いの極端な例）
		p5.session.flow.force_phase(GameState.Phase.CLOSE)
		var ev5: Array = p5.session.flow.runner.events
		c.check("%s・客0人：CLOSEの先頭に 衝突 → 火災 が届く（必須情報#7）" % case[0],
			_common_texts(ev5) == [CLASH, FIRE1, FIRE2] and str(ev5[0]["part"]) == "common_event",
			str(_common_texts(ev5)))
		c.check("%s：その後ろに閉店の語りが続く" % case[0],
			_norm(ev5.slice(3)) == _norm(Day1Events.close_events()))
		c.check("%s：再生済みに両方入る" % case[0], p5.session.played_events == ["d6_clash", "d6_fire"])
		p5.free()
	var p5b = _wake_panel(t, 6)
	_start_open(p5b)   # 衝突は宵の口の始めで再生済み
	p5b.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("宵の口で早仕舞い：CLOSEで取り戻すのは火災だけ（衝突は二重にならない）",
		_common_texts(p5b.session.flow.runner.events) == [FIRE1, FIRE2])
	p5b.free()
	# 早仕舞いの理由・未提供版の退店の後ろに共通イベントが続く（順序：理由 → 未提供版 → 共通イベント → 閉店の語り）
	var p5c = _wake_panel(t, 6)
	p5c.session.closed_early_reason = "（今日はここで店じまいにする。）"
	p5c.session.pending_close_lines = [{ "type": "GREET", "customer": "x", "text": "未提供の退店", "part": "reaction" }]
	p5c.session.flow.force_phase(GameState.Phase.CLOSE)
	var texts5c := []
	for ev in p5c.session.flow.runner.events:
		texts5c.append(str(ev.get("text", "")))
	c.check("順序：理由 → 未提供版の退店 → 共通イベント → 閉店の語り",
		texts5c.slice(0, 5) == ["（今日はここで店じまいにする。）", "未提供の退店", CLASH, FIRE1, FIRE2]
			and texts5c[5] == "看板の灯を落とす。", str(texts5c))
	p5c.free()

	# --- 6. 数値は変えない（所持金・評判・在庫・鍋・需要・客の構成・帳簿） ---
	var p6 = _wake_panel(t, 6)
	GameState.add_inventory("tofu", 3)
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	var numbers_before := _numbers()
	p6._set_runner_for_phase(GameState.Phase.OPEN)
	c.check("衝突を前置しても数値は不変", _numbers() == numbers_before)
	p6.session.flow.force_phase(GameState.Phase.CLOSE)
	c.check("CLOSEで火災を取り戻しても数値は不変（所持金・評判・在庫・鍋・DayPlan・帳簿）",
		_numbers() == numbers_before)
	p6.free()

	# --- 7. Day6以外は何も前置されず、従来と同一 ---
	for day in [1, 2, 3, 4, 5, 7]:
		var p7 = _wake_panel(t, day)
		_start_open(p7)
		var customer7: String = str(p7.session.open.current_customer())
		c.check("Day%d：最初の客の列は customer_events のまま（共通イベントなし）" % day,
			_norm(p7.session.flow.runner.events) == _norm(Day1Events.customer_events(customer7)) and p7.session.played_events.is_empty())
		p7.session.flow.force_phase(GameState.Phase.CLOSE)
		c.check("Day%d：CLOSEは従来の閉店の列" % day, _norm(p7.session.flow.runner.events) == _norm(Day1Events.close_events()))
		p7.free()

	# --- 8. 再挑戦（朝へ戻す）：再生済みがリセットされ、最初から再生し直す ---
	var p8 = _wake_panel(t, 6)
	_start_open(p8)
	c.check("（前提）衝突を再生した", p8.session.played_events == ["d6_clash"])
	c.check("朝（Day6）へ戻せる", p8.retry_from_morning(6) and GameState.day_count == 6)
	c.check("再挑戦：再生済みと前置の記録がリセットされる", p8.session.played_events.is_empty() and p8.session.slot_event_ids.is_empty())
	_start_open(p8)
	c.check("再挑戦後の営業でも、衝突がもう一度前置される（1回だけ）", _common_texts(p8.session.flow.runner.events) == [CLASH]
		and p8.session.played_events == ["d6_clash"])
	p8._on_new_run_pressed()
	c.check("新しい周：再生済みはリセット（Day1）", p8.session.played_events.is_empty() and GameState.day_count == 1)
	p8.free()

	# --- 9. ニュースタブ：過ぎた日の出来事は載り、今日の分は再生した分だけ載る ---
	var p9 = _wake_panel(t, 6)
	p9._phone_tab = "news"
	c.check("Day6の朝（まだ再生していない）：出来事は載らない", not p9._format_phone().contains("出来事："))
	_start_open(p9)
	p9._phone_tab = "news"
	var tab9: String = p9._format_phone()
	c.check("衝突を再生した後：衝突は載り、火災はまだ載らない", tab9.contains("ぶつかったらしい") and not tab9.contains("倉庫が燃えている"))
	p9.free()
	GameState.reset_for_new_game()
	GameState.day_count = 7
	c.check("Day7のタブには、過ぎたDay6の出来事（衝突・火災）が載る",
		News.tab_text(7).contains("ぶつかったらしい") and News.tab_text(7).contains("倉庫が燃えている"))

	# --- 10. at が wake／close の共通イベント（データを差し替えて確認） ---
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
		wake_texts[2 + news_count] == "朝の出来事" and wake_texts[3 + news_count].begins_with("共同水道"))
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

	# --- 11. 試遊のハーネス：読み飛ばすのは part が news または common_event の TEXT だけ ---
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
