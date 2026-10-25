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
	# 朝の列：目が覚めた／（スマホの入力待ち・ニュースは会話枠に出さずに続けて進む）／共同水道の払い／さて、準備へ向かうか
	var steps := 0
	var texts: Array = []
	while steps < 6 and not s.flow.is_runner_done():
		var before: int = s.flow.runner.index
		_click_box(root)
		steps += 1
		texts.append(_box_text(root))
		if s.flow.runner.index <= before:
			break
	c.check("Day1の朝：会話枠のクリックで進み、ニュースとスマホの入力待ちの行は出ない（本物のマウス）",
		s.flow.is_runner_done() and steps == 3 and not texts.any(func(x): return str(x).contains("ニュース：") or str(x).contains("スマホを見る")),
		str(texts))
	c.check("朝の会話枠が空にならない（列の終わりでも、最後に出した行を残す）", not texts.any(func(x): return str(x) == ""), str(texts))

	# --- 2. Enter・Space でも同じだけ進む（開店の前の朝の列の終わりまで）---
	GameState.reset_for_new_game()
	root.queue_free()
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	s = root.session
	play = load("res://tests/ui_autoplay.gd").new(root)
	var key_ok := true
	var key_texts: Array = []
	for keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
		var before_key: int = s.flow.runner.index
		_key(root, keycode)
		key_texts.append(_box_text(root))
		if s.flow.runner.index <= before_key:
			key_ok = false
	c.check("Enter・Space・テンキーのEnterでも、会話が進む（クリックと同じ。朝の3行）", key_ok and s.flow.is_runner_done(), str(key_texts))

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

	# --- 5. 左の列のどこをクリックしても進む（キャラ表示エリア・会話枠）。アイコンと右の枠では進まない。ログは進めずに閉じる ---
	GameState.reset_for_new_game()
	root = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	s = root.session
	var viewport := root.get_viewport()
	var left_hits := {}
	for ix in range(0, 41):
		for iy in range(0, 37):
			var pos := Vector2(ix * 20.0 + 1.0, iy * 20.0 + 1.0)   # 左の列 0〜820 × 0〜720
			if pos.x >= 820.0 or pos.y >= 720.0:
				continue
			var motion := InputEventMouseMotion.new()
			motion.position = pos
			motion.global_position = pos
			viewport.push_input(motion, true)
			var hit := viewport.gui_get_hovered_control()
			var hit_name := str(hit.name) if hit != null else "(なし)"
			left_hits[hit_name] = int(left_hits.get(hit_name, 0)) + 1
	var allowed := ["ClickArea", "DialogueBox", "PhoneIcon", "LogIcon", "SkipButton", "PhoneBadge"]
	var stray := {}
	for hit_name in left_hits:
		if not allowed.has(hit_name):
			stray[hit_name] = left_hits[hit_name]
	c.check("左の列（820×720）：どの点も、会話を進める領域（ClickArea・会話枠）かアイコンのボタンに当たる（ほかの部品が塞がない）",
		stray.is_empty() and left_hits.has("ClickArea") and left_hits.has("DialogueBox"), str(left_hits))
	var before_portrait: int = s.flow.runner.index
	load("res://tests/ui_autoplay.gd").click_at(viewport, Vector2(410, 300))   # キャラ表示エリア
	c.check("キャラ表示エリアをクリックしても、会話が進む", s.flow.runner.index > before_portrait, str(s.flow.runner.index))
	before_portrait = s.flow.runner.index
	load("res://tests/ui_autoplay.gd").click_at(viewport, Vector2(60, 300))   # 左端の何も無い所
	c.check("左の列の何も無い所をクリックしても、会話が進む", s.flow.runner.index > before_portrait or s.flow.is_runner_done())
	before_portrait = s.flow.runner.index
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%PhoneIcon"))
	c.check("スマホのアイコンでは会話は進まない（スマホの開閉）", s.flow.runner.index == before_portrait)
	var overlay_now: String = root.overlay
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%PhoneIcon"))
	c.check("スマホのアイコンをもう一度押すと元に戻る（会話は進まない）", s.flow.runner.index == before_portrait and root.overlay != overlay_now)
	# 右の枠：ボタンでも空き部分でも会話を進めない
	var right_pane: Control = root.right_pane
	var right_visible := ""
	for pane in root._panes():
		if (pane as Control).visible:
			right_visible = str(pane.name)
	var before_right: int = s.flow.runner.index
	load("res://tests/ui_autoplay.gd").click_at(viewport, right_pane.get_global_rect().get_center())
	c.check("右の枠の空き部分をクリックしても、会話は進まない（%s）" % right_visible, s.flow.runner.index == before_right)
	# ログ：開いているあいだのクリックは進めずに閉じる。もう一度ログのアイコンでも閉じる。右の枠は触らない
	var log_box: UiLogBox = root.left.get_node("%LogBox")
	var right_before_log := right_visible
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%LogIcon"))
	c.check("ログのアイコン：会話枠が上へ伸びて今日の行が並ぶ", root.left.is_log_open() and log_box.visible and log_box.row_count() >= 1
		and log_box.get_global_rect().position.y < root.left.get_node("%DialogueBox").get_global_rect().position.y
		and log_box.get_global_rect().end.y == root.left.get_node("%DialogueBox").get_global_rect().end.y)
	var after_open_right := ""
	for pane in root._panes():
		if (pane as Control).visible:
			after_open_right = str(pane.name)
	c.check("ログを開いても、右の枠は置き換わらない", after_open_right == right_before_log, "%s → %s" % [right_before_log, after_open_right])
	var before_log: int = s.flow.runner.index
	load("res://tests/ui_autoplay.gd").click_at(viewport, log_box.get_global_rect().get_center())
	c.check("ログの枠の中のクリックでは閉じない（会話も進まない）", root.left.is_log_open() and s.flow.runner.index == before_log)
	load("res://tests/ui_autoplay.gd").click_at(viewport, Vector2(410, 150))
	c.check("ログを開いているあいだ、枠の外（左の列）のクリックは会話を進めず、ログを閉じる",
		not root.left.is_log_open() and not log_box.visible and s.flow.runner.index == before_log)
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%LogIcon"))
	load("res://tests/ui_autoplay.gd").click(root.left.get_node("%LogIcon"))
	c.check("もう一度ログのアイコンを押しても閉じる（会話は進まない）", not root.left.is_log_open() and s.flow.runner.index == before_log)
	root.queue_free()
	return c.finish()
