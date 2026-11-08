extends Control
class_name UiPotGauge
## トッピングタブの鍋の小さな絵（UI準備S）。数字は出さない（正確な杯数・濃さは鍋タブ）。表示だけ。
##   量＝残りの杯数（鍋の容量 Rules.pot_capacity に対する割合。水で容量を超えたら満杯。1杯でも残っていれば底に少し見える）。
##   色＝濃さ（濃さ1＝薄い色 → 濃さ5＝濃い色。濃さ0＝出せない＝水のような色）。
##   濃さが適正の外（0・1・5。鍋タブの目盛り・案内文と同じ線引き）のときは、鍋の縁を注意色にする。
## 鍋が無いときは何も描かない。

const LIGHT := Color("#e2c48f")    # 濃さ1（薄い）
const DARK := Color("#7f3f15")     # 濃さ5（濃い）
const WATERY := Color("#b9c4c7")   # 濃さ0（出せない）
const MIN_FILL_PX := 3.0           # 残りがあるときの、いちばん少ない見え方

var exists := false
var fill_ratio := 0.0   # 0〜1（残りの杯数 ÷ 容量）
var fill_color := LIGHT
var warn := false


## pot_view() の辞書から、量・色・注意を決めて描き直す。
func set_pot(pot: Dictionary) -> void:
	exists = bool(pot.get("exists", false))
	if exists:
		var strength := int(pot.get("strength", 0))
		fill_ratio = ratio_for(int(pot.get("remaining", 0)), int(pot.get("capacity", 0)))
		fill_color = color_for(strength, pot)
		warn = UiKaitenTopping.strength_outside_fit(strength, pot)
	else:
		fill_ratio = 0.0
		warn = false
	queue_redraw()


## 残りの割合（0〜1）。容量が分からないときは、残りがあれば満杯。
static func ratio_for(remaining: int, capacity: int) -> float:
	if remaining <= 0:
		return 0.0
	if capacity <= 0:
		return 1.0
	return clampf(float(remaining) / float(capacity), 0.0, 1.0)


## 濃さの色。出せない（床以下）は水のような色、それ以外は薄い→濃いへ。
static func color_for(strength: int, pot: Dictionary) -> Color:
	var floor_value := int(pot.get("strength_floor", GameState.STRENGTH_HARD_FLOOR))
	var lo := int(pot.get("strength_min", GameState.STRENGTH_MIN))
	var hi := int(pot.get("strength_max", GameState.STRENGTH_MAX))
	if strength <= floor_value:
		return WATERY
	var t := clampf(float(strength - lo) / float(maxi(hi - lo, 1)), 0.0, 1.0)
	return LIGHT.lerp(DARK, t)


func _draw() -> void:
	if not exists:
		return
	var line := get_theme_color(&"warn" if warn else &"accent", &"UiPalette")
	var w := size.x
	var h := size.y
	# 鍋の体（縁の内側）・左右の取っ手・上の縁
	var body := Rect2(8, 10, w - 16, h - 12)
	draw_rect(body, get_theme_color(&"bg", &"UiPalette"), true)
	var inner := body.grow(-3)
	if fill_ratio > 0.0:
		var fill_h := maxf(inner.size.y * fill_ratio, MIN_FILL_PX)
		draw_rect(Rect2(inner.position.x, inner.end.y - fill_h, inner.size.x, fill_h), fill_color, true)
	draw_rect(body, line, false, 2.0)
	draw_line(Vector2(3, 10), Vector2(w - 3, 10), line, 2.0)
	draw_rect(Rect2(1, 14, 7, 8), line, false, 2.0)
	draw_rect(Rect2(w - 8, 14, 7, 8), line, false, 2.0)
