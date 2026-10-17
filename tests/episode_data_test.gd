extends RefCounted
## 来店場面（episode）と基本プロフィールのデータ（フェーズ4-4a・DESIGN.md 10.8.1・10.8.6）の検証。
## 対象：data/episodes/<客>/<episode_id>.json（21ファイル）、data/customers/<id>.json の
## プロフィール、week7_regulars.json の episode_id、ScheduleData の新しい読み込み口。
## 4-4aは動作を変えないデータ構造の整理なので、customer_events() の出力が4-3の記録
## （fixture。全常連×Day1〜7）と一致することを確かめる（日程に無い6組だけ意図した差）。

# 21枠の episode_id（日 → [宵の口, 夜半, 明け方]）。来店順の連番。
const EPISODES := {
	1: ["delivery_man_01", "thug_01", "granny_01"],
	2: ["officer_01", "delivery_man_02", "thug_02"],
	3: ["hooker_01", "granny_02", "officer_02"],
	4: ["streamer_01", "hooker_02", "delivery_man_03"],
	5: ["thug_03", "officer_03", "streamer_02"],
	6: ["delivery_man_04", "thug_04", "hooker_03"],
	7: ["streamer_03", "officer_04", "granny_03"],
}
const REGULARS := {
	1: ["delivery_man", "thug", "granny"],
	2: ["officer", "delivery_man", "thug"],
	3: ["hooker", "granny", "officer"],
	4: ["streamer", "hooker", "delivery_man"],
	5: ["thug", "officer", "streamer"],
	6: ["delivery_man", "thug", "hooker"],
	7: ["streamer", "officer", "granny"],
}
const BASE_ORDER := {
	"delivery_man": ["HOT", "POWER"], "thug": ["MELLOW", "GENTLE"], "granny": ["SAVORY", "FILLING"],
	"officer": ["SOUR", "BITE"], "hooker": ["BITTER", "TREAT"], "streamer": ["MELLOW", "BITE"],
}
const FIXTURE_PATH := "res://tests/fixtures/customer_events_4_3.json"
const EPISODE_KEYS := ["customer", "greet", "id", "reactions", "servings"]
# 任意のキー（あれば型を検査する）。market_talk＝昼の市場の会話（システム整理A。officer_01だけが持つ）。
const OPTIONAL_KEYS := ["market_talk", "pre_order", "body", "body_unserved", "choices", "closing",
	"sets_facts", "must_info", "cups"]
# 複数杯の場面（cups。システム整理E）の必須キー：反応・杯数は cups の各杯が持つので reactions・servings は無い。
const CUPS_EPISODE_KEYS := ["customer", "greet", "id"]
# cups を持つ場面（Day1の配達員の3杯）。他の場面は持たない。
const CUPS_EPISODES := ["delivery_man_01"]
# 提供後の場面データ（システム整理C）の新キー。現行の21場面はどれも持たない（既存データは動作が変わらない）。
const AFTER_SERVE_KEYS := ["pre_order", "body", "body_unserved", "choices", "closing", "sets_facts", "must_info"]
const MARKET_TALK_EPISODES := ["officer_01"]
const CUSTOMERS := ["delivery_man", "thug", "granny", "officer", "hooker", "streamer"]
# 日程に無く、旧データでは当日のキーもDay1のキーも無く会話データを持たなかった組（日:客）。
# 日番号で引くのをやめたため、日程に無い客はその客の最後の場面（通常の1杯）を返す＝
# 要求タグ・会話・杯数が入る。ゲーム内では呼ばれない組み合わせ（意図した差）。
const KNOWN_DIFFS := ["1:officer", "1:hooker", "2:hooker", "1:streamer", "2:streamer", "3:streamer"]


## JSONを通した形（整数が小数になる差を避けて比べるため）にそろえる。
func _norm(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func run(_t: SceneTree) -> int:
	var c := TestCheck.new()
	ScheduleData.clear_cache()
	GameState.reset_for_new_game()

	# --- 1. 21枠が有効な episode_id を持つ（表どおり・場面ファイルがある・customer が一致） ---
	var seen := {}
	for d in range(1, 8):
		var slots := ScheduleData.regular_slots(d)
		c.check("Day%d：枠は3つ" % d, slots.size() == 3)
		for i in range(slots.size()):
			var regular := str(slots[i].get("regular", ""))
			var eid := str(slots[i].get("episode_id", ""))
			var label := "Day%d 枠%d（%s）" % [d, i, regular]
			c.check("%s：常連は10.5.1の表どおり" % label, regular == REGULARS[d][i])
			c.check("%s：episode_idは表どおり（%s）" % [label, EPISODES[d][i]], eid == EPISODES[d][i], eid)
			var ep := ScheduleData.episode_data(regular, eid)
			c.check("%s：場面ファイルがある" % label, not ep.is_empty())
			c.check("%s：場面のid・customerが枠と一致" % label,
				str(ep.get("id", "")) == eid and str(ep.get("customer", "")) == regular)
			var required_keys := ep.keys().filter(func(k): return not OPTIONAL_KEYS.has(k))
			required_keys.sort()
			var is_cups := ep.has("cups")
			c.check("%s：cups を持つのは複数杯の場面（配達員の3杯）だけ" % label, is_cups == CUPS_EPISODES.has(eid))
			c.check("%s：場面のキーは id/customer/greet/reactions/servings（複数杯の場面は id/customer/greet）＋任意キーのみ（日番号キー無し）" % label,
				required_keys == (CUPS_EPISODE_KEYS if is_cups else EPISODE_KEYS), str(ep.keys()))
			for k in AFTER_SERVE_KEYS:
				c.check("%s：新しいキー %s は持たない（現行データは動作が変わらない）" % [label, k], not ep.has(k))
			c.check("%s：場面データの形に問題が無い（scene_problems）" % label,
				ScheduleData.scene_problems(ep).is_empty(), str(ScheduleData.scene_problems(ep)))
			var has_talk := ep.has("market_talk")
			c.check("%s：market_talkを持つのは officer_01 だけ" % label, has_talk == MARKET_TALK_EPISODES.has(eid))
			if has_talk:
				var talk = ep["market_talk"]
				var talk_ok: bool = talk is Array and not (talk as Array).is_empty()
				if talk_ok:
					for line in talk:
						talk_ok = talk_ok and line is String and line != ""
				c.check("%s：market_talkは空でない文字列の配列" % label, talk_ok, str(talk))
				c.check("%s：episode_market_talk()が同じ行を返す" % label,
					ScheduleData.episode_market_talk(regular, eid) == talk)
			seen[eid] = true
	c.check("episode_idは21個すべて異なる（来店順ごとに1場面）", seen.size() == 21)

	# --- 2. 場面の番号は、その客の来店順の連番 ---
	for cid in CUSTOMERS:
		var ids := ScheduleData.customer_episode_ids(cid)
		var want := []
		for n in range(1, ids.size() + 1):
			want.append("%s_%02d" % [cid, n])
		c.check("%s：場面idは日程の順に連番（%s）" % [cid, str(want)], ids == want, str(ids))
	c.check("来店回数＝場面数（4・4・4・3・3・3）",
		ScheduleData.customer_episode_ids("delivery_man").size() == 4
			and ScheduleData.customer_episode_ids("thug").size() == 4
			and ScheduleData.customer_episode_ids("officer").size() == 4
			and ScheduleData.customer_episode_ids("granny").size() == 3
			and ScheduleData.customer_episode_ids("hooker").size() == 3
			and ScheduleData.customer_episode_ids("streamer").size() == 3)
	c.check("日程に無い客は場面なし", ScheduleData.customer_episode_ids("no_such_customer").is_empty())

	# --- 3. 基本プロフィール：is_mob・favorite・wanted_tags（日番号を持たない） ---
	for cid in CUSTOMERS:
		var profile := ScheduleData.customer_profile(cid)
		c.check("%s：プロフィールに日番号のdaysが無い" % cid, not profile.has("days"))
		c.check("%s：基本注文は10.5.1どおり" % cid, profile.get("wanted_tags", []) == BASE_ORDER[cid],
			str(profile.get("wanted_tags")))
		c.check("%s：is_mobはfalse・好物がある" % cid,
			not bool(profile.get("is_mob", true)) and str(profile.get("favorite", "")) != "")
	c.check("未知の客のプロフィールは空辞書", ScheduleData.customer_profile("no_such_customer_xyz").is_empty())
	c.check("無い場面は空辞書（エラーにならない）",
		ScheduleData.episode_data("thug", "thug_99").is_empty()
			and ScheduleData.episode_data("", "x").is_empty() and ScheduleData.episode_data("thug", "").is_empty())

	# --- 4. 日程の無い日（Day8）は枠が空 ---
	c.check("日程の無い日（Day8）の枠は空", ScheduleData.regular_slots(8).is_empty())

	# --- 6. 同一性の保証：customer_events() の出力が4-3の記録と一致する（全常連×全日） ---
	# fixtureは4-3の実装（コミット0378166）で記録した。両方をJSONを通した形にそろえて比べる。
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	c.check("記録ファイルが読める（7日分）", fixture is Dictionary and (fixture as Dictionary).size() == 7)
	for d in range(1, 8):
		for cid in CUSTOMERS:
			var now = _events_at(cid, d)
			var recorded = fixture[str(d)][cid]
			if KNOWN_DIFFS.has("%d:%s" % [d, cid]):
				# 日程に無い組み合わせ（ゲーム内では呼ばれない）。旧データでは会話データが
				# 無かったが、新実装は日程に無い客に最後の場面を返す。その客が日程にある日の
				# 出力（同じ場面）と一致し、基本注文・会話が入っていることを確かめる。
				var on_schedule = _events_at(cid, _scheduled_day(cid))
				var reacts = (now as Array).filter(func(e): return str(e.get("type", "")) == "REACT")
				c.check("Day%d %s（日程に無い組）：通常の場面（最後の場面）を返す" % [d, cid],
					now == on_schedule and reacts.size() == 1
						and reacts[0].get("wanted_tags", []) == BASE_ORDER[cid]
						and (now as Array)[0].get("type", "") == "GREET")
			else:
				c.check("Day%d %s：customer_eventsが4-3の記録と一致" % [d, cid], now == recorded,
					"%d vs %d events" % [(now as Array).size(), (recorded as Array).size()])
	GameState.reset_for_new_game()

	return c.finish()


func _sorted_keys(d: Dictionary) -> Array:
	var ks := d.keys()
	ks.sort()
	return ks


## 記録時と同じ固定の在庫（ADJUSTのoptionsが在庫から組まれるため）で、その日の
## customer_eventsをJSONを通した形で返す（日付を進めた在庫の傷みが混ざらないよう毎回作り直す）。
func _events_at(customer_id: String, day: int) -> Variant:
	GameState.reset_for_new_game()
	GameState.day_count = day
	GameState.add_inventory("nam_prik_pao", 2)
	GameState.add_inventory("tofu", 1)
	GameState.add_inventory("herbal_sauce", 1)
	return _norm(Day1Events.customer_events(customer_id))


## その客が日程にある日のうち、最後の日（最後の場面の日）。
func _scheduled_day(customer_id: String) -> int:
	var last := 1
	for d in range(1, 8):
		for entry in ScheduleData.regular_slots(d):
			if str(entry.get("regular", "")) == customer_id:
				last = d
	return last

