extends PanelContainer
## STEP 17: 客一人分の簡易夜営業画面（Graybox）。DESIGN.md 9.5 STEP 17。
##
## 目的は操作感（会話の間・テンポ・客の存在感）の確認。完成UI・立ち絵・演出は作らない。
## DebugPanel は検証用としてそのまま残す（この画面とは別シーン・無改修）。
##
## 対象は OPEN の接客のみ、客は delivery_man 固定（他の客で試したいときは
## CUSTOMER_ID を書き換える）。FlowController は使わない（フェーズ概念が不要）。
## 単体シーンとして直接実行できるよう、PREP を経由せずその場で最低限の鍋を作る。
##
## 表示するのは：セリフ / 客の姿を置く領域 / 味付けボタン / 反応 / 鍋の状態 だけ。
## 所持金・提供数・index・status・events数・final_tags・判定の生値は出さない
## （判定結果は客の反応textの内容差だけで伝える）。椀の中身（additions）も出さない
## （今は具材のON/OFFだけなので忘れようがない、という判断）。

const CUSTOMER_ID := "delivery_man"

@onready var _soup_label: Label = $Margin/VBox/SoupLabel as Label
@onready var _customer_label: Label = $Margin/VBox/CustomerBox/CustomerLabel as Label
@onready var _dialogue_label: Label = $Margin/VBox/DialogueLabel as Label
@onready var _options_row: HBoxContainer = $Margin/VBox/OptionsRow as HBoxContainer
@onready var _btn_send: Button = $Margin/VBox/BtnSend as Button

var _open: OpenController
var _runner: EventRunner


func _ready() -> void:
	if GameState.soup == null:
		GameState.set_soup("bone_broth", ["meaty"])
	_open = OpenController.new([CUSTOMER_ID])
	_runner = EventRunner.new(Day1Events.customer_events(str(_open.current_customer())))
	_btn_send.pressed.connect(_on_send_pressed)
	_customer_label.text = CUSTOMER_ID
	_refresh()


## [送る] のハンドラ。PLAYING中のみ押せる（WAITING_INPUT中はボタン自体を隠す）。
func _on_send_pressed() -> void:
	var before := _runner.index
	_runner.advance()
	if _runner.index != before:
		_apply_event(_runner.current())
	_refresh()


## ADJUST の選択肢ボタンのハンドラ。椀へ反映してから入力完了で1つ進める。
func _on_option_selected(ingredient_id: String) -> void:
	_open.add_to_bowl(ingredient_id)
	var before := _runner.index
	_runner.complete_input()
	if _runner.index != before:
		_apply_event(_runner.current())
	_refresh()


## DebugPanelの_apply_eventのOPEN部分と同一ロジック。本番UI着手時にController分離を検討
## （CURRENT_SPEC.md 1章）。Graybox は客一人分・OPENのみが対象なので、GREET/ADJUST/SERVE
## は表示だけ（何もしない）。REACT だけ judge_bowl → apply_money → record_served を行う。
## Event（text / text_miss）はここでも書き換えない。
func _apply_event(ev) -> void:
	if not (ev is Dictionary):
		return
	if ev.get("type", "") == "REACT":
		var sale := int(ev.get("sale", 0))
		_open.judge_bowl(ev.get("wanted_tags", []))
		GameState.apply_money(sale)
		GameState.record_served({ "customer": ev.get("customer", ""), "sale": sale })


func _refresh() -> void:
	_soup_label.text = _format_soup()
	_dialogue_label.text = _current_dialogue_text()
	_update_options_row()
	_btn_send.visible = _runner.status == EventRunner.Status.PLAYING


func _format_soup() -> String:
	if GameState.soup == null:
		return "鍋: (まだ無い)"
	return "鍋: %s tags=%s" % [GameState.soup.get("base_id", "?"), str(GameState.soup.get("tags", []))]


## DebugPanelの_current_reaction_textと同一ロジック。本番UI着手時にController分離を検討
## （CURRENT_SPEC.md 1章）。GREET/ADJUST/SERVEはev.textそのまま、REACTは判定結果に応じて
## text/text_missを選ぶ（Eventは書き換えない）。runnerがDONE（現在Eventが無い）ときは
## 終了メッセージを返す。
func _current_dialogue_text() -> String:
	var cur = _runner.current()
	if cur == null:
		return "（この客の接客は以上です）"
	if not (cur is Dictionary):
		return ""
	if cur.get("type", "") == "REACT" and _open.current_bowl.get("result", "") == "MISS":
		return str(cur.get("text_miss", cur.get("text", "")))
	return str(cur.get("text", ""))


## ADJUST の選択肢ボタンを描画。DebugPanelの_update_options_rowと同じ発想
## （optionsを持つWAITING_INPUTのときだけ、件数を問わず並べる）。
func _update_options_row() -> void:
	for child in _options_row.get_children():
		child.queue_free()
	if _runner.status != EventRunner.Status.WAITING_INPUT:
		return
	var cur = _runner.current()
	if not (cur is Dictionary) or not cur.has("options"):
		return
	for option in cur["options"]:
		var btn := Button.new()
		btn.text = str(option.get("label", option.get("id", "?")))
		btn.pressed.connect(_on_option_selected.bind(str(option.get("id", ""))))
		_options_row.add_child(btn)
