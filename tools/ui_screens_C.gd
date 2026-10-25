# 本番UI（UI準備C）のスクリーンショットを撮る（1280×720のPNGを planning/ui_screens_C/ へ。UI準備Bの13枚に、
# 客足・足りなかった杯数の内訳・DM・張記の会話・鍋を触れる状態の状態を足したもの）。
# ウィンドウありで起動する（ヘッドレスでは描画されない。一瞬ウィンドウが出る）：
#   godot --path . --resolution 1280x720 --script res://tools/ui_screens_C.gd
# 遊び方は UIの通しテストと同じ台本（tests/ui_autoplay.gd。ボタンと会話枠のクリックだけ）。傷んだ在庫・鍋が尽きた保留・
# ゲームオーバー・足りなかった杯数の内訳の数・DMの匂わせが出る需要の中心は、撮るためにスクリプトで状態を作る
# （ゲームの数値の検証ではない。スクリーンショットの説明に「仮の状態」と書く）。
# あわせて、文字が枠に入りきらないラベル・ボタンを planning/ui_screens_C/overflow.txt に書き出す。
# セーブ・既読・日次ログは、実際のファイルと別の user://ui_screens_* に書く。
extends SceneTree

const OUT_DIR := "res://planning/ui_screens_C"

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
	play = load("res://tests/ui_autoplay.gd").new(ui)
	var s = ui.session

	# Day1 の張記の会話（鍋の素を選ぶ直前。主人公が目安の杯数を一度だけ言う）
	_until(func(): return str(s.current_line().get("part", "")) == "prep_talk" and str(s.current_line().get("text", "")).contains("最初の晩"))
	await _shot("18_prep_talk_day1", "張記の会話・Day1（主人公が目安の杯数を言う）")
	# Day1 をUIだけで遊び、Day2 の朝（昨夜の成績）
	_until(func(): return gs.day_count == 2 and gs.phase == gs.Phase.WAKE and ui.pane_morning.visible)
	# 撮るための状態：足りなかった杯数の内訳（素材1・鍋1・断った1・来られなかった1＝画面では「鍋 2」）
	var previous: Dictionary = gs.day_records[gs.day_records.size() - 1]
	previous["unserved_cups"] = 4
	previous["unserved_ingredients"] = 1
	previous["unserved_pot"] = 1
	previous["unserved_declined"] = 1
	previous["unserved_not_arrived"] = 1
	s.notify_changed()
	await _shot("01_morning", "朝（昨夜の成績。足りなかった杯数の内訳の数は撮るための仮の状態）")
	# 入力待ち「スマホを見る。」まで会話を進め、「スマホを見る」→ スマホ（ニュース）
	_until(func(): return s.is_waiting_input(), func(): play.click(ui.left.get_node("%DialogueBox")))
	play.press(ui.pane_morning.get_node("%PrimaryButton"))
	await _shot("02_phone", "スマホ（ニュース）")
	play.press(ui.pane_phone.get_node("%Tabs").get_child(0))
	await _shot("14_sns_dm", "スマホ（SNS＝DM。Day2。開いた時点で未読だった行は左に注意色の線）")
	play.press(ui.pane_phone.get_node("%CloseButton"))
	# 張記の会話（Day2：前日の事実だけ）
	_until(func(): return str(s.current_line().get("part", "")) == "prep_talk" and str(s.current_line().get("text", "")).contains("昨日"))
	await _shot("17_prep_talk", "張記の会話・Day2（前日の注文の杯数と足りなかった杯数だけ）")
	# 仕込み：張記で中を買う
	_until(func(): return ui.pane_buy_meat.visible and s.is_in_prep_tier())
	play.press(ui.pane_buy_meat.get_node("%Tiers").get_child(1))
	await _shot("04_buy_meat", "購入（張記。中を買ったあと）")
	# 市場：豆腐屋で豆腐を買う → 市場に戻る
	_until(func(): return ui.pane_market.visible)
	play.press(ui.pane_market.get_node("%Stalls").get_child(3))
	play.press(ui.pane_buy_shop.get_node("%Goods").get_child(0).get_node("BuyButton"))
	await _shot("05_buy_tofu", "購入（福生豆腐麺房。豆腐を1回買ったあと）")
	play.press(ui.pane_buy_shop.get_node("%BackButton"))
	await _shot("03_market", "市場（店選び）")
	# 仕込み（全面）
	play.press(ui.pane_market.get_node("%ExitButton"))
	play.click(ui.full_prep)
	await _shot("11_prep", "仕込み（全面）")
	# 撮るための状態：傷んだ豆腐を2つ（購入日を2日前にする）
	gs.inventory["tofu"] = int(gs.inventory.get("tofu", 0)) + 2
	var batches: Array = gs.perishable_batches.get("tofu", [])
	batches.push_front({ "day": gs.day_count - 2, "count": 2, "unit_price": 8 })
	gs.perishable_batches["tofu"] = batches
	# 開店：最初の客を待つ鍋
	_until(func(): return gs.phase == gs.Phase.OPEN and ui.pane_kaiten.pot.visible)
	await _shot("06_kaiten_pot", "開店の鍋")
	# 名前あり客の椀：傷んだ豆腐＋調味料（減点の予告）
	_until(func(): return ui.pane_kaiten.topping.visible and ui.pane_kaiten.topping.is_adjusting() and s.can_reask())
	var top = ui.pane_kaiten.topping
	for item in top.get_node("%Grid").get_children():
		if item.visible and item.get_node("MainButton/Name").text == "豆腐":
			play.press(item.get_node("DamagedButton"))
	var tabs: HBoxContainer = top.get_node("%Tabs")
	play.press(tabs.get_child(tabs.get_child_count() - 1))
	play.press(top.get_node("%Grid").get_child(0).get_node("MainButton"))
	await _shot("07_kaiten_topping", "開店のトッピング（傷んだ在庫あり・減点の予告あり）")
	# モブの団体の確認（今夜のモブで。来なければ次の日以降で撮る）
	_until(func(): return top.visible and top.get_node("%GroupBox").visible)
	await _shot("09_mob_group", "モブの団体の確認")
	# 鍋が尽きた保留：次の名前あり客の提供の直後に、鍋を空にする
	_until(func(): return s.is_awaiting_react() and not s.is_current_mob_order())
	gs.soup["remaining_servings"] = 0
	_until(func(): return s.is_shortage_pending(), func(): play.click(ui.left.get_node("%DialogueBox")))
	await _shot("08_shortage", "鍋が尽きた保留")
	# 閉店：語りを読み終えて、基金に +10
	_until(func(): return gs.phase == gs.Phase.CLOSE and s.flow.is_runner_done())
	play.press(ui.pane_close.get_node("%Steps").get_child(0))
	# 撮るための状態：足りなかった杯数の内訳（素材1・鍋2・断った1・来られなかった1）
	s.log_unserved = { "ingredients": 1, "pot": 2, "declined": 1 }
	s.log_planned_cups = int(s.tonight_totals()["served_cups"]) + 5
	s.notify_changed()
	await _shot("10_close", "閉店（今夜の結果と修繕基金。足りなかった杯数の内訳の数は撮るための仮の状態）")
	# Day3 の朝：DMの匂わせ（需要の中心を撮るために仮に置く。多い日・少ない日）
	play.press(ui.pane_close.get_node("%NextButton"))
	_until(func(): return gs.day_count == 3 and gs.phase == gs.Phase.WAKE)
	var real_center: int = int(gs.today_plan["demand_center"])
	gs.today_plan["demand_center"] = 14
	ui.open_phone("sns")
	await _shot("15_sns_hint_many", "スマホ（SNS。Day3。需要の中心を14に置いた仮の状態：匂わせ many のDMが届く）")
	gs.today_plan["demand_center"] = 7
	s.notify_changed()
	await _shot("16_sns_hint_few", "スマホ（SNS。Day3。需要の中心を7に置いた仮の状態：匂わせ few のDMが届く）")
	gs.today_plan["demand_center"] = real_center
	ui.close_overlay()
	# Day7 の朝：DMが多い日（今日までに届いたDMがたまる。一覧は縦にスクロールできる）
	_until(func(): return gs.day_count == 7 and gs.phase == gs.Phase.WAKE)
	ui.open_phone("sns")
	await _shot("19_sns_day7", "スマホ（SNS。Day7。DMが多い日。一覧は縦にスクロールできる。%d通）" % s.phone_dm().size())
	ui.close_overlay()
	# 最終日の結果まで遊ぶ
	_until(func(): return ui.full_result.visible, Callable(), 20000)
	await _shot("12_result", "結果（全面・1ページ目）")
	# ゲームオーバー：新しい周の Day1 の閉店で所持金を減らし、翌朝の運営費が払えない
	play.press(ui.full_result.get_node("%Tabs").get_child(2))
	play.press(ui.full_result.get_node("%NewRunButton"))
	_until(func(): return gs.phase == gs.Phase.CLOSE and s.flow.is_runner_done())
	gs.money = 20
	play.press(ui.pane_close.get_node("%NextButton"))
	await _shot("13_gameover", "ゲームオーバー（全面）")

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
	var lines := PackedStringArray(["# 本番UI（UI準備C）スクリーンショットの一覧と、文字が枠に入りきらない箇所",
		"# tools/ui_screens_C.gd が書き出す（手で直さない）", "", "## スクリーンショット"])
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
