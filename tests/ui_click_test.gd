extends RefCounted
## 会話枠のクリックの検証（本番UI）。本物のマウスイベント（InputEventMouseButton を Viewport.push_input で座標つきに送る）を使い、
## 当たり判定を通して確かめる。gui_input を直接呼ぶ方法では、上に重なった部品が会話枠のクリックを塞いでいても気づけない。
## 対象：会話枠のどの点をクリックしても会話枠に届く（押せない「既読スキップ」が右下に重なっても塞がない。押せるときだけ、そのボタンが受ける）、
## Day1 の朝・仕込み（初日セットの受け取りは空の枠でクリックさせない）・開店・閉店の会話枠のクリックで会話が進む、
## Enter・Space でも同じだけ進む。

const GRID_X := 31
const GRID_Y := 11


## 会話枠の格子の各点に、どのコントロールが当たるか。DialogueBox 以外が当たった点を { 名前: 数 } で返す。
func _blockers(root: UiGameRoot) -> Dictionary:
	var box: Control = root.left.get_node("%DialogueBox")
	var viewport := box.get_viewport()
	var rect := box.get_global_rect()
	var bad := {}
	for ix in range(GRID_X):
		for iy in range(GRID_Y):
			var pos := rect.position + Vector2(rect.size.x * (ix + 0.5) / GRID_X, rect.size.y * (iy + 0.5) / GRID_Y)
			var motion := InputEventMouseMotion.new()
			motion.position = pos
			motion.global_position = pos
			viewport.push_input(motion, true)
			var hit := viewport.gui_get_hovered_control()
			var hit_name := str(hit.name) if hit != null else "(なし)"
			# 押せる既読スキップは、右下に重なる本物のボタン（そこを押せば既読スキップ）。それ以外が当たったら塞がれている
			var skip: Button = root.left.get_node("%SkipButton")
			if hit_name == "DialogueBox" or (hit == skip and not skip.disabled):
				continue
			bad[hit_name] = int(bad.get(hit_name, 0)) + 1
	return bad


func _click_box(root: UiGameRoot) -> void:
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%DialogueBox"))


func _key(root: UiGameRoot, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	root.get_viewport().push_input(ev, true)


func _box_text(root: UiGameRoot) -> String:
	return str(root.left.get_node("%DialogueText").text)


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var s: PlaySession = root.session
	var play = load("res://tests/ui_autoplay.gd").new(root)
	var skip: Button = root.left.get_node("%SkipButton")

	# --- 1. Day1 の朝（スマホを開いた状態）---
	c.check("Day1の朝：会話枠の最初の行が出ている（空ではない）", _box_text(root) != "" and str(s.current_line().get("text", "")) != "", _box_text(root))
	var blockers := _blockers(root)
	c.check("会話枠のどの点にも、会話枠が当たる（塞ぐのは、押せる既読スキップのボタンだけ）", blockers.is_empty(), str(blockers))
	c.check("既読スキップは、押せないあいだはクリックを受けない（押せるときだけ受ける）", skip.disabled == (skip.mouse_filter == Control.MOUSE_FILTER_IGNORE))
	var steps := 0
	var all_one := true
	var detail := ""
	while steps < 5 and GameState.phase == GameState.Phase.WAKE:
		var before: int = s.flow.runner.index
		_click_box(root)
		if s.flow.runner.index != before + 1:
			all_one = false
			detail += " %d→%d" % [before, s.flow.runner.index]
		steps += 1
	c.check("Day1の朝：会話枠をクリックするたびに、会話が1つずつ進む（本物のマウス）", all_one and steps == 5, detail)

	# --- 2. Enter・Space でも同じだけ進む（開店の前の朝の列の終わりまで）---
	GameState.reset_for_new_game()
	root.queue_free()
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	s = root.session
	play = load("res://tests/ui_autoplay.gd").new(root)
	var key_ok := true
	for keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
		var before_key: int = s.flow.runner.index
		_key(root, keycode)
		if s.flow.runner.index != before_key + 1:
			key_ok = false
	c.check("Enter・Space・テンキーのEnterでも、会話が1つずつ進む", key_ok, str(s.flow.runner.index))

	# --- 3. Day1 の仕込み（鍋の素を選ぶまで）：空の枠でクリックさせない ---
	var guard := 0
	# 朝から仕込みへ：入ってすぐの行（受け取り）まで、台本（ボタンと会話枠のクリック）で進める
	while not (GameState.phase == GameState.Phase.PREP and s.flow.runner.index == 0) and guard < 40:
		guard += 1
		play.step()
	c.check("Day1の仕込みに入った（最初の行は受け取りの語り）", GameState.phase == GameState.Phase.PREP and s.flow.runner.index == 0
		and _box_text(root) != "")
	var clicks := 0
	var empty_seen := false
	var silent_seen := false
	guard = 0
	while not s.is_in_prep_tier() and guard < 40:
		guard += 1
		_click_box(root)
		clicks += 1
		if s.is_in_prep_tier():
			break
		if _box_text(root) == "":
			empty_seen = true
		if str(s.current_line().get("type", "")) == "ADD_ITEM":
			silent_seen = true
	c.check("Day1の仕込み：初日セットの受け取り（ADD_ITEM 7件）で、会話枠を空にしてクリックさせない", not empty_seen and not silent_seen,
		"クリック%d回・空の枠=%s・ADD_ITEMで止まった=%s" % [clicks, str(empty_seen), str(silent_seen)])
	c.check("鍋の素を選ぶ画面（PREP_TIER）まで、会話枠のクリックだけで着いた（5回）", s.is_in_prep_tier() and clicks == 5, str(clicks))
	var kit_total := 0
	for item in GameState.inventory:
		kit_total += int(GameState.inventory[item])
	c.check("受け取りのEventはすべて反映されている（初日セットの在庫が入っている）", kit_total > 0, str(GameState.inventory))
	c.check("仕込みの会話枠にも、押せない既読スキップは重ならない", _blockers(root).is_empty(), str(_blockers(root)))

	# --- 4. 開店・閉店の会話枠のクリック ---
	guard = 0
	while not (GameState.phase == GameState.Phase.OPEN and str(s.current_line().get("type", "")) == "GREET" and root.left.visible) and guard < 400:
		guard += 1
		play.step()
	var open_ok := GameState.phase == GameState.Phase.OPEN and str(s.current_line().get("type", "")) == "GREET"
	c.check("開店の最初の客の挨拶（GREET）まで進んだ", open_ok)
	if open_ok:
		var before_open: int = s.flow.runner.index
		c.check("開店の会話枠：どの点にも会話枠が当たる", _blockers(root).is_empty(), str(_blockers(root)))
		_click_box(root)
		c.check("開店の会話枠をクリックすると、挨拶から次のEventへ進む", s.flow.runner.index == before_open + 1, str(s.flow.runner.index))
	guard = 0
	while not (GameState.phase == GameState.Phase.CLOSE and s.can_next_event() and str(s.current_line().get("text", "")) != "") and guard < 600:
		guard += 1
		if play.step() == "":
			break
	var close_ok := GameState.phase == GameState.Phase.CLOSE and str(s.current_line().get("text", "")) != ""
	c.check("閉店の語りまで進んだ", close_ok)
	if close_ok:
		var before_close: int = s.flow.runner.index
		_click_box(root)
		c.check("閉店の会話枠をクリックすると、語りが進む", s.flow.runner.index == before_close + 1 or not s.can_next_event(), str(s.flow.runner.index))
		c.check("閉店の会話枠：どの点にも会話枠が当たる", _blockers(root).is_empty(), str(_blockers(root)))

	root.queue_free()
	return c.finish()
