extends RefCounted
## PlaySession（UI準備A①：骨組み）の検証。
## 対象：部品が FlowController を自分で持つこと、changed の通知、DebugPanelとの結線
## （session をパネルの子として持ち、flow は session.flow を返す橋、changed で描き直す）。
## 処理の移動（市場・開店・閉店…）は②以降で、それぞれの塊のテスト（既存スイート）が確かめる。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 部品の単体：FlowController を自分で作って持つ・changed を1回ずつ出す ---
	var s := PlaySession.new()
	c.check("flow（FlowController）を自分で持ち、子ノードにしている", s.flow is FlowController and s.flow.get_parent() == s)
	var count := { "n": 0 }
	s.changed.connect(func(): count["n"] += 1)
	c.check("通知の前は changed は出ていない", count["n"] == 0)
	s.notify_changed()
	c.check("notify_changed() で changed が1回出る", count["n"] == 1)
	s.notify_changed()
	c.check("もう一度呼べばもう一度出る（出るたびにUIは全体を描き直す）", count["n"] == 2)
	s.free()

	# --- 2. DebugPanelとの結線 ---
	GameState.reset_for_new_game()
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	c.check("木に入れる前から session と flow を使える",
		panel.session is PlaySession and panel.session.flow is FlowController)
	t.root.add_child(panel)
	c.check("PlaySession はパネルの子ノード", panel.session.get_parent() == panel)
	c.check("FlowController は PlaySession の子で、パネル直下にもう無い（.tscn から外した）",
		panel.get_node_or_null("FlowController") == null and panel.session.flow.get_parent() == panel.session)
	c.check("起動すると最初の朝（WAKE）の列が組まれる（従来どおり）",
		GameState.phase == GameState.Phase.WAKE and panel.session.flow.runner != null and panel.session.flow.runner.events.size() > 0)
	panel._runner_label.text = "（描き直す前）"
	panel.session.notify_changed()
	c.check("changed を受けるとパネルが描き直す（_refresh）", panel._runner_label.text != "（描き直す前）")
	panel.free()
	GameState.reset_for_new_game()
	return c.finish()
