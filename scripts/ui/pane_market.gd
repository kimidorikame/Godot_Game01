extends Panel
class_name UiPaneMarket
## 右の枠：市場（店選び）。寸法表 SCREENS_UI_LAYOUT §4。
## 店の一覧は market_stalls()（市場の画面＝MARKET にいるときだけ入っている）。閉まっている店は薄く押せない。
## 鍋の素を買った店（張記）は強調色の枠と「鍋の素 中11杯 買った」（today_base()）。ほかの店は「¥24 使った」（UIの集計）。
## 店を押す → select_stall(id)。「市場を出る」→ exit_market()（can_exit_market() のとき）。

var session: PlaySession = null
var tally: UiShopTally = null

@onready var _header: Control = %Header
@onready var _budget: Control = %Budget
@onready var _stalls: VBoxContainer = %Stalls
@onready var _exit: Button = %ExitButton


func _ready() -> void:
	_exit.pressed.connect(_on_exit_pressed)
	for i in range(_stalls.get_child_count()):
		(_stalls.get_child(i) as Button).pressed.connect(_on_stall_pressed.bind(i))


func bind_session(s: PlaySession) -> void:
	session = s


func refresh() -> void:
	if session == null:
		return
	UiParts.set_header(_header, "市場", "Day %d" % GameState.day_count)
	UiParts.set_budget(_budget, session.budget())
	var stalls := session.market_stalls()
	var base := session.today_base()
	for i in range(_stalls.get_child_count()):
		var row: Button = _stalls.get_child(i)
		row.visible = i < stalls.size()
		if i >= stalls.size():
			continue
		var stall: Dictionary = stalls[i]
		var id := str(stall["id"])
		var enabled := bool(stall["enabled"])
		row.disabled = not enabled
		row.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.45)   # 閉まっている店は薄く
		(row.get_node("Name") as Label).text = UiLabels.shop_name(id, str(stall["label"]))
		(row.get_node("Wares") as Label).text = UiLabels.shop_wares(id)
		var bought_base := id == "meat_wholesale" and bool(base["paid"])
		(row.get_node("BoughtFrame") as Control).visible = bought_base
		var state := ""
		if bought_base:
			state = "鍋の素 %s%d杯 買った" % [_tier_short(str(base["label"])), int(base["servings"])]
		if tally != null and tally.spent(id) > 0:
			state = ("%s・" % state if state != "" else "") + "¥%d 使った" % tally.spent(id)
		if not enabled and state == "":
			state = "今日は閉まっている"
		(row.get_node("State") as Label).text = state
	_exit.disabled = not session.can_exit_market()


## 鍋の素の段階のラベル（「中仕込み」など）を、店の一覧の短い形（「中」）にする。
static func _tier_short(label: String) -> String:
	return label.replace("仕込み", "")


func _on_stall_pressed(index: int) -> void:
	var stalls := session.market_stalls()
	if index < stalls.size() and bool(stalls[index]["enabled"]):
		session.select_stall(str(stalls[index]["id"]))


func _on_exit_pressed() -> void:
	if session != null and session.can_exit_market():
		session.exit_market()
