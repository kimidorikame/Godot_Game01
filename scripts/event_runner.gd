extends RefCounted
class_name EventRunner
## フェーズ内の Event 列を index で1つずつ進める使い捨て部品。
##
## 設計上の役割分担（DESIGN.md 準拠）:
##   - 進行度（index / status）はここが持つ。GameState には置かない。
##   - Event の種別ごとの処理（apply_money 等）はここではやらない。受ける側の責務。
##   - STEP 1 で解釈するのは「入力待ちか否か」だけ（type == WAIT_INPUT）。
##     残りの Event 型（TEXT / PAY / ADD_ITEM）は STEP 3〜4 で受け側に足す。

enum Status { PLAYING, WAITING_INPUT, DONE }

# 入力待ちを表す Event の type 値。STEP 1.5 で先行して決めた唯一の型。
const TYPE_WAIT_INPUT := "WAIT_INPUT"

var events: Array = []
var index: int = 0
var status: Status = Status.PLAYING


func _init(event_list: Array = []) -> void:
	events = event_list
	reset()


## 先頭に戻す。events はそのまま。
func reset() -> void:
	index = 0
	status = _status_for_index(0)


## 現在の Event。範囲外なら null。
func current() -> Variant:
	if index < 0 or index >= events.size():
		return null
	return events[index]


## 次の Event へ進める。
## 末尾を超えたら DONE。次が入力待ち種別なら WAITING_INPUT、それ以外 PLAYING。
## WAITING_INPUT 中は動かさない（complete_input() を通すこと）。
func advance() -> void:
	if status == Status.DONE or status == Status.WAITING_INPUT:
		return
	index += 1
	status = _status_for_index(index)


## 入力待ちを解除して次へ。WAITING_INPUT のときだけ有効。
func complete_input() -> void:
	if status != Status.WAITING_INPUT:
		return
	status = Status.PLAYING
	advance()


func _status_for_index(i: int) -> Status:
	if i >= events.size():
		return Status.DONE
	if _is_wait_input(events[i]):
		return Status.WAITING_INPUT
	return Status.PLAYING


func _is_wait_input(ev) -> bool:
	return ev is Dictionary and ev.get("type", "") == TYPE_WAIT_INPUT
