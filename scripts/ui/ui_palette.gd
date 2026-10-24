extends RefCounted
class_name UiPalette
## 本番UIの配色（夜の画面）。チャット側の配置図と同じ値。Theme（resources/ui_theme.tres）と
## 生成スクリプト（tools/build_ui_scenes.gd）がここから作る。部品は個別に色を持たず、Themeの
## 型の変種（LabelDim・ButtonPrimary など）かテーマの色（型 "UiPalette"）を使う。

const BG := Color("#12161d")        # 地
const BG2 := Color("#1a202b")       # 地2
const FRAME := Color("#1c222d")     # 枠
const BUTTON := Color("#262e3b")    # ボタン
const LINE := Color("#3d485a")      # 線
const TEXT := Color("#e8ebf0")      # 文字
const DIM := Color("#9aa5b5")       # 薄い文字
const ACCENT := Color("#e8a33d")    # 強調
const ON_ACCENT := Color("#1a1204") # 強調の上の文字
const WARN := Color("#ff8a7a")      # 注意
const GOOD := Color("#6fd49a")      # 良い
const PORTRAIT := Color("#2c3544")  # 立ち絵の影


## テーマの色の名前（型 "UiPalette"）→ 値。
static func colors() -> Dictionary:
	return { "bg": BG, "bg2": BG2, "frame": FRAME, "button": BUTTON, "line": LINE, "text": TEXT, "dim": DIM,
		"accent": ACCENT, "on_accent": ON_ACCENT, "warn": WARN, "good": GOOD, "portrait": PORTRAIT }
