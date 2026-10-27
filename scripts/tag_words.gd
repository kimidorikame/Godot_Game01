extends RefCounted
class_name TagWords
## タグ（内部名）→ 画面に出す言葉（UI準備F）。データは data/tag_words.json（flavor＝味の軸／topping＝具の軸）。
## 表示だけ：判定（Judge）・SaleRule・保存・ログ・自動試遊は内部名（HOT 等）のまま。静的クラスで状態は持たない（読むだけ・乱数なし）。

const PATH := "res://data/tag_words.json"
const KINDS := ["flavor", "topping"]

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache = {}


static func data() -> Dictionary:
	if _cache.is_empty() and FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_cache = parsed
	return _cache


## タグの言葉。知らないタグ（データに無い）は内部名のまま返す（空にはしない）。
static func word(tag: String) -> String:
	for kind in KINDS:
		var group = data().get(kind, {})
		if group is Dictionary and (group as Dictionary).has(tag):
			return str((group as Dictionary)[tag])
	return tag


## タグの軸："flavor"（味）か "topping"（具）。データに無ければ ""。
static func kind(tag: String) -> String:
	for k in KINDS:
		var group = data().get(k, {})
		if group is Dictionary and (group as Dictionary).has(tag):
			return k
	return ""


## タグの並びを言葉の並びにする。
static func words(tags: Array) -> Array:
	var out: Array = []
	for tag in tags:
		out.append(word(str(tag)))
	return out


## タグの並びを「辛い・スタミナ」の形の文字列にする（札を作らない場面の文字・テスト用）。
static func joined(tags: Array, separator: String = "・") -> String:
	return separator.join(PackedStringArray(words(tags)))


## データにある全タグ（味→具の並び）。
static func all_tags() -> Array:
	var out: Array = []
	for k in KINDS:
		var group = data().get(k, {})
		if group is Dictionary:
			for tag in group:
				out.append(str(tag))
	return out
