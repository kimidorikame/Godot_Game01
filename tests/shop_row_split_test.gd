extends RefCounted
## 市場の店の画面：商品を調味料の行（_seasoning_row）と具材の行（_options_row）に分ける
## （UI変更。判定はIngredients.is_topping()/is_flavor()。dashiは調味料の行）の検証。
## 購入処理・価格・個数・ラベル文面は変えていないので、ここでは「どの行に入るか」と
## 「店を出たあとに残らないこと」だけを見る。
##
## 行のクリアはqueue_free()（フレーム末まで子として残る）なので、行の子を調べるときは
## is_queued_for_deletion()のものを除外する。

# 店 → [調味料の行に入る商品名, 具材の行に入る商品名（「市場に戻る」の前まで）]
const EXPECT := {
	"produce": [["苦瓜"], ["冬瓜"]],
	"meat_wholesale": [["濃縮だし"], ["モツ", "モツ(小口1個)", "軟骨", "すじ肉"]],
	"dry_goods": [["ナムプリックパオ", "ココナッツミルク", "薬膳ナンプラーだれ", "塩漬けライム"], ["乾燥きくらげ"]],
	"tofu_noodles": [[], ["豆腐", "米麺"]],
	"seafood": [[], ["海老", "海老(小口1個)", "貝", "魚の浮き袋"]],
	"scraps": [[], ["割れた餃子皮", "肉団子"]],
}


func _setup(t: SceneTree, money: int):
	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.money = money
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)
	return panel


## 市場（店を選ぶ画面）のMARKETイベントを積み、入力待ちにする。
func _open_market(panel) -> void:
	var stalls := []
	for id in EXPECT:
		stalls.append({ "id": id, "label": id, "enabled": true })
	panel.flow.set_runner([{ "type": "MARKET", "text": "（市場をぶらつく）", "options": stalls }])
	panel._market_shop = ""


## 行の、削除予約されていないボタンの文言。
func _texts(row: HBoxContainer) -> Array:
	var out := []
	for child in row.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Button:
			out.append(str((child as Button).text))
	return out


## 行の、削除予約されていないボタン。
func _buttons(row: HBoxContainer) -> Array:
	var out := []
	for child in row.get_children():
		if not child.is_queued_for_deletion() and child is Button:
			out.append(child)
	return out


## 商品名の並び（label）が、ボタンの文言の先頭（"ラベル（-価格…" 形式）と順に一致するか。
func _matches(texts: Array, labels: Array) -> bool:
	if texts.size() != labels.size():
		return false
	for i in range(labels.size()):
		if not str(texts[i]).begins_with(str(labels[i]) + "（-"):
			return false
	return true


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var panel = _setup(t, 1000)
	_open_market(panel)
	c.check("（前提）市場は入力待ちで、MARKETイベントが現在位置",
		panel.flow.runner.status == EventRunner.Status.WAITING_INPUT and panel._is_in_market())

	# --- 1. 店を選ぶ画面：行は分けない（調味料の行は空。店の一覧と[市場を出る]は具材の行） ---
	panel._update_options_row()
	c.check("店を選ぶ画面では調味料の行は空", _buttons(panel._seasoning_row).is_empty(),
		str(_texts(panel._seasoning_row)))
	c.check("店を選ぶ画面は一覧6店＋[市場を出る]が下の行（具材の行）に並ぶ",
		_texts(panel._options_row).size() == 7 and str(_texts(panel._options_row)[6]) == "市場を出る",
		str(_texts(panel._options_row)))

	# --- 2. 各店：商品が正しい行へ入る。[市場に戻る]は具材の行の末尾 ---
	for shop in EXPECT:
		var want_seasoning: Array = EXPECT[shop][0]
		var want_topping: Array = EXPECT[shop][1]
		panel._on_market_stall_selected(shop)
		panel._update_options_row()
		var seasoning := _texts(panel._seasoning_row)
		var options := _texts(panel._options_row)
		c.check("%s：調味料の行は期待どおり" % shop, _matches(seasoning, want_seasoning),
			"%s != %s" % [str(seasoning), str(want_seasoning)])
		var topping_part := options.slice(0, maxi(options.size() - 1, 0))
		c.check("%s：具材の行は期待どおり（末尾は[市場に戻る]）" % shop,
			_matches(topping_part, want_topping) and not options.is_empty()
				and str(options[options.size() - 1]) == "市場に戻る",
			"%s != %s" % [str(options), str(want_topping)])
		var goods: Array = panel._shop_goods(shop)
		c.check("%s：商品の件数が2行の合計と一致する（ボタンの重複・欠落なし）" % shop,
			goods.size() == seasoning.size() + topping_part.size(),
			"%d != %d+%d" % [goods.size(), seasoning.size(), topping_part.size()])
		panel._on_shop_exit_pressed()   # 店を出る（_market_shop=""・再描画）
		panel._update_options_row()
		c.check("%s：店を出ると調味料の行に商品が残らない" % shop,
			_buttons(panel._seasoning_row).is_empty(), str(_texts(panel._seasoning_row)))

	# --- 3. 乾物調味料の店：調味料4種とも調味料の行・きくらげは具材の行（念のため行の実体で） ---
	panel._on_market_stall_selected("dry_goods")
	panel._update_options_row()
	c.check("乾物調味料：調味料の行は4種", _buttons(panel._seasoning_row).size() == 4)
	c.check("乾物調味料：具材の行はきくらげ＋[市場に戻る]", _buttons(panel._options_row).size() == 2)

	# --- 4. 表示のみの変更：所持金が足りない商品は従来どおり無効化される ---
	GameState.money = 30
	panel._update_options_row()
	var disabled_by_label := {}
	for row in [panel._seasoning_row, panel._options_row]:
		for btn in _buttons(row):
			disabled_by_label[str(btn.text).split("（")[0]] = btn.disabled
	c.check("きくらげ（50）は所持金30で無効・ナムプリックパオ（25）は有効",
		bool(disabled_by_label["乾燥きくらげ"]) and not bool(disabled_by_label["ナムプリックパオ"]),
		str(disabled_by_label))
	c.check("[市場に戻る]は常に押せる", not bool(disabled_by_label["市場に戻る"]))

	# --- 5. 購入処理は変えていない（調味料の行のボタンでも従来どおり買える） ---
	GameState.money = 100
	var stock_before := int(GameState.inventory.get("pickled_lime", 0))
	panel._on_shop_item_selected("dry_goods", "pickled_lime")
	c.check("塩漬けライムの購入：所持金-20・在庫+5",
		GameState.money == 80 and int(GameState.inventory.get("pickled_lime", 0)) == stock_before + 5,
		"money=%d stock=%d" % [GameState.money, int(GameState.inventory.get("pickled_lime", 0))])

	# --- 6. 店の画面から別のコンテキストへ移ると、店の商品は両方の行から消える ---
	panel._update_options_row()
	c.check("（前提）店の画面では両方の行に商品がある",
		not _buttons(panel._seasoning_row).is_empty() and not _buttons(panel._options_row).is_empty())
	panel.flow.set_runner([])   # 別のフェーズ・コンテキスト（イベント無し）へ
	panel._market_shop = ""
	panel._update_options_row()
	c.check("別の画面へ移ると調味料の行・具材の行とも空",
		_buttons(panel._seasoning_row).is_empty() and _buttons(panel._options_row).is_empty(),
		"%s / %s" % [str(_texts(panel._seasoning_row)), str(_texts(panel._options_row))])

	GameState.reset_for_new_game()
	if is_instance_valid(panel):
		panel.free()
	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
