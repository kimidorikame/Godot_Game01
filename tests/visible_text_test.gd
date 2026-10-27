extends RefCounted
## プレイヤーに見えるテキストに、タグの内部名（MELLOW・HOT・SOUR・BITTER・SAVORY・FILLING・POWER・GENTLE・BITE・TREAT）が
## 残っていないこと（UI準備F2）。見る場所：
##   ・data/ の台詞・DM・ニュース・日程などの文（data/tag_words.json・data/recipes・タグそのものの値＝配列の要素は除く）
##   ・scenes/ui/*.tscn のラベル・ボタンの文字
##   ・本番UI（UiGameRoot）の全部のラベル・ボタン・RichTextLabel の文字（Day1の開店中と、Day2の営業中で見る）
## DebugPanel（開発用の仮画面）は対象外。タグそのものの値（"HOT" だけの文字列＝判定・保存の内部名）も対象外。

const TAGS := ["MELLOW", "HOT", "SOUR", "BITTER", "SAVORY", "FILLING", "POWER", "GENTLE", "BITE", "TREAT"]
const SKIP_FILES := ["res://data/tag_words.json", "res://data/recipes/names.json"]


func _regex() -> RegEx:
	var re := RegEx.new()
	re.compile("\\b(%s)\\b" % "|".join(PackedStringArray(TAGS)))
	return re


## JSON の値の中の文字列を集める。内部名そのもの（タグの値）と、"_" で始まるキー（メモ）は数えない。
func _strings(value, out: Array, path: String) -> void:
	if value is String:
		if not TAGS.has(value):
			out.append([path, value])
	elif value is Array:
		for i in range(value.size()):
			_strings(value[i], out, "%s[%d]" % [path, i])
	elif value is Dictionary:
		for key in value:
			if str(key).begins_with("_"):
				continue
			_strings(value[key], out, "%s.%s" % [path, key])


func _json_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_json_files("%s/%s" % [dir_path, sub], out)
	for file in dir.get_files():
		if file.ends_with(".json"):
			out.append("%s/%s" % [dir_path, file])


func _all_texts(node: Node, out: Array) -> void:
	if node is RichTextLabel:
		out.append([str(node.name), (node as RichTextLabel).text])
	elif node is Label:
		out.append([str(node.name), (node as Label).text])
	elif node is Button:
		out.append([str(node.name), (node as Button).text])
	for child in node.get_children():
		_all_texts(child, out)


func _first_hit(rows: Array, re: RegEx) -> String:
	for row in rows:
		if re.search(str(row[1])) != null:
			return "%s: %s" % [row[0], str(row[1]).left(60)]
	return ""


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	var re := _regex()
	var probe := re.search("警官（SOUR/BITE）")
	c.check("（前提）内部名の検出が働く（SOUR/BITE を見つける・「酸っぱい」は見つけない）", probe != null and re.search("警官（酸っぱい・歯ごたえ）") == null)

	# --- 1. data/ の文 ---
	var files: Array = []
	_json_files("res://data", files)
	var bad := ""
	var checked := 0
	for path in files:
		if SKIP_FILES.has(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		var rows: Array = []
		_strings(parsed, rows, path.get_file())
		checked += rows.size()
		var hit := _first_hit(rows, re)
		if hit != "" and bad == "":
			bad = "%s %s" % [path, hit]
	c.check("data/ の文（%d個）に内部名が残っていない（台詞・DM・ニュース・日程）" % checked, bad == "" and checked > 100, bad)

	# --- 2. scenes/ui/*.tscn の文字 ---
	var scene_bad := ""
	var dir := DirAccess.open("res://scenes/ui")
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			for line in FileAccess.get_file_as_string("res://scenes/ui/" + file).split("\n"):
				if line.begins_with("text = ") and re.search(line) != null and scene_bad == "":
					scene_bad = "%s: %s" % [file, line]
	c.check("scenes/ui の文字に内部名が残っていない", scene_bad == "", scene_bad)

	# --- 3. 本番UIの全部の文字 ---
	GameState.reset_for_new_game()
	var root: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root)
	var rows1: Array = []
	_all_texts(root, rows1)
	var guard := 0
	while root.session.flow.runner != null and root.session.flow.runner.status == EventRunner.Status.PLAYING and guard < 60:
		guard += 1
		root.left.advance()
		_all_texts(root, rows1)
	c.check("本番UI（Day1の開店）の全部のラベル・ボタン（%d個）に内部名が残っていない" % rows1.size(), _first_hit(rows1, re) == "" and rows1.size() > 50, _first_hit(rows1, re))
	root.queue_free()

	GameState.reset_for_new_game()
	GameState.day_count = 2
	GameState.reputation = 65
	var root2: UiGameRoot = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(root2)
	var s: PlaySession = root2.session
	GameState.inventory.clear()
	for id in ["offal", "nam_prik_pao", "tendon_meat", "tofu", "shrimp"]:
		GameState.add_inventory(id, 3)
	GameState.set_soup("bone_broth", ["meaty"], 999, 3, 2)
	GameState.phase = GameState.Phase.OPEN
	s.open = OpenController.new([{ "name": "宵の口", "customers": ["officer", "granny"] }])
	s.load_current_customer()
	root2.close_overlay()
	s.notify_changed()
	var rows2: Array = []
	guard = 0
	while s.flow.runner.status == EventRunner.Status.PLAYING and guard < 40:
		guard += 1
		root2.left.advance()
		_all_texts(root2, rows2)
	root2.pane_kaiten.topping.refresh()
	_all_texts(root2, rows2)
	c.check("本番UI（Day2の営業中・名前あり客）の全部のラベル・ボタン（%d個）に内部名が残っていない" % rows2.size(), _first_hit(rows2, re) == "", _first_hit(rows2, re))
	root2.queue_free()

	return c.finish()
