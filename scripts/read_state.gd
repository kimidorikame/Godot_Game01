extends RefCounted
class_name ReadState
## 既読の記録（フェーズ4・手順4-7③。DESIGN.md 10.4「既読スキップ」）。
##
## 既読は「その周の状態」ではなく「プレイヤーが見たことがあるか」＝再挑戦（朝へ戻す）や新しい周でも
## 消えない。したがって**朝の保存（MorningSave）には入れない**。CustomerMemory.seen_episodes（場面の
## 選び方に使い、再挑戦で朝の状態に戻る）とは別物。保存先は user://read_state.json
## （{ version, lines:[キー…] }。path で差し替えられる）。メモリ上の集合へ足し、日の終わり・結果画面・
## 終了時に書き出す（1行ごとには書かない。変更が無ければ書かない）。
##
## 行のキー：種別（kind）＋話し手（speaker）＋part＋本文の sha1。本文が差し替わった行（脚本が直った）は
## 未読に戻る。反応（REACT）は、選ばれた反応文の本文で数える。
##
## 試遊（playthroughs.gd）は enabled=false にして、既読ファイルを読まず・書かない（結果が既読の有無で
## 変わらない）。テストは reset(パス) で開始時にメモリ上の集合とパスを初期化する。

const VERSION := 1

static var path := "user://read_state.json"
static var enabled := true

static var _lines: Dictionary = {}
static var _loaded := false
static var _dirty := false


## メモリ上の集合とパスを初期化する（テストの開始時など）。ファイルは読まない（空の集合から始める）。
static func reset(new_path: String = "user://read_state.json", is_enabled: bool = true) -> void:
	path = new_path
	enabled = is_enabled
	_lines = {}
	_loaded = true
	_dirty = false


static func line_key(kind: String, speaker: String, part: String, text: String) -> String:
	return "%s|%s|%s|%s" % [kind, speaker, part, text.sha1_text()]


static func is_read(key: String) -> bool:
	if not enabled:
		return false
	_ensure_loaded()
	return _lines.has(key)


## 既読にする（見えたとき）。新しく足したら true。
static func mark(key: String) -> bool:
	if not enabled:
		return false
	_ensure_loaded()
	if _lines.has(key):
		return false
	_lines[key] = true
	_dirty = true
	return true


static func count() -> int:
	_ensure_loaded()
	return _lines.size()


## 変更があれば書き出す（無効のとき・変更が無いときは書かない）。書いたら true。
static func flush() -> bool:
	if not enabled or not _dirty:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ReadState: failed to open %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({ "version": VERSION, "lines": _lines.keys() }))
	f.close()
	_dirty = false
	return true


## 初回の利用でファイルを読む。無い・壊れている・版が違うときは空の集合から始める。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_lines = {}
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and int((parsed as Dictionary).get("version", 0)) == VERSION \
			and (parsed as Dictionary).get("lines") is Array:
		for key in parsed["lines"]:
			if key is String:
				_lines[key] = true
