extends RefCounted
class_name Ingredients
## 具材マスタ（DESIGN.md 9.5 STEP 11 / STEP 13 / STEP 17.5）。
##
## day1_events.gd と同じ「データのみ」の薄いクラス。
## Ingredient は id と tags[] だけを持つ最小形（DESIGN.md 9.5 STEP 11）。
## その日のイベント台本（day1_events.gd）とは別ファイルに置く:
## こちらは「ゲーム全体で共通の定義」であって、日ごとの台本ではないため。
##
## STEP 17.5: 5つの味（調味料）を用意。tagsは1個ずつ、大文字（HOT等）で統一
## （鍋のbase_tagsは"meaty"等の小文字のままで別の名前空間。衝突しない）。
## STEP 17.6: 具材4種を追加。味とは別軸（POWER/GENTLE/FILLING等、DESIGN.md 9.5 STEP17.6）。
## Day1の在庫はこのうち7種（調味料3＋具材4）。pickled_lime/bitter_meronは
## 定義のみでDay1では使わない（在庫が選択肢を決める＝day1_events.gd側で絞る）。

const _TAGS := {
	"nam_prik_pao": ["HOT"],
	"coconut_milk": ["MELLOW"],
	"pickled_lime": ["SOUR"],
	"bitter_melon": ["BITTER"],
	"herbal_sauce": ["SAVORY"],
	"offal": ["POWER"],
	"meat_ball": ["POWER"],
	"tofu": ["GENTLE"],
	"broken_wrapper": ["FILLING"],
}


## id から tags[] を引く。未知 id は空配列（フォールバック）。
## 呼び出し側が配列を書き換えても _TAGS 本体に影響しないよう複製して返す。
static func tags_for(id: String) -> Array:
	return _TAGS.get(id, []).duplicate()
