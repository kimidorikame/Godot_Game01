extends RefCounted
## 本番UIを「ボタンを押す・会話枠をクリックする」だけで1手ずつ進める台本（UIの通しテストとスクリーンショット用）。
## DebugPanel も PlaySession の操作も直接は呼ばない（押す先を決めるために状態を読むだけ）。押せないボタンは押さない。
## step(root) は押したもの（クリックを含む）の名前を返す。結果・ゲームオーバーの全面では "" を返して止まる。

var root: UiGameRoot
var session: PlaySession
## 鍋の素の段階（0＝小・1＝中・2＝大）。押せなければ押せる段階のうち一番大きいもの。
var tier_index := 1
## 市場で寄る店（店の一覧の何番目か）と、1回の訪問で「買う」を押す回数（Day2から。具材を切らさないため）。
const SHOP_PLAN := { 3: 2, 2: 1, 0: 1 }   # 豆腐麺 2回・乾物調味料 1回・食肉仲卸 1回
var _visited := {}
var _visited_day := -1
var _bought_here := 0


func _init(game_root: UiGameRoot) -> void:
	root = game_root
	session = game_root.session


static func press(button: BaseButton) -> bool:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


static func click(control: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	control.gui_input.emit(ev)


func _talk() -> String:
	click(root.left.get_node("%DialogueBox"))
	return "会話をクリック"


func step() -> String:
	if root.full_gameover.visible or root.full_result.visible:
		return ""
	if root.full_prep.visible:
		if press(root.full_prep.get_node("%OpenButton")):
			return "開店する"
		click(root.full_prep)
		return "仕込みをクリック"
	var choices: Control = root.left.get_node("%Choices")
	if choices.get_child_count() > 0 and press(choices.get_child(0)):
		return "選択肢"
	if root.pane_phone.visible:
		if session.is_waiting_input() and str(session.current_line().get("type", "")) == EventRunner.TYPE_WAIT_INPUT:
			return _talk()   # スマホを開いたまま会話を進める＝入力待ち「スマホを見る。」を終える
		press(root.pane_phone.get_node("%CloseButton"))
		return "スマホを閉じる"
	if root.pane_log.visible:
		press(root.pane_log.get_node("%CloseButton"))
		return "ログを閉じる"
	if root.pane_morning.visible:
		var primary: Button = root.pane_morning.get_node("%PrimaryButton")
		if primary.text == "市場へ" and press(primary):
			return "市場へ"
		if session.is_waiting_input() and press(primary):
			return "スマホを見る"
		return _talk()
	if GameState.day_count != _visited_day:
		_visited_day = GameState.day_count
		_visited = {}
	if root.pane_buy_meat.visible and session.is_in_market():
		return _buy_in(root.pane_buy_meat, 0)
	if root.pane_buy_meat.visible:
		var tiers: Control = root.pane_buy_meat.get_node("%Tiers")
		for i in [tier_index, 2, 1, 0]:
			if i < tiers.get_child_count() and press(tiers.get_child(i)):
				return "鍋の素（%d）" % i
		if press(root.pane_buy_meat.get_node("%BackButton")):
			return "店選びへ"
		return _talk()
	if root.pane_market.visible:
		var stalls: Control = root.pane_market.get_node("%Stalls")
		for index in SHOP_PLAN:
			if not _visited.has(index) and index < stalls.get_child_count() and press(stalls.get_child(index)):
				_visited[index] = true
				_bought_here = 0
				return "店に入る（%d）" % index
		if press(root.pane_market.get_node("%ExitButton")):
			return "市場を出る"
		return _talk()
	if root.pane_buy_shop.visible:
		var index := -1
		for stall_index in SHOP_PLAN:
			var stalls: Array = session.market_stalls()
			if stall_index < stalls.size() and str(stalls[stall_index]["id"]) == session.market_shop:
				index = stall_index
		return _buy_in(root.pane_buy_shop, index)
	if root.pane_kaiten.visible:
		return _kaiten()
	if root.pane_close.visible:
		if press(root.pane_close.get_node("%NextButton")):
			return "次の日へ"
		return _talk()
	return _talk()


## 店の中：商品の1行目の「買う」を SHOP_PLAN の回数だけ押してから、店選びへ戻る。
func _buy_in(pane: Control, stall_index: int) -> String:
	var goods: Control = pane.get_node("%Goods")
	if _bought_here < int(SHOP_PLAN.get(stall_index, 0)) and goods.get_child_count() > 0 \
			and press(goods.get_child(0).get_node("BuyButton")):
		_bought_here += 1
		return "買う"
	press(pane.get_node("%BackButton"))
	return "店選びへ戻る"


func _kaiten() -> String:
	var pane := root.pane_kaiten
	var pot := pane.pot
	var top := pane.topping
	if top.is_adjusting() and not top.visible:
		press(pane.get_node("%ToppingTab"))
		return "トッピングタブ"
	if pot.visible:
		if press(pot.get_node("%ResumeButton")):
			return "営業を続ける"
		if session.is_shortage_pending() and press(pot.get_node("%WaterButton")):
			return "水"
		if session.is_shortage_pending() and press(pot.get_node("%DashiButton")):
			return "だし"
		if press(pot.get_node("%CloseButton")):
			return "閉店（保留）"
		if press(pot.get_node("%CloseNightButton")):
			return "閉店する"
		return _talk()
	# トッピング
	if top.get_node("%GroupBox").visible:
		if press(top.get_node("%GroupServe")):
			return "団体：提供"
		press(top.get_node("%GroupDecline"))
		return "団体：断る"
	if not top.is_adjusting():
		return _talk()
	var bowl := session.bowl_view()
	var has_topping := false
	var has_flavor := false
	for id in bowl.get("additions", []):
		has_topping = has_topping or Ingredients.is_topping(str(id))
		has_flavor = has_flavor or Ingredients.is_flavor(str(id))
	var tabs: HBoxContainer = top.get_node("%Tabs")
	if (bowl.get("additions", []) as Array).size() < 3:
		if not has_topping and _pick(top, tabs, "具材"):
			return "具材を入れる"
		if not has_flavor and _pick(top, tabs, "調味料"):
			return "調味料を入れる"
	if press(top.get_node("%ServeButton")):
		return "提供"
	if press(top.get_node("%DeclineButton")):
		return "断る"
	return _talk()


## 分類タブ（名前が prefix で始まる最初のタブ）を開き、押せる最初の具材ボタン（新鮮な側）を押す。
func _pick(top: UiKaitenTopping, tabs: HBoxContainer, prefix: String) -> bool:
	for tab in tabs.get_children():
		if tab.visible and (tab as Button).text.begins_with(prefix):
			press(tab)
			break
	var grid: GridContainer = top.get_node("%Grid")
	for item in grid.get_children():
		if item.visible and press(item.get_node("MainButton")):
			return true
	return false
