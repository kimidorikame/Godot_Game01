extends RefCounted
class_name Ingredients
## 具材マスタ（DESIGN.md 9.5 STEP 11 / STEP 13）。
##
## day1_events.gd と同じ「データのみ」の薄いクラス。
## Ingredient は id と tags[] だけを持つ最小形（DESIGN.md 9.5 STEP 11）。
## その日のイベント台本（day1_events.gd）とは別ファイルに置く:
## こちらは「ゲーム全体で共通の定義」であって、日ごとの台本ではないため。

const _TAGS := {
	"nam_prik_pao": ["spicy"],
}


## id から tags[] を引く。未知 id は空配列（フォールバック）。
## 呼び出し側が配列を書き換えても _TAGS 本体に影響しないよう複製して返す。
static func tags_for(id: String) -> Array:
	return _TAGS.get(id, []).duplicate()
