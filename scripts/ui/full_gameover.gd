extends Control
class_name UiFullGameOver
## 全面：ゲームオーバー。寸法表 SCREENS_UI_LAYOUT §8。
## 何日目のどこで何が払えなかったかと所持金（game_over_info()）。
## 「Day N の朝からやり直す」：戻れる朝があれば retry()（最後の朝）、無ければ run_again()（Day1の朝から。記録が無ければ新しい周）。
## 「終わる」はタイトル画面（フェーズ6）まで押せない。

const KIND_LABELS := { "daily_cost": "水と炭（運営費）", "water": "水道代", "rent": "場所代", "kit": "初日セット" }
const PHASE_LABELS := { GameState.Phase.WAKE: "朝", GameState.Phase.PREP: "市場", GameState.Phase.OPEN: "営業中",
	GameState.Phase.CLOSE: "閉店" }

var session: PlaySession = null

@onready var _detail: Label = %Detail
@onready var _retry: Button = %RetryButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	_retry.pressed.connect(_on_retry_pressed)


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	var info := session.game_over_info()
	if bool(info["available"]):
		var kind := str(KIND_LABELS.get(str(info["kind"]), "支払い"))
		var where := str(PHASE_LABELS.get(int(info["phase"]), ""))
		_detail.text = "Day %d の%sに、%s ¥%d が払えなかった。\n所持金 ¥%d" % [int(info["day"]), where, kind,
			int(info["amount"]), int(info["money"])]
	else:
		_detail.text = "所持金 ¥%d" % GameState.money
	var exits := session.exits()
	_retry.text = "Day %d の朝からやり直す" % retry_day()
	_retry.disabled = not (bool(exits["can_retry"]) or bool(exits["can_run_again"]))
	_quit.disabled = true   # タイトル画面はフェーズ6


## 「やり直す」で戻る朝の日：retry() が戻る先＝戻れる最後の朝（GameState.latest_morning と同じ日）。
## 運営費が払えなかった朝は記録されないので、朝に詰んだときは前日の朝になる（Day3の朝に払えない→2）。
## 朝の記録が1つも無ければ1（run_again＝Day1の朝から。記録が無いので新しい周と同じ動作）。
func retry_day() -> int:
	if bool(session.exits()["can_retry"]):
		return int(GameState.morning_snapshots.keys().max())
	return 1


func _on_retry_pressed() -> void:
	if bool(session.exits()["can_retry"]):
		session.retry()
	elif bool(session.exits()["can_run_again"]):
		session.run_again()
