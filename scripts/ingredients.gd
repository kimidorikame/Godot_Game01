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
## Day1の在庫はこのうち7種（調味料3＋具材4）。pickled_limeは定義のみで未使用
## （在庫が選択肢を決める＝day1_events.gd側で絞る）。
## DESIGN.md 7.7: 永順青果の商品として winter_melon（冬瓜）を追加。bitter_melon（苦瓜）は
## STEP17.6で定義済みだったものを購入対象として使い始める（tagsの定義自体は変更なし）。
##
## タグは2つの軸に分かれる（フェーズ1 ステップ3で「具」側を判定に使うため明文化）：
##   調味料（味）… HOT / MELLOW / SOUR / BITTER / SAVORY
##   具材（具）  … POWER / GENTLE / FILLING / BITE / TREAT
## 苦瓜（bitter_melon）は BITTER のみ＝味の素材なので「具」には数えない（is_topping参照）。

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
	"winter_melon": ["GENTLE"],
	# 市場の残り店で買える新しい品目（DESIGN.md 7.7）。BITE・TREAT は新しい軸。
	"cartilage": ["BITE"],
	"tendon_meat": ["BITE"],
	"dried_wood_ear": ["BITE"],
	"rice_noodle": ["FILLING"],
	"shrimp": ["TREAT"],
	"clam": ["TREAT"],
	"fish_maw": ["TREAT"],
}


# 腐る品目（腐敗管理の対象）。調味料の一部・冬瓜・乾燥きくらげ・米麺・ベースは腐らない。
const _PERISHABLE := [
	"coconut_milk", "offal", "meat_ball", "tofu", "broken_wrapper", "bitter_melon",
	"cartilage", "tendon_meat", "shrimp", "clam", "fish_maw",
]

# 通知テキスト用の日本語名（「〜を入れる」ではない名詞形）。腐る品目の分だけ持つ。
const _NAMES := {
	"coconut_milk": "ココナッツミルク", "offal": "モツ", "meat_ball": "くず肉団子",
	"tofu": "豆腐", "broken_wrapper": "割れた餃子皮", "bitter_melon": "苦瓜",
	"cartilage": "軟骨", "tendon_meat": "すじ肉", "shrimp": "海老", "clam": "貝",
	"fish_maw": "魚の浮き袋",
}


static func is_perishable(id: String) -> bool:
	return _PERISHABLE.has(id)


# 「具」側の軸（上のコメント参照）。judge_bowl の具なし判定（フェーズ1 ステップ3）で使う。
const _TOPPING_TAGS := ["POWER", "GENTLE", "FILLING", "BITE", "TREAT"]


## id が「具材」（具の軸のタグを1つでも持つ品目）かどうか。調味料（味の軸のみ）や
## タグ未定義の id は false。DESIGN.md「具なしの椀は常に最低評価」の判定に使う
## （OpenController.judge_bowl から呼ぶ）。
static func is_topping(id: String) -> bool:
	for tag in tags_for(id):
		if _TOPPING_TAGS.has(tag):
			return true
	return false


## id から日本語名を引く。未知 id はそのまま id を返す。
static func name_for(id: String) -> String:
	return _NAMES.get(id, id)


## id から tags[] を引く。未知 id は空配列（フォールバック）。
## 呼び出し側が配列を書き換えても _TAGS 本体に影響しないよう複製して返す。
static func tags_for(id: String) -> Array:
	return _TAGS.get(id, []).duplicate()
