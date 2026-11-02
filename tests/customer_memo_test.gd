extends RefCounted
## 店主のメモ帳（客タブ。UI準備O2）。場面データの memo（省略可）を、その来店で1杯以上出したら日の終わり（閉店のあと）に来店記録の
## facts["memo"]（{ day, key＝場面id }）へ足し、翌朝から客タブで見える。客タブは一覧（名前だけ）→詳細（前回頼んだ注文の札・来た日・好物・メモ）。
## 新しいメモは客タブとスマホのボタンに●（客タブを開いたら消える）、詳細では「新」（見たら消える）。好物を知る時刻は favorite_reveal
## （"first_serve"＝今までどおり／"memo"＝reveals_favorite のある来店のメモを足したとき）。今の場面データには memo を入れていないので、
## このテストは読み込んだ場面データに一時的に memo を足して確かめる（終わったら外す）。


func _press(button: BaseButton) -> bool:
	return load("res://tests/ui_autoplay.gd").press(button)


func _texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_texts(child, out)
	return out


## 全部の名前あり客の場面に、仮のメモ（「<場面id>のメモ」の1行）を足す／外す。
func _set_memos(on: bool, reveal_customer: String = "") -> void:
	for customer_id in DirAccess.get_directories_at("res://data/episodes/"):
		for file in DirAccess.get_files_at("res://data/episodes/%s/" % customer_id):
			if not file.ends_with(".json"):
				continue
			var ep := ScheduleData.episode_data(customer_id, file.get_basename())
			if on:
				ep["memo"] = ["%sのメモ" % file.get_basename()]
				if customer_id == reveal_customer:
					ep["reveals_favorite"] = true
			else:
				ep.erase("memo")
				ep.erase("reveals_favorite")


## Day1 を通しで遊ぶ（チンピラだけ、何も入れずに断る）。Day2 の朝（市場の前）で止める。閉店の画面で knows を見る客がいれば、そのときの値を返す。
func _play_day1(root: UiGameRoot, watch: String = "") -> Dictionary:
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var guard := 0
	var seen := { "close_known": null, "close_memo": -1 }
	while not (GameState.day_count == 2 and GameState.phase == GameState.Phase.WAKE) and guard < 3000:
		guard += 1
		if s.open != null and GameState.phase == GameState.Phase.OPEN and s.is_choosing_ingredients() and str(s.open.current_customer()) == "thug" \
				and (s.open.current_bowl.get("additions", []) as Array).is_empty():
			s.decline_customer()
		if GameState.phase == GameState.Phase.CLOSE and seen["close_memo"] == -1:
			seen["close_memo"] = (CustomerMemory.fact("delivery_man", "memo", []) as Array).size()
			if watch != "":
				seen["close_known"] = GameState.knows_favorite(watch)
		play.step()
	return seen


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. データの検査 ---
	var ok_ep := { "customer": "granny", "memo": ["1年前から通っているらしい"], "reveals_favorite": true }
	c.check("memo：数字は使ってよい・reveals_favorite は名前あり客の場面で memo があればよい", ScheduleData.scene_problems(ok_ep).is_empty(), str(ScheduleData.scene_problems(ok_ep)))
	c.check("memo：空の文は弾く", not ScheduleData.scene_problems({ "customer": "granny", "memo": ["", "あ"] }).is_empty())
	c.check("memo：内部の札の名前（英字の札）は弾く", ScheduleData.scene_problems({ "customer": "granny", "memo": ["HOT が好きらしい"] }).any(func(x): return str(x).contains("HOT")))
	c.check("reveals_favorite：モブの場面にあれば弾く", ScheduleData.scene_problems({ "customer": "dock_workers", "memo": ["あ"], "reveals_favorite": true }).any(func(x): return str(x).contains("名前あり客")))
	c.check("reveals_favorite：true／false でなければ弾く・true なのに memo が無ければ弾く",
		not ScheduleData.scene_problems({ "customer": "granny", "memo": ["あ"], "reveals_favorite": "yes" }).is_empty()
			and ScheduleData.scene_problems({ "customer": "granny", "reveals_favorite": true }).any(func(x): return str(x).contains("memo が無い")))
	c.check("規則データ：favorite_reveal は first_serve（今の動き）", Rules.favorite_reveal() == "first_serve" and GameState.FAVORITE_REVEAL == "first_serve")

	# --- 2. 閉店のあとに足す・翌朝から見える・出さなかった来店は足さない ---
	ReadState.reset("user://test_read_memo.json")
	_set_memos(true)
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var seen := _play_day1(root)
	var dm_memo: Array = CustomerMemory.fact("delivery_man", "memo", [])
	var dm_ep := str(CustomerMemory.visits_of("delivery_man")[0]["episode_id"])
	c.check("閉店の時点ではまだ足さない（日の終わりに足す）", int(seen["close_memo"]) == 0, str(seen))
	c.check("翌朝：1杯以上出した来店のメモが足されている（{ day, key＝場面id }）", dm_memo.size() == 1 and int(dm_memo[0]["day"]) == 1 and str(dm_memo[0]["key"]) == dm_ep, str(dm_memo))
	c.check("全部断った来店（チンピラ）は足さない", (CustomerMemory.fact("thug", "memo", []) as Array).is_empty() and int(CustomerMemory.visits_of("thug")[0]["served"]) == 0)
	var notes := s.phone_notes()
	var dm_note: Dictionary = notes["regulars"][0]
	c.check("客ノートの行にメモ（日付付き。文は表示のときにデータから引く）", str(dm_note["id"]) == "delivery_man" and (dm_note["memo"] as Array).size() == 1
		and str(dm_note["memo"][0]["text"]) == "%sのメモ" % dm_ep and int(dm_note["memo"][0]["day"]) == 1, str(dm_note["memo"]))
	c.check("前回：基本の注文の客は、いつもの札（配達員＝辛い・スタミナ）", dm_note["last_order"] == ["HOT", "POWER"], str(dm_note["last_order"]))
	var granny_ep := str(CustomerMemory.visits_of("granny")[0]["episode_id"])
	ScheduleData.episode_data("granny", granny_ep)["order"] = { "today_request": { "tags": ["MELLOW", "GENTLE"], "label": "" } }
	var granny_note: Dictionary = (s.phone_notes()["regulars"] as Array).filter(func(r): return str(r["id"]) == "granny")[0]
	c.check("前回：その来店に今日の頼みがあれば、頼んだ札（いつもの札ではない）", granny_note["last_order"] == ["MELLOW", "GENTLE"] and granny_note["tags"] != granny_note["last_order"],
		str(granny_note["last_order"]))
	ScheduleData.episode_data("granny", granny_ep).erase("order")
	var lines_total := 0
	for r in notes["regulars"]:
		lines_total += (r["memo"] as Array).size()

	# --- 3. ●（客タブ・スマホのボタン）と「新」---
	var phone: UiPanePhone = root.pane_phone
	var content: VBoxContainer = phone.get_node("%Content")
	c.check("新しいメモがあると、スマホのボタンの未読に入る", s.memo_unread_count() == lines_total and lines_total >= 2 and s.phone_unread_count() >= lines_total)
	root.open_phone("news")
	c.check("客タブに●と数（ほかのタブを表示しているとき）", (phone.get_node("%NotesBadge") as Label).text == "●%d" % lines_total, (phone.get_node("%NotesBadge") as Label).text)
	_press((phone.get_node("%Tabs") as Control).get_child(3))
	c.check("客タブを開いたら●が消える", s.memo_unread_count() == 0 and (phone.get_node("%NotesBadge") as Label).text == "")
	var row: Button = content.get_node("NoteRow_delivery_man")
	c.check("一覧：名前だけ・まだ詳細で見ていないメモのある客の行に「新」", row.has_node("NewMark") and _texts(row).has("配達員") and not content.has_node("NoteRow_thug/NewMark"))
	_press(row)
	var detail := _texts(content)
	c.check("詳細：前回（頼んだ注文の札）・来た日・メモ（日付と「新」）。入れた材料の行は出さない", phone.notes_open == "delivery_man" and detail.has("前回") and detail.has("辛い")
		and detail.has("スタミナ") and not detail.has("いつもの") and not detail.any(func(x): return str(x).begins_with("前回　")) and detail.has("来た日　Day1")
		and detail.has("%sのメモ" % dm_ep) and detail.has("新") and detail.has(Calendar.label(1)), str(detail))
	_press(content.get_node("NoteBack"))
	c.check("「戻る」で一覧・見たあとは「新」が消える", phone.notes_open == "" and content.has_node("NoteRow_delivery_man") and not content.has_node("NoteRow_delivery_man/NewMark")
		and s.memo_new_ids("delivery_man").is_empty())
	_press(content.get_node("NoteRow_delivery_man"))
	c.check("もう一度開くと「新」は付かない", not _texts(content).has("新"))
	_press(content.get_node("NoteBack"))
	_press(content.get_node("NoteRow_mob_dock_workers"))
	c.check("モブの詳細は好みの札だけ（メモは無い）", phone.notes_open == "mob:dock_workers" and _texts(content).has("好み") and not _texts(content).has("メモ"), str(_texts(content)))
	root.close_overlay()

	# --- 4. 朝の保存から戻すとメモも戻る・再挑戦ではその日より後のメモは消える ---
	var envelope: Dictionary = MorningSave.capture("")
	var later: Array = (CustomerMemory.fact("delivery_man", "memo", []) as Array).duplicate(true)
	later.append({ "day": 2, "key": dm_ep + "_x" })
	CustomerMemory.set_fact("delivery_man", "memo", later)
	MorningSave.apply(envelope)
	var back: Array = CustomerMemory.fact("delivery_man", "memo", [])
	c.check("朝の保存から戻す：その朝のメモに戻る（後の日に足したメモは消える）", back.size() == 1 and str(back[0]["key"]) == dm_ep, str(back))
	root.queue_free()

	# --- 5. favorite_reveal："memo" ---
	_set_memos(false)
	_set_memos(true, "granny")
	GameState.FAVORITE_REVEAL = "memo"
	GameState.reset_for_new_game()
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	seen = _play_day1(root, "granny")
	c.check("memo：初めて出しただけでは好物を知らない（閉店の時点）", seen["close_known"] == false, str(seen))
	c.check("memo：reveals_favorite のある来店のメモを足したときに知る（翌朝）", GameState.knows_favorite("granny"))
	c.check("memo：reveals_favorite の無い客は、出しても知らない", not GameState.knows_favorite("delivery_man"))
	root.queue_free()
	GameState.FAVORITE_REVEAL = "first_serve"
	GameState.reset_for_new_game()
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	seen = _play_day1(root, "granny")
	c.check("first_serve（今の動き）：初めて出したときに知る（閉店の時点で知っている）", seen["close_known"] == true and GameState.knows_favorite("granny"), str(seen))
	root.queue_free()

	_set_memos(false)
	GameState.FAVORITE_REVEAL = Rules.favorite_reveal()
	GameState.reset_for_new_game()
	ReadState.reset(ReadState.path)
	return c.finish()
