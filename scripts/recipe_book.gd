extends RefCounted
class_name RecipeBook
## レシピ保存と「いつもの」（フェーズ4・手順4-7①。DESIGN.md 10.4・10.4.1）。状態は
## GameState.saved_recipes（朝の保存に含む）と来店記録（CustomerMemory）にあり、ここは検証・引き当て・
## 並べ替えの処理だけを持つ静的クラス（読むだけ・乱数なし）。
##
## 保存レシピ：{ name: 候補の名前, ingredients: [具材id…（1〜3）] }、最大 Rules.recipe_slots() 枠（既定3）。
## 名前は data/recipes/names.json の候補（表示だけで性能は変えない。tags は説明用で判定に使わない）。
## 「いつもの」：その客の直近の料理＝今日より前の来店で、評価した杯の最後の具材の並び（断った・未提供・
## 評価なしの杯は飛ばす。今日の来店は含めない）。新しい保存状態は要らない。
## 適用は DebugPanel が「具材ボタンを順に押したのと同じ処理」（_on_ingredient_selected）で行う：在庫・鮮度の
## 確認と消費は省略しない。ここはその前の「全部出せるか」の検査だけを持つ（途中で止まって一部だけ入る
## 状態を作らない）。傷んだ具材は自動では使わない。

const NAMES_PATH := "res://data/recipes/names.json"
const MAX_INGREDIENTS := 3   # OpenController.MAX_ADDITIONS と同じ

static var _names: Array = []
static var _names_loaded := false


## 名前の候補 [{ id, name, tags }]（データから。形の整ったものだけ）。
static func names() -> Array:
	if not _names_loaded:
		_names = []
		if FileAccess.file_exists(NAMES_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(NAMES_PATH))
			if parsed is Dictionary and (parsed as Dictionary).get("names") is Array:
				for item in parsed["names"]:
					if item is Dictionary and (item as Dictionary).get("id") is String \
							and (item as Dictionary).get("name") is String and str(item["name"]) != "":
						var tags := []
						if (item as Dictionary).get("tags") is Array:
							for tag in item["tags"]:
								tags.append(str(tag))
						_names.append({ "id": str(item["id"]), "name": str(item["name"]), "tags": tags })
		_names_loaded = true
	return _names.duplicate(true)


## 候補を並べる：椀の味のタグ（bowl_tags）を候補の tags がすべて含むものを先頭に（データの順）、残りを後ろに。
## 表示の並べ替えだけで、どれでも選べる。
static func names_ordered(bowl_tags: Array) -> Array:
	var matching := []
	var others := []
	for item in names():
		var all_in := not (item["tags"] as Array).is_empty()
		for tag in item["tags"]:
			all_in = all_in and bowl_tags.has(tag)
		if all_in:
			matching.append(item)
		else:
			others.append(item)
	return matching + others


static func slot_count() -> int:
	return Rules.recipe_slots()


## 保存レシピ1件の形（name は空でない文字列、ingredients は1〜3個の空でない文字列）。
static func is_valid_recipe(recipe) -> bool:
	if not (recipe is Dictionary) or not ((recipe as Dictionary).get("name") is String) \
			or str(recipe["name"]) == "" or not ((recipe as Dictionary).get("ingredients") is Array):
		return false
	var ids: Array = recipe["ingredients"]
	if ids.is_empty() or ids.size() > MAX_INGREDIENTS:
		return false
	for id in ids:
		if not (id is String) or id == "":
			return false
	return true


## 枠 slot（0起点）へ保存する。空き枠（保存済みの枠数と同じ番号）なら追加、保存済みの枠なら上書き。
## 枠の範囲外・飛ばした番号・不正なレシピは保存せず false。
static func save(slot: int, recipe_name: String, ingredients: Array) -> bool:
	var recipe := { "name": recipe_name, "ingredients": ingredients.duplicate() }
	if not is_valid_recipe(recipe) or slot < 0 or slot >= slot_count() or slot > GameState.saved_recipes.size():
		return false
	if slot == GameState.saved_recipes.size():
		GameState.saved_recipes.append(recipe)
	else:
		GameState.saved_recipes[slot] = recipe
	return true


## 具材idの並びの表示（"豆腐＋肉団子"）。
static func ingredient_text(ids: Array) -> String:
	var names_text := PackedStringArray()
	for id in ids:
		names_text.append(Ingredients.name_for(str(id)))
	return "＋".join(names_text)


## 具材の並びが持つ味のタグ（重複を除く。表示用）。
static func tags_of(ids: Array) -> Array:
	var tags := []
	for id in ids:
		for tag in Ingredients.tags_for(str(id)):
			if not tags.has(tag):
				tags.append(tag)
	return tags


## その客の「いつもの」＝今日より前の来店で、評価した杯の最後の具材の並び。無ければ空配列。
static func usual_for(customer_id: String) -> Array:
	var visits := CustomerMemory.visits_of(customer_id)
	for i in range(visits.size() - 1, -1, -1):
		var visit: Dictionary = visits[i]
		if int(visit["day"]) >= GameState.day_count:
			continue
		var grades: Array = visit["grades"]
		var cups: Array = visit["ingredients"]
		for j in range(mini(grades.size(), cups.size()) - 1, -1, -1):
			if str(grades[j]) != "" and not (cups[j] as Array).is_empty():
				return (cups[j] as Array).duplicate()
	return []


## 新鮮な在庫で足りない具材のid（重複なし・並びの順）。同じ具材を複数回使う料理はその個数ぶん、
## 名前あり客の注文は1杯の人数（servings）ぶん要る（_on_ingredient_selected が servings 分を引くため）。
## 傷んだ在庫は数えない。
static func shortage(ids: Array, servings: int) -> Array:
	var uses := {}
	for id in ids:
		uses[str(id)] = int(uses.get(str(id), 0)) + 1
	var missing := []
	for id in uses:
		if GameState.fresh_count(id) < int(uses[id]) * maxi(servings, 1):
			missing.append(id)
	return missing


## 適用できるか（具材が1〜3個で、新鮮な在庫からすべて出せる）。椀が空かどうか・ADJUST 中かは呼び出し側。
static func can_apply(ids: Array, servings: int) -> bool:
	return not ids.is_empty() and ids.size() <= MAX_INGREDIENTS and shortage(ids, servings).is_empty()
