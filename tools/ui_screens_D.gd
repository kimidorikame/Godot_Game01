# 本番UI（UI準備D）で変えた画面だけのスクリーンショットを撮る（1280×720のPNGを planning/ui_screens_D/ へ）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_D.gd
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd。ボタンと会話枠のクリックだけ）。
# あわせて、文字が枠に入りきらないラベル・ボタンを planning/ui_screens_D/overflow.txt に書き出す。
# セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

const OUT_DIR := "res://planning/ui_screens_D"

var gs
var ui   # UiGameRoot（クラス名で型を付けない＝autoload より先に読み込まれて止まらないように）
var play
var overflow: Array = []
var shots: Array = []


func _initialize() -> void:
	await process_frame
	load("res://scripts/morning_save.gd").set("save_path", "user://ui_screens_save.dat")
	load("res://scripts/morning_save.gd").call("delete_file")
	load("res://scripts/read_state.gd").call("reset", "user://ui_screens_read_state.json")
	load("res://scripts/balance_log.gd").set("path", "user://ui_screens_balance_log.jsonl")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	gs = root.get_node("GameState")
	gs.reset_for_new_game()
	ui = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(ui)
	ui.full_prep.auto_advance = false   # 撮るために、点は手で進める（実際は約0.7秒ごとに自動）
	play = load("res://tests/ui_autoplay.gd").new(ui)
	var s = ui.session

	# Day1 をUIだけで遊び、Day2 の朝（昨夜の成績）
	_until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible)
	await _shot("01_morning", "朝（Day2。主ボタンは「市場へ」だけ。朝の語りを読み終えるまで押せない。スマホのボタンの●はDMとニュースの未読の合計）")
	# 朝の語りを会話枠のクリックだけで読み終える（ニュース・スマホの入力待ちは会話枠に出ない）
	var guard := 0
	while not s.flow.is_runner_done() and guard < 40:
		guard += 1
		ui.left.advance()
	await _shot("02_morning_read", "朝（語りを読み終えた。「市場へ」が押せる。ニュースは未読のまま進める）")
	# スマホ：ニュース（開いた時点で未読だった見出しには ● が付く。SNSタブには未読のDMの数）
	play.click(ui.left.get_node("%PhoneIcon"))
	await _shot("03_phone_news", "スマホ（ニュース。開いた時点で未読だった見出しに ●。SNSタブの●はまだ読んでいないDM）")
	play.press(ui.pane_phone.get_node("%CloseButton"))
	await _shot("04_morning_after_phone", "朝（スマホを読んだあと。ボタンの●はSNSのDMだけ）")
	play.press(ui.pane_morning.get_node("%PrimaryButton"))
	# 張記：鍋の素を選ぶ直前。会話ログを開く（会話枠が上へ伸びる。右の枠はそのまま）
	_until(func(): return ui.pane_buy_meat.visible and s.is_in_prep_tier())
	ui.left.toggle_log()
	await _shot("05_log_open", "会話ログ（会話枠が上へ伸びて今日の行を並べる。右の枠＝張記はそのまま。もう一度ログを押すか、枠の外をクリックで閉じる）")
	ui.left.close_log()
	play.press(ui.pane_buy_meat.get_node("%Tiers").get_child(1))
	await _shot("06a_tier_selected", "購入（張記。鍋の素「中」を選んだところ。まだ買わない。「使える」から価格を引いて見せる。「購入確定」「購入して店を出る」）")
	play.press(ui.pane_buy_meat.get_node("%ConfirmButton"))
	play.press(ui.pane_buy_meat.get_node("%Goods").get_child(0).get_node("BuyButton"))
	await _shot("06_buy_meat", "購入（張記。中を買ったあと。モツをかごに入れたところ。かごの合計・「1つ戻す」「全部戻す」。出口は「買わずに店を出る」）")
	play.press(ui.pane_buy_meat.get_node("%CartBox/ClearButton"))
	_until(func(): return ui.pane_market.visible)
	play.press(ui.pane_market.get_node("%Stalls").get_child(3))
	var goods = ui.pane_buy_shop.get_node("%Goods")
	play.press(goods.get_child(0).get_node("BuyButton"))
	play.press(goods.get_child(0).get_node("BuyButton"))
	play.press(goods.get_child(1).get_node("BuyButton"))
	await _shot("07_buy_shop", "購入（福生豆腐麺房。豆腐2・米麺1をかごに入れたところ。「使える」はかごの分を引いた額。「購入確定」「購入して店を出る」）")
	# 撮るための状態：使える現金を ¥70 にして、かごに入れられない商品（米麺¥40）に理由を出す
	var pending_total: int = ui.cart.total("tofu_noodles")
	gs.money = int(ui.session.budget()["reserved"]) + pending_total + 20
	ui.session.notify_changed()
	await _shot("07b_buy_shop_limit", "購入（豆腐麺房。使える現金が残り ¥20 の仮の状態：これを超える商品はかごに入れられず、理由が出る）")
	gs.money = int(ui.session.budget()["reserved"]) + 500
	ui.cart.clear_all()
	play.press(ui.pane_buy_shop.get_node("%BackButton"))
	play.press(ui.pane_market.get_node("%ExitButton"))
	ui.full_prep.tick(0.7)
	await _shot("08_prep_dots", "仕込み（全面。クリックなしで約0.7秒ごとに点が1つずつ点く。2つ目まで点いた途中）")
	play.click(ui.full_prep)
	await _shot("09_prep_done", "仕込み（全面。クリックですぐ全部点く。全部ついたら「開店する」）")
	# 開店：椀を作っている最中。入れた具材には「✓」。もう一度押すと取り消せる（D-3）
	play.press(ui.full_prep.get_node("%OpenButton"))
	var top = ui.pane_kaiten.topping
	_until(func(): return gs.phase == gs.Phase.OPEN and top.visible and top.is_adjusting())
	var grid = top.get_node("%Grid")
	for item in grid.get_children():
		if item.visible and not item.get_node("MainButton").disabled:
			play.press(item.get_node("MainButton"))
			break
	await _shot("10_topping_in_bowl", "開店のトッピング（具材を1つ入れたところ：入れた具材のボタンに「✓」。もう一度押すと椀から外れて在庫が戻る）")
	_write_overflow()
	print("UI_SCREENS_DONE %d" % shots.size())
	quit()


## 台本で1手ずつ進める（cond が真になるまで）。each を渡せば、台本の代わりにそれを呼ぶ。
func _until(cond: Callable, each: Callable = Callable(), limit: int = 3000) -> void:
	var n := 0
	while not cond.call() and n < limit:
		n += 1
		if each.is_valid():
			each.call()
		elif play.step() == "":
			break
	if not cond.call():
		push_error("状態に届かなかった（%d手）" % n)


func _shot(file_name: String, title: String) -> void:
	for i in range(4):
		await process_frame
	var path := "%s/%s.png" % [OUT_DIR, file_name]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	shots.append("%s.png  %s" % [file_name, title])
	_collect_overflow(file_name, ui)


## 文字が枠に入りきらないもの：1行のラベル・ボタンは幅、折り返すラベルは高さを見る（切って「…」にしているものは除く）。
func _collect_overflow(file_name: String, node: Node) -> void:
	for child in node.get_children():
		_collect_overflow(file_name, child)
	if not (node is Control) or not (node as Control).is_visible_in_tree():
		return
	if node is Label:
		var label: Label = node
		if label.text == "" or label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			return
		var need: Vector2 = label.get_minimum_size()
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and need.x > label.size.x + 1.0:
			overflow.append("%s: %s 「%s」 幅 %d が必要（枠 %d）" % [file_name, ui.get_path_to(label), label.text.replace("\n", "／"), need.x, label.size.x])
		elif label.autowrap_mode != TextServer.AUTOWRAP_OFF and need.y > label.size.y + 1.0 and not (label.get_parent() is Container):
			overflow.append("%s: %s 「%s」 高さ %d が必要（枠 %d）" % [file_name, ui.get_path_to(label), label.text.replace("\n", "／"), need.y, label.size.y])
	elif node is Button:
		var button: Button = node
		if button.text != "" and not button.clip_text and button.get_minimum_size().x > button.size.x + 1.0:
			overflow.append("%s: %s 「%s」 幅 %d が必要（枠 %d）" % [file_name, ui.get_path_to(button), button.text.replace("\n", "／"),
				button.get_minimum_size().x, button.size.x])


func _write_overflow() -> void:
	var lines := PackedStringArray(["# 本番UI（UI準備D）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_D.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
	shots.sort()
	lines.append_array(PackedStringArray(shots))
	lines.append("")
	lines.append("## 入りきらない箇所（%d件）" % overflow.size())
	var unique := {}
	for line in overflow:
		unique[line] = true
	lines.append_array(PackedStringArray(unique.keys()))
	var f := FileAccess.open("%s/overflow.txt" % OUT_DIR, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
