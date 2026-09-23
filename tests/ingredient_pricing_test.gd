extends RefCounted
## ①具材の購入単位（BALANCE_REDESIGN_PLAN.md §3）の検証。対象は価格・購入単位・
## モツ/海老の小口購入・ロットごとの実際に払った単価だけ。経済数値のうち評判・客数・
## 仕込み量・鍋容量・判定ロジック本体（judge_bowl）は変更していないことも合わせて確認する。

## 17品目＋小口2件（モツ・海老）。"item"が在庫id、"count"が1回の購入で増える個数。
const _BUTTONS := [
	{ "shop": "produce", "id": "winter_melon", "item": "winter_melon", "price": 50, "count": 5 },
	{ "shop": "produce", "id": "bitter_melon", "item": "bitter_melon", "price": 12, "count": 3 },
	{ "shop": "meat_wholesale", "id": "offal", "item": "offal", "price": 30, "count": 3 },
	{ "shop": "meat_wholesale", "id": "offal_single", "item": "offal", "price": 12, "count": 1 },
	{ "shop": "meat_wholesale", "id": "cartilage", "item": "cartilage", "price": 24, "count": 3 },
	{ "shop": "meat_wholesale", "id": "tendon_meat", "item": "tendon_meat", "price": 36, "count": 3 },
	{ "shop": "dry_goods", "id": "nam_prik_pao", "item": "nam_prik_pao", "price": 25, "count": 5 },
	{ "shop": "dry_goods", "id": "coconut_milk", "item": "coconut_milk", "price": 15, "count": 3 },
	{ "shop": "dry_goods", "id": "herbal_sauce", "item": "herbal_sauce", "price": 25, "count": 5 },
	{ "shop": "dry_goods", "id": "pickled_lime", "item": "pickled_lime", "price": 20, "count": 5 },
	{ "shop": "dry_goods", "id": "dried_wood_ear", "item": "dried_wood_ear", "price": 50, "count": 5 },
	{ "shop": "tofu_noodles", "id": "tofu", "item": "tofu", "price": 24, "count": 3 },
	{ "shop": "tofu_noodles", "id": "rice_noodle", "item": "rice_noodle", "price": 40, "count": 5 },
	{ "shop": "seafood", "id": "shrimp", "item": "shrimp", "price": 54, "count": 3 },
	{ "shop": "seafood", "id": "shrimp_single", "item": "shrimp", "price": 20, "count": 1 },
	{ "shop": "seafood", "id": "clam", "item": "clam", "price": 48, "count": 3 },
	{ "shop": "seafood", "id": "fish_maw", "item": "fish_maw", "price": 100, "count": 5 },
	{ "shop": "scraps", "id": "broken_wrapper", "item": "broken_wrapper", "price": 18, "count": 3 },
	{ "shop": "scraps", "id": "meat_ball", "item": "meat_ball", "price": 24, "count": 3 },
]


func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が自動でinitial_inventory()を積む
	GameState.inventory.clear()
	GameState.perishable_batches.clear()
	GameState.money = 100000   # どのボタンを何回押しても足りるだけの所持金
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. 19ボタン(17品目+小口2件)すべてで価格・購入単位・所持金・在庫・単価が目標どおり ---
	var panel = _setup(t)
	for btn in _BUTTONS:
		var before_money: int = GameState.money
		var before_inv: int = int(GameState.inventory.get(btn["item"], 0))
		panel._on_shop_item_selected(btn["shop"], btn["id"])
		c.check("%s: 所持金が%dだけ減る" % [btn["id"], btn["price"]],
			GameState.money == before_money - int(btn["price"]), "money=%d" % GameState.money)
		c.check("%s: 在庫(%s)が%d個増える" % [btn["id"], btn["item"], btn["count"]],
			int(GameState.inventory.get(btn["item"], 0)) == before_inv + int(btn["count"]),
			str(GameState.inventory.get(btn["item"], 0)))
		if Ingredients.is_perishable(str(btn["item"])):
			var batches: Array = GameState.perishable_batches.get(btn["item"], [])
			var expected_unit_price: int = int(btn["price"]) / int(btn["count"])
			c.check("%s: 直近バッチの単価が%d" % [btn["id"], expected_unit_price],
				not batches.is_empty() and int(batches[-1]["unit_price"]) == expected_unit_price,
				str(batches))

	# --- 2. モツ：パック購入→小口購入で別々の単価のバッチとして記録される
	#    (「小口の海老20を消費した原価を18と数えない」§3原文と同じ理屈をモツで検証) ---
	panel = _setup(t)
	panel._on_shop_item_selected("meat_wholesale", "offal")          # パック: 3個・単価10
	panel._on_shop_item_selected("meat_wholesale", "offal_single")   # 小口: 1個・単価12
	var offal_batches: Array = GameState.perishable_batches.get("offal", [])
	c.check("モツ：パック購入+小口購入で2つの別バッチになる", offal_batches.size() == 2, str(offal_batches))
	c.check("モツ：1つ目のバッチは単価10・3個",
		int(offal_batches[0]["unit_price"]) == 10 and int(offal_batches[0]["count"]) == 3, str(offal_batches))
	c.check("モツ：2つ目のバッチは単価12・1個",
		int(offal_batches[1]["unit_price"]) == 12 and int(offal_batches[1]["count"]) == 1, str(offal_batches))
	c.check("モツ：在庫合計は4個", int(GameState.inventory.get("offal", 0)) == 4)

	# --- 3. 同日・同じ単価のパック購入を2回行うと1つのバッチに合算される(既存動作の回帰) ---
	panel = _setup(t)
	panel._on_shop_item_selected("meat_wholesale", "offal")
	panel._on_shop_item_selected("meat_wholesale", "offal")
	var merged_batches: Array = GameState.perishable_batches.get("offal", [])
	c.check("モツ：同日・同単価のパック購入2回は1バッチに合算される",
		merged_batches.size() == 1 and int(merged_batches[0]["count"]) == 6, str(merged_batches))

	# --- 4. パック購入分を4日目まで放置して破棄すると、廃棄額は実際に払った額と一致する ---
	panel = _setup(t)
	panel._on_shop_item_selected("meat_wholesale", "offal")   # 3個・単価10 → 30円分
	GameState.day_count = 4
	var spoiled: Dictionary = GameState.discard_spoiled_inventory()
	c.check("モツ(パック購入)の廃棄額は実際に払った30円",
		int(spoiled.get("offal", {}).get("value", -1)) == 30, str(spoiled))

	# --- 5. 初期在庫(無料)が腐って破棄されても、廃棄額は0円 ---
	panel = _setup(t)
	panel._seed_initial_inventory()
	GameState.day_count = 4
	var spoiled_free: Dictionary = GameState.discard_spoiled_inventory()
	var free_perishable_found := false
	for id in spoiled_free:
		free_perishable_found = true
		c.check("初期在庫(%s)は無料なので廃棄額0" % id,
			int(spoiled_free[id].get("value", -1)) == 0, str(spoiled_free))
	c.check("初期在庫の腐る品目が少なくとも1つ検証できた(前提の崩れ検知)", free_perishable_found)

	# --- 6. すじ肉はPOWER・BITEどちらの要求タグにも一致する(judge_bowlは無改修の回帰) ---
	GameState.reset_for_new_game()
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	var open := OpenController.new([])
	open.current_bowl = { "additions": ["tendon_meat"] }
	var result := open.judge_bowl(["POWER", "BITE"])
	c.check("すじ肉1つでPOWER+BITEの要求2つに一致してGOODになる", result == "GOOD", result)

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
