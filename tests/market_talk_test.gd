extends RefCounted
## 昼の市場の会話（場面データの market_talk。システム整理A・E 3.1）の検証。
## 以前は PREP の市場の前に day_count == 2 のときだけ新人警官の1行を直書きで差していた。
## 今は「今日来る常連の場面（DayPlanの枠、無ければ日程の枠）」が持つ market_talk を、枠の順に
## 差す。実データの出力は従来と同一（tests/fixtures/prep_events_system_a.json＝直書きの実装で記録した
## Day1〜8の prep_after_tier_events）。市場の解禁（enabled）とは無関係に会話は出る。

const FIXTURE_PATH := "res://tests/fixtures/prep_events_system_a.json"
const OFFICER_LINE := "警官（市場・注文: 酸っぱい・歯ごたえ）"


## JSONを通した形（整数が小数になる差を避けて比べるため）にそろえる。
func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _market_talks(events: Array) -> Array:
	# MARKETより前にあるGREET（＝市場の会話）の [customer, text]
	var talks := []
	for ev in events:
		if str(ev.get("type", "")) == "MARKET":
			break
		if str(ev.get("type", "")) == "GREET":
			talks.append([str(ev["customer"]), str(ev["text"])])
	return talks


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.episodes_dir = "res://data/episodes/"
	ScheduleData.clear_cache()

	# --- 1. 実データ：Day1〜8のprep_after_tier_eventsが、直書きの実装の記録と一致 ---
	var recorded = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	c.check("記録ファイルが読める（8日×2）", recorded is Dictionary and (recorded as Dictionary).size() == 16)
	for d in range(1, 9):
		for scraps in [false, true]:
			GameState.reset_for_new_game()
			GameState.day_count = d
			var now = _norm(Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[1], scraps))
			var key := "%d:%s" % [d, "scraps" if scraps else "normal"]
			c.check("Day%d（%s）：直書きの実装の記録と同一" % [d, "端材屋" if scraps else "通常"], now == recorded[key],
				"%d vs %d events" % [(now as Array).size(), (recorded[key] as Array).size()])

	# --- 2. 新人警官の会話はDay2にだけ出る（日程の枠＝DayPlanが無い経路） ---
	for d in range(1, 9):
		GameState.reset_for_new_game()
		GameState.day_count = d
		var talks := _market_talks(Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[1], false))
		if d == 2:
			c.check("Day2：市場の前に新人警官の1行だけが出る", talks == [["officer", OFFICER_LINE]], str(talks))
		else:
			c.check("Day%d：市場の会話は出ない" % d, talks.is_empty(), str(talks))

	# --- 3. DayPlanがあるとき：今日の枠の場面から引く（Day2の実際のWAKE） ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()がWAKEを組む（今日のDayPlanができる）
	c.check("（前提）今日のDayPlanがあり、officerの枠はofficer_01",
		int(GameState.today_plan.get("day", -1)) == 2 and Day1Events.episode_id_of("officer") == "officer_01")
	var plan_events := Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[1], false)
	c.check("DayPlanがあるDay2も、直書きの記録と同一（同じ位置に同じ形）",
		_norm(plan_events) == recorded["2:normal"])
	c.check("market_talk_events()は状態を書き換えない（何度呼んでも同じ）",
		_norm(Day1Events.market_talk_events()) == _norm(Day1Events.market_talk_events()))

	# --- 4. 市場の解禁とは無関係：Day1（解禁前）でもmarket_talkを持つ場面があれば出る ---
	# 場面データを差し替えて（キャッシュへ注入）、日程の枠にある場面にmarket_talkを持たせる。
	GameState.reset_for_new_game()
	GameState.day_count = 1
	ScheduleData._episode_cache["delivery_man/delivery_man_01"] = {
		"id": "delivery_man_01", "customer": "delivery_man", "greet": ["x"], "reactions": {}, "servings": 1,
		"market_talk": ["配達員（市場A）", "配達員（市場B）"] }
	ScheduleData._episode_cache["thug/thug_01"] = {
		"id": "thug_01", "customer": "thug", "greet": ["x"], "reactions": {}, "servings": 1,
		"market_talk": ["チンピラ（市場）"] }
	var multi := _market_talks(Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[1], false))
	c.check("同じ日に複数の場面が持つときは、枠の順に全部出す（Day1：配達員→チンピラ）",
		multi == [["delivery_man", "配達員（市場A）"], ["delivery_man", "配達員（市場B）"], ["thug", "チンピラ（市場）"]],
		str(multi))
	c.check("市場の解禁前（Day1。店は押せない）でも会話は出る",
		not bool(Day1Events._market_options(false)[0]["enabled"]) and not multi.is_empty())
	ScheduleData.clear_cache()

	# --- 5. market_talkを持たない場面・不正な形では出ない ---
	GameState.reset_for_new_game()
	GameState.day_count = 2
	ScheduleData._episode_cache["officer/officer_01"] = {
		"id": "officer_01", "customer": "officer", "greet": ["x"], "reactions": {}, "servings": 1 }
	c.check("officer_01がmarket_talkを持たなければDay2でも出ない（日番号に依らない）",
		Day1Events.market_talk_events().is_empty())
	ScheduleData._episode_cache["officer/officer_01"] = {
		"id": "officer_01", "customer": "officer", "greet": ["x"], "reactions": {}, "servings": 1,
		"market_talk": "文字列（配列でない）" }
	c.check("配列でないmarket_talkは無視（クラッシュしない）", Day1Events.market_talk_events().is_empty())
	ScheduleData._episode_cache["officer/officer_01"] = {
		"id": "officer_01", "customer": "officer", "greet": ["x"], "reactions": {}, "servings": 1,
		"market_talk": ["", 3, "有効な行"] }
	c.check("空文字・文字列でない行は捨て、有効な行だけ出す",
		_market_talks(Day1Events.prep_after_tier_events(Day1Events.PREP_TIERS[1], false)) == [["officer", "有効な行"]])
	ScheduleData.clear_cache()

	GameState.reset_for_new_game()
	if is_instance_valid(panel):
		panel.free()
	return c.finish()
