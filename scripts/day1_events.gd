extends RefCounted
class_name Day1Events
## Day1 の Event 列（データのみ）。DESIGN.md 9章 STEP 3。
##
## 「シナリオデータと処理を分離する」方針（DESIGN.md 確定事項）に従い、
## Event の中身はここに置く。処理（表示・入力待ち解除など）は
## EventRunner / DebugPanel 側で行い、ここには書かない。
##
## STEP 3: WAKE のみ。STEP 4: PREP を最小構成で追加。
## STEP 6: OPEN の客1人分。STEP 7: OPEN の客を3人に（キューを増やすだけで回る確認）。
## STEP 8: チンピラの REACT 後ろに場所代 PAY を1つ差す（専用 State なし・単なる Event）。

## 名前あり客のid→表示名（予告メモ・営業メモ用。DebugPanel._format_tonight_memo()参照）。
## 挨拶テキスト(greet)から名前を拾わないのは、delivery_manのDay1が専用Event列
## （_delivery_man_events）で greet を持たない特殊形のため、日や実装状況に関わらず
## 安定して名前を引ける場所を別に用意した。
const CUSTOMER_NAMES := {
	"delivery_man": "配達員", "thug": "チンピラ", "granny": "老婆",
	"officer": "新人警官", "hooker": "夜の女", "streamer": "配信者",
}

## 日々の運営費（DAILY_OPERATING_COST）は、ここではなくDebugPanel._set_runner_for_phase
## (WAKE)が直接支払う（Eventとしては持たない）。理由：WAKEは_phase_can_skip=trueで
## [次のPhase]がrunnerを消化せず先へ進めるため、支払いをPAY Eventとして置くと毎回
## スキップされてしまう（場所代・水道代の再編＋日々の運営費で確認済み）。ここに置く
## 3つ目のTEXTは、既に支払い済みであることを見せるだけの表示専用の行（効果は持たない）。
## 「共同水道と炭屋」という具体的な行き先にしているのは、実際に支払いが完了する
## （物語上のけじめが付く）タイミングを市場を出るとき（prep_after_tier_events参照）に
## 見せるため、ここでは「まとめて渡す分を先に取っておく」という前振りにしてある。
static func wake_events() -> Array:
	return [
		{ "type": "TEXT", "text": "……目が覚めた。まだ薄暗い店の奥。" },
		{ "type": EventRunner.TYPE_WAIT_INPUT, "text": "スマホを見る。" },
		{ "type": "TEXT", "text": "共同水道と炭屋への払い（¥%d）は、市場を出るときにまとめて渡す分として先に取っておく。" % GameState.DAILY_OPERATING_COST },
		{ "type": "TEXT", "text": "さて、準備へ向かうか。" },
	]


## 仕込みの3段階（BALANCE_REDESIGN_PLAN.md§2「7日版の数値一式」）。MARKETの
## *_goods()と同じ置き場所・schema思想（id/label/price + この場合はservings）。
## 小仕込みの価格(80)は独立した定数（旧GameState.BASE_PRICEは予備ベース購入専用の
## 値だったが、濃さメカニクス三点セットで予備ベースごと廃止した）。
const PREP_TIERS := [
	{ "id": "small",  "label": "小仕込み", "price": 80,  "servings": 8 },
	{ "id": "medium", "label": "中仕込み", "price": 110, "servings": 11 },
	{ "id": "large",  "label": "大仕込み", "price": 140, "servings": 14 },
]


## PREP_TIER Eventのoptionsとして渡す（呼び出し側が書き換えても本体に影響しないよう複製）。
static func prep_tier_options() -> Array:
	return PREP_TIERS.duplicate(true)


## idから仕込み段階を引く。未知idはPREP_TIERS[0]（小仕込み）にフォールバックする
## （安全側。実際には既知の3種類のidしかボタンから渡らない想定）。
static func prep_tier_by_id(tier_id: String) -> Dictionary:
	for tier in PREP_TIERS:
		if str(tier.get("id", "")) == tier_id:
			return tier
	return PREP_TIERS[0]


## PREP の最小構成（DESIGN.md 9章 STEP 4 → STEP 9 で水道代 → Day2 分岐で条件化）。
## 「PREP という巨大なコード」は作らず、TEXT / PAY / ADD_ITEM / MARKET / REMOVE_ITEM の
## 並びだけで表現する。ここはデータのみ。PAY の amount / ADD_ITEM・REMOVE_ITEM の
## item・amount が「効果」を表し、実際の処理（apply_money / add_inventory /
## remove_inventory）は受け側 = DebugPanel._apply_event が行う。
## text は表示用でしかなく、状態は動かさない。
## DESIGN.md 7.7: 市場を MARKET Event（"options" を持つ。ADJUSTと同じくEventRunnerは
##   型を問わずWAITING_INPUTで止まる）として挟む。水場は市場滞在中に押せる
##   選択肢の1つになり、TEXTとしては並べない（受け側が直接処理する。詳細は
##   DebugPanel._visit_water_stall / _on_market_exit_pressed）。
## 具材の腐敗: spoiled は今朝PREPに入った瞬間に破棄された品目 id → 個数の Dictionary
##   （受け側が GameState.discard_spoiled_inventory() で先に消して渡す。日次ログ導入で
##   個数も持つようになったが、ここでは `for id in spoiled` でキーを回すだけなので
##   Array時代と同じ書き方のまま動く）。あれば先頭に一言テキストを1つ足す
##   （データのみ。破棄自体はここでは行わない）。
## クズ野菜ベース: scraps_base は「一番安い仕込み（PREP_TIERS[0]）すら払えない」ので
##   食肉仲卸ではなく端材屋へ回る日か。受け側がPREPに入る瞬間に所持金を見て1回だけ決め、
##   ここへは引数で渡す（計器盤にも同じ値を出すため。ここで money を読むと、PREPの途中で
##   所持金が変わったときに表示とずれる）。この場合は3段階から選ばせず、自動的に
##   PREP_TIERS[0]と同じ8杯・支払い無し・濃さ1スタートになる。
## 仕込み3段階化（BALANCE_REDESIGN_PLAN.md§1・§2）：食肉仲卸での固定PAYは、
##   PREP_TIER Event（3段階から選ぶ、MARKETと同じ"options"方式）に置き換えた。
##   選んだ段階の杯数はprep_events()を組み立てる時点ではまだ決まらないため、
##   ここでは選択肢を提示するところまでで打ち切り、残り（ADD_ITEM以降）は
##   選択後にprep_after_tier_events()で組み立ててDebugPanel側がrunnerを差し替える
##   （_on_prep_tier_selected参照）。端材屋ルートは段階が固定（PREP_TIERS[0]相当）
##   なので、従来どおりここで最後まで1回で組み立てる。
static func prep_events(spoiled: Dictionary = {}, scraps_base: bool = false) -> Array:
	var events := []
	if not spoiled.is_empty():
		var names := PackedStringArray()
		for id in spoiled:
			names.append(Ingredients.name_for(str(id)))
		events.append({ "type": "TEXT",
			"text": "在庫を確かめる。傷みきった%sは捨てた。" % "・".join(names) })
	if scraps_base:
		# 値切る／譲ってもらう。食肉仲卸で仕込みを選ぶ淡々としたトーンと対比させる。
		events.append_array([
			{ "type": "TEXT", "text": "荷捌き裏通りへ回る。半端市「拾味」。今日は財布が軽い" },
			{ "type": "TEXT", "text": "「すまん、持ち合わせが足りねえ」「……野菜くずなら持ってきな。金はいい」" },
		])
		events.append_array(prep_after_tier_events(PREP_TIERS[0], true))
	else:
		events.append_array([
			{ "type": "TEXT", "text": "食肉売場へ来た" },
			{ "type": "PREP_TIER", "text": "「いつもの、って言われてもな。今日はどれだけ仕込む？」",
				"options": prep_tier_options() },
		])
	return events


## PREP_TIERの選択（または端材屋の固定・小仕込み相当）が決まった後の残り。
## DebugPanel._on_prep_tier_selected()が選択直後にflow.set_runner()で差し替える
## （prep_events()自体は選択前に呼ばれるため、選ばれた杯数をここで初めて確定させる）。
## 差し替え先の新しいEvent列の先頭（index 0）はEventRunnerの仕様上、乗った瞬間には
## 効果が適用されない（_apply_eventのコメント参照）ため、先頭を必ず効果の無いTEXTにする
## （scraps_baseルートはprep_events()側の既存TEXTに連結されるだけなので影響なし）。
static func prep_after_tier_events(tier: Dictionary, scraps_base: bool = false) -> Array:
	var events := []
	if not scraps_base:
		events.append({ "type": "TEXT", "text": "%sにした。" % str(tier.get("label", "")) })
	events.append({ "type": "ADD_ITEM", "item": "soup_base", "amount": 1,
		"text": "萎れた野菜くずをひと抱え、譲ってもらった" if scraps_base else "鶏骨と手羽端を受け取った" })
	# Day2（新人警官の初登場）：ベース入手の後・市場の前に、昼の市場の会話を挟む。要求タグ
	# （酸っぱい汁・噛める具）を仕入れの前に知らせるため。市場の enabled（day2_unlocked）とは
	# 無関係に、会話は必ず出る。日付は _market_options と同じく関数の中で直接読む。
	if GameState.day_count == 2:
		events.append_array(_talk("officer", _OFFICER_MARKET))
	events.append({ "type": "MARKET", "text": "（市場をぶらつく）",
		"options": _market_options(scraps_base) })
	# 場所代・水道代の再編＋日々の運営費：市場を出た瞬間の物語上のけじめ（表示専用の
	# TEXT。効果は持たない。実際の日々の運営費の天引きはWAKEで既に済んでおり、市場を
	# 出た瞬間にDebugPanel._on_market_exit_pressedが支払い予定の表示だけを決済する）。
	events.append({ "type": "TEXT", "text": "共同水道と炭屋に寄り、市場を出た。" })
	# 仕込み: 在庫を減らす責務は REMOVE_ITEM のまま（鍋作成を混ぜない）。
	events.append({ "type": "REMOVE_ITEM", "item": "soup_base", "amount": 1,
		"text": "さて、仕込むか。鍋に放り込む" })
	# 共有鍋ができる（STEP 12）。ベースは今は鶏がらだしの1種類だけ（DESIGN.md 7.7：
	# 「骨と大根」から「鶏骨＋手羽端」に変更。IDはbone_broth/soup_baseのまま据え置き）。
	# 7.6: 残量（杯数）を Event が運ぶ。PAY の amount / REACT の sale と同じで、
	#   具体値は Event が持ち、適用は受け側（GameState.set_soup）が行う。仕込み3段階化：
	#   杯数はtier.servings（選んだ段階、または端材屋の固定分）を使う。
	# 7.6: 濃さ（仕込み時は3＝ちょうどいい）と、今夜使える水の回数も一緒に渡す。
	#   水の回数自体は市場（水場）に行ったかとは無関係に毎朝2回分（GameState定数）。
	#   水場で払うのは水道代（徴収日のみ）で、回数を増やす効果ではない。
	# クズ野菜ベース: 濃さ1スタート（既存の濃さ1のペナルティがそのまま効く）。base_id・tags は
	#   veg_scrap_broth / ["vegetal"] にして、計器盤の soup 行で1日中「クズ野菜の日」と読めるようにする
	#   （soupのtagsは判定に使っていない＝表示用。効果は濃さだけ）。
	var servings := int(tier.get("servings", 8))
	if scraps_base:
		events.append({ "type": "SET_SOUP", "base_id": "veg_scrap_broth", "tags": ["vegetal"],
			"servings": servings,
			"strength": 1,
			"water_doses": GameState.WATER_DOSES_PER_NIGHT,
			"text": "野菜くずを煮出した。薄い……。今日の鍋ができた（%d杯分）。" % servings })
	else:
		events.append({ "type": "SET_SOUP", "base_id": "bone_broth", "tags": ["meaty"],
			"servings": servings,
			"strength": 3,
			"water_doses": GameState.WATER_DOSES_PER_NIGHT,
			"text": "鶏の出汁が立ってきた。今日の鍋ができた（%d杯分）。" % servings })
	return events


## 市場の選択肢（DESIGN.md 7.7）。"enabled" で今日押せるかをデータ側に持たせる
## （「今日どの店が開いているか」は日ごとに変わる事実なので、is_mob等と同じくデータ側）。
## 食肉仲卸・青果〜端材半端物の6店は2日目から解禁（DESIGN.md 7.7「他の区画は2日目から解禁」）。
##   どの店も実際に買える（各店の商品は produce_goods など <店のid>_goods 参照）。
##   食肉仲卸のベース購入はPREPの先頭で自動で済むが、ここでは追加購入の店として入れる。
##   >= 2 なので3日目以降も開いたまま（店ごとに解禁日を変える仕組みは対象外）。
## 水場は市場のボタン一覧には出さない（場所代・水道代の再編＋日々の運営費：水道代は
##   [市場を出る]で自動的に精算される。DebugPanel._on_market_exit_pressed /
##   _visit_water_stall 参照）。水場専用の訪問セリフも同じ理由で廃止した。
## 注意: この enabled は prep_events() が呼ばれた瞬間（＝PREPに入った瞬間）に固定される。
##   Event データは読むだけで書き換えない原則のため、MARKET画面を表示したまま
##   day_count が変わっても、その場では反映されない（次にPREPへ入り直すまで）。
## クズ野菜ベースの日（scraps_base）は、Day1だけ「訪問済み」の表示が食肉仲卸ではなく
##   端材半端物の側に付く（自動で済んだ店がグレーで押せない説明のため）。2日目以降は影響なし。
static func _market_options(scraps_base: bool = false) -> Array:
	var day2_unlocked: bool = GameState.day_count >= 2
	# 「（訪問済み）」は、Day1に自動で済んだ店が押せない理由の説明にだけ付ける。
	# 2日目以降は6店とも買い物のできる店なので、クズ野菜の日でも付けず、押せる
	# （貧しい日こそ端材屋の安い商品が要る。店には何度でも入れる）。
	var meat_label := "食肉仲卸"
	var scraps_label := "端材半端物"
	if not day2_unlocked:
		if scraps_base:
			scraps_label += "（訪問済み）"
		else:
			meat_label += "（訪問済み）"
	return [
		{ "id": "meat_wholesale", "label": meat_label, "enabled": day2_unlocked },
		{ "id": "produce",        "label": "青果",       "enabled": day2_unlocked },
		{ "id": "dry_goods",      "label": "乾物調味料", "enabled": day2_unlocked },
		{ "id": "tofu_noodles",   "label": "豆腐麺",     "enabled": day2_unlocked },
		{ "id": "seafood",        "label": "海鮮",       "enabled": day2_unlocked },
		{ "id": "scraps",         "label": scraps_label, "enabled": day2_unlocked },
	]


## 永順青果の商品（DESIGN.md 7.7 → BALANCE_REDESIGN_PLAN.md §3で購入単位・価格を更新）。
## 各要素の"item"が在庫に足す品目id、"count"が1回の購入で増える個数（品目ごとに異なる。
## GameState.INGREDIENT_SERVINGS_PER_PURCHASEは①具材の購入単位ラウンドで廃止した）。
## "id"はボタン識別用（同じitemに複数の購入選択肢があるときはidを分ける。モツ・海老の
## 小口購入 = meat_wholesale_goods() / seafood_goods() 参照）。何度でも買える。
## 所持金が足りなければ受け側がボタンを無効化する。
static func produce_goods() -> Array:
	return [
		{ "id": "winter_melon", "item": "winter_melon", "label": "冬瓜", "price": 50, "count": 5 },
		{ "id": "bitter_melon", "item": "bitter_melon", "label": "苦瓜", "price": 12, "count": 3 },
	]


## 残りの店の商品（DESIGN.md 7.7）。<店のid>_goods の名前で produce_goods に揃える
## （DebugPanel._shop_goods の match のキーと一対一）。schemaは produce_goods() 参照。
## モツは1個12の小口購入も追加（offal_single。在庫は同じoffalへ足す）。
## 「既存id」は初期在庫と同じ id で、市場での補充経路が増えるだけ（買い足すと品目全体の
## 補充日が更新される簡易仕様）。
static func meat_wholesale_goods() -> Array:
	return [
		{ "id": "offal",        "item": "offal",       "label": "モツ",           "price": 30, "count": 3 },
		{ "id": "offal_single", "item": "offal",       "label": "モツ(小口1個)", "price": 12, "count": 1 },
		{ "id": "cartilage",    "item": "cartilage",   "label": "軟骨",           "price": 24, "count": 3 },
		{ "id": "tendon_meat",  "item": "tendon_meat", "label": "すじ肉",         "price": 36, "count": 3 },
		# 濃縮だし（予備ベースの後継。濃さメカニクス三点セット）。1周1回の制限や期限は無く、
		# 毎日何度でも買える。在庫（inventory）には入れず、受け側が GameState.buy_dashi()
		# で処理する。Day2から（市場の解禁と同じ）。
		{ "id": "dashi", "label": "濃縮だし", "price": GameState.DASHI_PRICE },
	]


static func dry_goods_goods() -> Array:
	return [
		{ "id": "nam_prik_pao",   "item": "nam_prik_pao",   "label": "ナムプリックパオ",   "price": 25, "count": 5 },
		{ "id": "coconut_milk",   "item": "coconut_milk",   "label": "ココナッツミルク",   "price": 15, "count": 3 },
		{ "id": "herbal_sauce",   "item": "herbal_sauce",   "label": "薬膳ナンプラーだれ", "price": 25, "count": 5 },
		{ "id": "pickled_lime",   "item": "pickled_lime",   "label": "塩漬けライム",       "price": 20, "count": 5 },
		{ "id": "dried_wood_ear", "item": "dried_wood_ear", "label": "乾燥きくらげ",       "price": 50, "count": 5 },
	]


static func tofu_noodles_goods() -> Array:
	return [
		{ "id": "tofu",        "item": "tofu",        "label": "豆腐", "price": 24, "count": 3 },
		{ "id": "rice_noodle", "item": "rice_noodle", "label": "米麺", "price": 40, "count": 5 },
	]


## 海老は1個20の小口購入も追加（shrimp_single。在庫は同じshrimpへ足す）。
static func seafood_goods() -> Array:
	return [
		{ "id": "shrimp",        "item": "shrimp",   "label": "海老",           "price": 54,  "count": 3 },
		{ "id": "shrimp_single", "item": "shrimp",   "label": "海老(小口1個)", "price": 20,  "count": 1 },
		{ "id": "clam",          "item": "clam",     "label": "貝",             "price": 48,  "count": 3 },
		{ "id": "fish_maw",      "item": "fish_maw", "label": "魚の浮き袋",   "price": 100, "count": 5 },
	]


static func scraps_goods() -> Array:
	return [
		{ "id": "broken_wrapper", "item": "broken_wrapper", "label": "割れた餃子皮", "price": 18, "count": 3 },
		{ "id": "meat_ball",      "item": "meat_ball",      "label": "肉団子",       "price": 24, "count": 3 },
	]


## 品目id → 市場での価格（"id"ごとの値。パックと小口が別idを持つ品目は両方載る）。
## 廃棄額の計算にはもう使わない（①具材の購入単位で、ロットごとに実際に払った単価を
## 積算する方式へ変更。GameState.discard_spoiled_inventory()参照）。将来の代表価格
## 表示用として残す。数値をここへ書き写さず、既存の *_goods() を1回ずつ集めて作るだけに
## する（市場価格を変えてもこちらは自動で追従する）。dashi（濃縮だし）は
## 仕込み用の別資源で腐敗バッチにも登場しないため、含めても実害はないが対象外として省く。
static func ingredient_prices() -> Dictionary:
	var prices := {}
	var all_goods := produce_goods() + meat_wholesale_goods() + dry_goods_goods() \
		+ tofu_noodles_goods() + seafood_goods() + scraps_goods()
	for good in all_goods:
		var id := str(good.get("id", ""))
		if id != "" and id != "dashi":
			prices[id] = int(good.get("price", 0))
	return prices


## CLOSE の締めくくり（DESIGN.md 9章 STEP 9）。TEXT のみ・効果を持つ Event は入れない。
## 所持金・提供数は計器盤に出ているので、ここは「読ませて区切る」だけ。
## 凝った売上内訳・精算演出は入れない（今ある状態を見せる最小）。
## 最終日（GameState.FINAL_DAY）だけ、末尾に「（終了）」を1つ足す。条件は GameState.is_final_day()
## を中で読む（水道代の条件化・_market_options の day_count 判定と同じ既存パターン）。
static func close_events() -> Array:
	var events := [
		{ "type": "TEXT", "text": "看板の灯を落とす。" },
		{ "type": "TEXT", "text": "屋台を閉める。" },
		{ "type": "TEXT", "text": "本日の営業終了。売上と提供数は計器盤のとおり。" },
	]
	if GameState.is_final_day():
		events.append({ "type": "TEXT", "text": "（終了）" })
	return events


## OPEN の客の並び（DESIGN.md 9章 / 7.6 / §9-C「データの外部化」）。STEP 6: 配達員1人
## → STEP 7: 3人 → §9-C: 日ごとの構成をScheduleData.day_schedule()のJSONから組み立てる
## 汎用ロジックに変更（day1_events.gd側にはもう客IDのif/matchを持たない）。
## 7.6: フラットな配列をやめ、**時間帯で区切る**（宵の口 / 夜半 / 明け方）。
##   時間帯名と客リストを1つの辞書に同居させる（名前を別配列で並行管理しない）。
## §9-C: day_schedule.jsonに無い日（Day3〜7）はScheduleData側で"1"（Day1）へ
##   フォールバックする。ここでは「今日の枠構成」をそのまま信じて組み立てるだけでよい。
## 時間帯に客がいない（＝main/main_poolを持たない）ことは今回は無い想定だが、
##   将来そういう枠を足しても "id": "" のまま customers=[] になるだけで安全。
##
## モブの独立抽選（Day2-7ダミーデータ・モブ抽選独立化 → ④評判の更新+⑤客数の決め方で
## Day2以降のauto経路をtotal_demand_today()ベースへ置き換え）。
## 枠ごとに決めたモブの（型・人数）は、customersに積む文字列自体を"mob#N"という
## その日だけのインスタンスidにし、_mob_instancesへ退避しておく（客の番が来て
## customer_events()→_customer_flavor()が呼ばれるときに引けるようにするため。
## OpenController・debug_panel.gdはcustomersを不透明な文字列としてしか見ないので、
## この2つは無改修で動く）。_mob_instancesはここで毎回clear()するので、次の日の
## customer_schedule()呼び出しで自動的に前日の分が消える（明示的なリセットフックは
## 不要と判断した）。
##
## debug_mob_count（-1=自動、0以上=QA用の一律上書き）とDay1は、従来どおり
## 枠（宵の口・夜半・明け方）ごとに独立して_pick_mob()を呼ぶ（Day1はCURRENT_SPEC.md
## 「チュートリアルなので評判では揺らさない」の明記どおり据え置き。デバッグ上書きは
## 総需要システムを丸ごとバイパスして全モブ枠へ一律適用する既存挙動を維持）。
## それ以外（Day2以降のauto）だけ、その夜の総需要からメイン客の合計杯数を引いた
## モブ杯数を先に決め、_plan_mob_groups()で組へ配分してから枠へ割り当てる。
static func customer_schedule(debug_mob_count: int = -1) -> Array:
	_mob_instances.clear()
	var slots: Array = ScheduleData.day_schedule(GameState.day_count).get("slots", [])
	var chosen_mains := []   # 同日内の重複禁止（main_poolの抽選用。§9-C確定仕様）
	var main_ids := []
	for slot in slots:
		var main_id := _pick_main(slot, chosen_mains)
		main_ids.append(main_id)
		if main_id != "":
			chosen_mains.append(main_id)

	var use_demand_system: bool = debug_mob_count < 0 and GameState.day_count > 1
	var mob_groups_by_index := {}
	if use_demand_system:
		var main_total := 0
		for main_id in main_ids:
			if main_id != "":
				main_total += _customer_total_servings(main_id)
		var mob_cups: int = maxi(GameState.total_demand_today() - main_total, 0)
		mob_groups_by_index = _plan_mob_groups(slots, mob_cups)

	var mob_seq := 0
	var result := []
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var customers := []
		if main_ids[i] != "":
			customers.append(main_ids[i])
		if use_demand_system:
			for size in mob_groups_by_index.get(i, []):
				var type_id := _pick_mob_type(slot)
				if type_id == "":
					continue
				var instance_id := "mob#%d" % mob_seq
				mob_seq += 1
				_mob_instances[instance_id] = { "type": type_id, "count": size }
				customers.append(instance_id)
		else:
			var mob := _pick_mob(slot, debug_mob_count)
			if not mob.is_empty():
				var instance_id := "mob#%d" % mob_seq
				mob_seq += 1
				_mob_instances[instance_id] = mob
				customers.append(instance_id)
		result.append({ "name": str(slot.get("name", "")), "customers": customers })
	return result


## 1人の客の合計servings（そのcustomer_events()の全REACT Eventのservingsを合算する）。
## 総需要からメイン客分を差し引く計算（customer_schedule）用。_customer_flavor().servingsを
## 直接見ないのは、配達員のDay1（3杯を別々のREACTに分ける専用Event列）のような
## 「1客で複数REACT」の形にも自動的に対応するため（配達員Day1は合計3になる）。
static func _customer_total_servings(customer_id: String) -> int:
	var total := 0
	for ev in customer_events(customer_id):
		if ev.get("type", "") == "REACT":
			total += int(ev.get("servings", 0))
	return total


## モブ杯数を1〜4人の組へ均等配分し（大きい組から先。BALANCE_REDESIGN_PLAN.md§5原文）、
## その日の枠index（day_schedule.jsonの並び順）へ割り当てる。返り値は
## { 枠index: [組のサイズ, ...] }（同じ枠に複数の組が入ることもある）。
## 組数は ceil(モブ杯数/4)。総需要の上限(18)とメイン客合計の下限(3)から、組数は
## 理論上4を超えない（_GROUP_SLOT_PRIORITYが4件しか無いのはこのため）。
## 配置先はその夜の組の何番目かで決め打ち（1組目→夜半、2組目→宵の口、3組目→明け方、
## 4組目→宵の口）。その枠がその日「モブなし」（mob:false。Day1・Day7の明け方）なら
## _GROUP_SLOT_FALLBACK（夜半）へ振り替える（杯数を消さない。全日で夜半は必ずモブ許可枠）。
const _GROUP_SLOT_PRIORITY := ["夜半", "宵の口", "明け方", "宵の口"]
const _GROUP_SLOT_FALLBACK := "夜半"

static func _plan_mob_groups(slots: Array, mob_cups: int) -> Dictionary:
	var by_index := {}
	if mob_cups <= 0:
		return by_index
	var group_count: int = ceili(float(mob_cups) / 4.0)
	var base: int = mob_cups / group_count
	var extra: int = mob_cups % group_count
	var sizes := []
	for i in range(group_count):
		sizes.append(base + 1 if i < extra else base)   # 大きい組から先に並べる

	var index_by_name := {}
	for i in range(slots.size()):
		index_by_name[str(slots[i].get("name", ""))] = i

	for i in range(sizes.size()):
		var target: String = _GROUP_SLOT_PRIORITY[i] if i < _GROUP_SLOT_PRIORITY.size() \
			else _GROUP_SLOT_FALLBACK
		if not (index_by_name.has(target) and _slot_mob_eligible(slots[index_by_name[target]])):
			target = _GROUP_SLOT_FALLBACK
		if not (index_by_name.has(target) and _slot_mob_eligible(slots[index_by_name[target]])):
			continue   # フォールバック先も無い/対象外という想定外の日は、その組は諦める（安全側）
		var idx: int = index_by_name[target]
		var arr: Array = by_index.get(idx, [])
		arr.append(sizes[i])
		by_index[idx] = arr
	return by_index


## その枠にモブが出る資格があるか（"mob"がfalse/無指定ではない）。
## Dictionary と bool を == で比べると実行時エラーになるため、先に is Dictionary で分岐する。
static func _slot_mob_eligible(slot: Dictionary) -> bool:
	var spec = slot.get("mob", false)
	if spec is Dictionary:
		return true
	return bool(spec)


## 1枠ぶんのメイン客idを決める（day_schedule.jsonの読み込みからは独立させた純粋関数。
## §9-Cで確定：固定("main")と抽選プール("main_pool")の2値のみ。特別な「初登場」
## 「最後に固定」用のフィールドは作らない）。
## main_poolの抽選は、その日すでに選ばれた客（chosen）を除外して選ぶ（同日内で同じ
## メイン客が2回出ない）。除外すると候補が0になる場合（プールが尽きた）は、除外を
## 無視してプール全体から選び直す（クラッシュしない。§9-C確定仕様）。
## 乱数はRandomNumberGeneratorを作らず、既存の流儀どおりグローバルなrandi()を使う。
static func _pick_main(slot: Dictionary, chosen: Array) -> String:
	if slot.has("main"):
		return str(slot["main"])
	var pool: Array = slot.get("main_pool", [])
	if pool.is_empty():
		return ""
	var candidates: Array = pool.filter(func(id): return not chosen.has(id))
	if candidates.is_empty():
		candidates = pool
	return str(candidates[randi() % candidates.size()])


## 1枠ぶんのモブの型・人数を決める（Day1・デバッグ上書き専用経路。customer_schedule()
## 参照）。人数は debug_count>=0 ならそれを、そうでなければ GameState.DAY1_MOB_COUNT
## を使う（この関数の自動フォールバック側は、customer_schedule()がDay1でしか
## 呼ばなくなったため、実質Day1専用になった）。人数が0ならその枠にモブは出さない
## （{}を返す。既存の「人数>0のときだけ出す」ルールを踏襲）。
static func _pick_mob(slot: Dictionary, debug_count: int) -> Dictionary:
	var type_id := _pick_mob_type(slot)
	if type_id == "":
		return {}
	var count := debug_count if debug_count >= 0 else GameState.DAY1_MOB_COUNT
	if count <= 0:
		return {}
	return { "type": type_id, "count": count }


## 1枠ぶんのモブの型だけを決める（人数はこの関数の役割外。_pick_mob()と
## _plan_mob_groups()の両方から呼ぶ）。"mob"の値は3値：false/無指定（モブなし・
## 空文字を返す）、true（既存どおりdock_workers固定）、{"pool":[...]}（型をプールから
## 抽選。**同日内の重複除外はしない**＝main_poolとは対称的な仕様。3-1節確定）。
static func _pick_mob_type(slot: Dictionary) -> String:
	var spec = slot.get("mob", false)
	# Dictionary と bool を == で比べると実行時エラーになるため、先に is Dictionary で
	# 分岐する（それ以外はbool(spec)でtrue/falseを見る）。
	if spec is Dictionary:
		var pool: Array = spec.get("pool", [])
		if pool.is_empty():
			return ""
		return str(pool[randi() % pool.size()])
	elif bool(spec):
		return "dock_workers"
	return ""


## id がモブ客か（DESIGN.md 7.6）。自動閉店の判定などで、受け側が
## 「これより後に名前あり客が残っているか」を問い合わせるために公開する。
static func is_mob_customer(customer_id: String) -> bool:
	return bool(_customer_flavor(customer_id).get("is_mob", false))


## その日だけのモブのインスタンスid（"mob#0"等）→{type, count}。customer_schedule()が
## 枠を組み立てる際に書き込み、customer_schedule()の次回呼び出し（＝翌日のOPEN開始）で
## clear()される。_customer_flavor()がここを見てモブの型・人数を引く。
static var _mob_instances: Dictionary = {}


## 1人の客の接客 Event 列。GREET→ADJUST→SERVE→REACT の4ステップは全客共通（DESIGN.md 4章）。
## データのみ。処理は受け側 = DebugPanel._apply_event（GREET/ADJUST/SERVE は表示だけ、
## REACT で仮の売上を計上）。
## STEP 7/8 の割り切り:
##   - 4ステップ骨格は全客共通。客ごとの差は text と sale、および REACT 後ろの追加 Event だけ
##   - REACT の sale は満足度判定（DESIGN.md 7章）が入るまでの固定プレースホルダ
##   - 個性・調理・評価・鍋・水（7章 / 7.5章）は入れない
## STEP 13: ADJUST は素通しをやめ、"options" を持たせて入力待ちにする（DESIGN.md 9.5 STEP 13）。
##   選択肢を選ぶ処理（椀へ足す）は EventRunner ではなく受け側（DebugPanel）が行う。
## STEP 14: 二択にする（DESIGN.md 9.5 STEP 14）。Day1/Day2 を問わず同じ二択
##   （Day1 も「足す/足さない」を選べるチュートリアルとして）。"none" は
##   add_to_bowl 側で「何も足さない」として既に扱える（STEP 13 で用意済み）。
## STEP 15/16: REACT に判定用のデータと反応textを持たせる（DESIGN.md 9.5 STEP 15・16）。
##   判定は受け側 = OpenController.judge_bowl が行う。反応textは書き換えず、
##   どれを見せるかは受け側が都度選ぶ（DebugPanel._current_reaction_text）。
## STEP 17.5: GREET は複数行の掛け合いを1行1Eventに分けて積む（テンポを出すため。
##   EventRunner/受け側は無改修で動く＝WAKEの起床TEXT3連続と同じパターン）。
## STEP 17.6: ADJUSTは3枠まで選べる形に変更（DESIGN.md 9.5 STEP17.6）。
##   「そのまま出す(none)」は削除。何も足さず提供したいときは、選ばずに
##   [入力完了]（提供）を押せばよい（DebugPanel側の変更のみで実現。ここには効果なし）。
##   options自体は全客共通なので _adjust_options() に括り出した。
##   判定は一致数による3段階になり、REACT は wanted_tags（配列）と
##   reactions（結果をキーにした反応textの辞書）を持つ。段階が増えても
##   reactions にキーを足すだけで済む形にしてある（favoriteの「とても好み」など）。
## 7.6: 1回の接客で複数杯出せるようにした（servings）。売上は 50×servings で、
##   値段はデータに書かずルール（GameState.PRICE_PER_SERVING）から出す。
##   is_mob はモブ客かどうか＝評判の増加量を受け側が切り替えるための印。
##   一団でも調理は1回・判定も1回（DESIGN.md 7.6「モブ客の仕様」）。
## 7.6: mob_count は dock_workers の人数（servings・台詞）にだけ使う。乱数は引かない
##   （引くのはOPEN開始時の1回だけ。ここで引くと customer_schedule と食い違う）。
static func customer_events(customer_id: String, mob_count: int = 0) -> Array:
	# 配達員は初日だけ、同じ客へ3杯を1杯ずつ会話の合間に出す専用のEvent列（客ごとの分岐は
	# データ層のここだけ。受け側 DebugPanel には客IDを書かない）。2日目以降に配達員が
	# 再来店した場合は、他の客と同じ通常の1杯の流れ（下の汎用ロジック）を使う
	# （customers/delivery_man.json の"days"."1"エントリが汎用フローの内容を持ち、
	# customer_dataのフォールバックにより2日目以降どの日でもここへフォールバックする）。
	if customer_id == "delivery_man" and GameState.day_count == 1:
		return _delivery_man_events()
	var flavor := _customer_flavor(customer_id, mob_count)
	var events := []
	for line in flavor["greet"]:
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	events.append({ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）",
		"options": _adjust_options() })
	events.append({ "type": "SERVE", "customer": customer_id, "text": "「はいよ、お待ち。」" })
	events.append({ "type": "REACT", "customer": customer_id,
		"reactions": flavor["reactions"], "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "servings": flavor["servings"],
		"is_mob": flavor["is_mob"],
		"sale": GameState.PRICE_PER_SERVING * int(flavor["servings"]) })
	events.append_array(_customer_extra_events(customer_id))
	return events


## 会話行（発話・ト書き）を、1行1Eventの GREET にして積む（既存の接客と同じ形）。
static func _talk(customer_id: String, lines: Array) -> Array:
	var events := []
	for line in lines:
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	return events


## 反応文：数行を改行でつないだ1つの文字列にする（reactions の形は従来どおり
## 「結果ごとの文字列配列」のまま。各結果1パターン）。
static func _lines_text(lines: Array) -> String:
	return "\n".join(PackedStringArray(lines))


## 配達員（阿強）の接客：同じ客に3杯を、会話の合間に1杯ずつ出す（本番用会話稿
## 「１日目_運び屋_1.md」）。1杯目・2杯目は阿強本人の分として個別に評価し、3杯目は
## 第八码頭の労働者への持ち帰り（評価なし）。客キューの上では退店まで1人の客のまま
## （客のEvent列を1本にするので、退店会話が終わるまで次の客へ進まない）。
##   - 各杯は ADJUST → SERVE → REACT。2杯目・3杯目の ADJUST は new_bowl:true で椀を新しくする
##   - 1杯目・2杯目の REACT：aggregate:true（鍋の消費と売上はその場で、評判と提供記録は
##     退店時に客1人分として1回だけ反映）。3杯目の REACT：judge:false を足す
##     （判定・反応・評判なし。鍋の消費と売上は通常どおり）
##   - 各杯 servings は1、売上は PRICE_PER_SERVING（合計150）
##   - 要求タグ・好物は旧 delivery_man のデータ（_customer_flavor）をそのまま使う
static func _delivery_man_events() -> Array:
	var id := "delivery_man"
	var flavor := _customer_flavor(id)
	var options := _adjust_options()
	var sale: int = GameState.PRICE_PER_SERVING * 1
	var events := []
	events.append_array(_talk(id, _DELIVERY_ARRIVAL))
	# 一杯目
	events.append({ "type": "ADJUST", "customer": id, "text": "（味を調える）", "options": options })
	events.append({ "type": "SERVE", "customer": id, "text": "（湯気の立つ椀を置く）" })
	events.append({ "type": "REACT", "customer": id, "servings": 1, "sale": sale,
		"reactions": _delivery_reactions_first(), "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "is_mob": false, "aggregate": true })
	events.append_array(_talk(id, _DELIVERY_AFTER_FIRST))
	# 二杯目
	events.append({ "type": "ADJUST", "customer": id, "text": "（味を調える）",
		"options": options, "new_bowl": true })
	events.append({ "type": "SERVE", "customer": id, "text": "（湯気の立つ椀を置く）" })
	events.append({ "type": "REACT", "customer": id, "servings": 1, "sale": sale,
		"reactions": _delivery_reactions_second(), "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "is_mob": false, "aggregate": true })
	events.append_array(_talk(id, _DELIVERY_AFTER_SECOND))
	# 三杯目（持ち帰り・評価なし）
	events.append({ "type": "ADJUST", "customer": id,
		"text": "（持ち帰り用。辛さ控えめ、豆腐多め）", "options": options, "new_bowl": true })
	events.append({ "type": "SERVE", "customer": id, "text": "（店主は蓋つきの容器を袋へ入れる）" })
	events.append({ "type": "REACT", "customer": id, "servings": 1, "sale": sale,
		"reactions": {}, "is_mob": false, "judge": false, "aggregate": true })
	events.append_array(_talk(id, _DELIVERY_EXIT))
	return events


static func _delivery_reactions_first() -> Dictionary:
	return {
		"GREAT": ["配達員【GREAT】(1杯目)"],
		"GOOD": ["配達員【GOOD】(1杯目)"],
		"OK": ["配達員【OK】(1杯目)"],
		"BAD": ["配達員【BAD】(1杯目)"],
	}


static func _delivery_reactions_second() -> Dictionary:
	return {
		"GREAT": ["配達員【GREAT】(2杯目)"],
		"GOOD": ["配達員【GOOD】(2杯目)"],
		"OK": ["配達員【OK】(2杯目)"],
		"BAD": ["配達員【BAD】(2杯目)"],
	}


## 来店〜一杯目の注文（会話稿「登場・一杯目の注文」）。
const _DELIVERY_ARRIVAL := [
	"配達員「注文（HOT/POWER）」1杯目",
]

## 一杯目の共通会話（料理の結果に関係なく表示。会話稿「一杯目・共通会話」）。
const _DELIVERY_AFTER_FIRST := [
	"配達員「1杯目の共通会話（第八码頭の話は省略）」",
]

## 二杯目の共通会話（第八码頭の情報はここ。料理の結果に関係なく必ず表示。
## 会話稿「二杯目・共通会話」。持ち帰りの注文まで）。
const _DELIVERY_AFTER_SECOND := [
	"配達員「2杯目の共通会話（持ち帰りを注文）」",
]

## 持ち帰りの提供後〜退店（会話稿「三杯目・提供と退店」。SERVE の後）。
const _DELIVERY_EXIT := [
	"配達員「退店（会計・名前は阿強）」",
]


## 新人警官（Day2で初登場・表示名「警官」）。本番用会話稿「Day2_新人警官_1.md」。
## 昼の市場（PREP。ベース入手の後・市場の前）と、夜の来店（宵の口）の2部構成。
##   - 要求タグは昼の市場の会話で先に出す（仕入れの前に知る必要がある）。好物（米麺）は夜の来店会話で出す。
##   - 夜は通常の1杯客（GREET → ADJUST → SERVE → REACT → 共通会話 → 会計・退店）。
##     評価（GREAT/GOOD/OK/BAD）で分岐するのは REACT の反応だけで、その後の共通会話と
##     会計・退店は、どの結果でも同じ内容を出す。
##   - 「西側は……」は任意の違和感で、Day2時点でスパイと断定できる材料にしない。
##   - 他のメイン客の、その日の具体的な行動は台詞で確定させない（再来店客との順番に依存させない）。
##   - 昼の市場の会話の冒頭のト書きは、場面を始めるために足したもの（原案に無い）。
##
## 昼・市場（PREP）。
const _OFFICER_MARKET := [
	"警官（市場・要求タグ: SOUR/BITE）",
]

## 夜・来店（宵の口）。REACT の前の GREET。§9-C「データの外部化」で
## res://data/customers/officer.json（days."2".greet）へ移した（重複を避けるため
## 定数としては持たない。中身を見るならJSON側を参照）。

## 提供後・共通会話（料理の結果に関係なく必ず表示）。
const _OFFICER_AFTER := [
	"警官（提供後・共通会話）",
]

## 会計・退店（共通会話の後。料理の結果に関係なく同じ内容）。
const _OFFICER_PAYMENT := [
	"警官（会計・退店）",
]

## 警官の反応文（結果ごとに短い会話を改行でつないだ1つの文字列。各結果の配列は要素数1）。
## §9-C「データの外部化」で res://data/customers/officer.json（days."2".reactions）へ
## 移した（重複を避けるため関数としては持たない。中身を見るならJSON側を参照）。


## Day1開始時の初期在庫（DESIGN.md 7.7）。塩漬けライム・苦瓜は含めない
## （苦瓜は市場で買って初めて手に入る、という導線を保つため。定義自体はIngredientsに残したまま）。
## 調味料3種と具材4種で数量に差をつける：
##   調味料（少量で効く・味付け的な使い方）は多め＝各10個
##   具材（実際の食材として消費される）は少なめ＝各4個。初日から在庫を気にする場面を作る
## soup_base（食肉仲卸のベース）はここに含めない＝ADJUSTの対象外の別枠。
## Day1経済監査（2026-09-26 planning/playtest_2026_09_26/agent_mechanics.md §2）で
## 判明した不足の直し方：Day1の実際の注文は9杯ではなく13杯（配達員2杯・宵の口モブ
## dock_workers4人・夜半モブ4人・チンピラ1杯・老婆1杯。配達員の3杯目はjudge:falseで
## 判定に関わらないため上記からは除く）で、モツ4＋肉団子4＝POWER8個では
## 「配達員2＋モブ8＝POWER10個」に2個足りていなかった。
## さらに day_schedule.json のDay1・夜半モブは（作業ゲー化対策で全モブの要求タグを
## 多様化したことに合わせて）dock_workers/inn_clerk/market_porterの3種から抽選する
## ようにしたため、どの型が来ても初期在庫だけで応対できる数を計算し直した：
##   dock_workers(HOT+POWER)なら POWER最大10個・HOT最大10個
##   inn_clerk(MELLOW+GENTLE)なら GENTLE最大5個（チンピラ1＋モブ4）・MELLOW最大5個
##   market_porter(HOT+FILLING)なら FILLING最大5個（老婆1＋モブ4）・HOT最大10個
## のどれが来ても崩れないよう、POWER=10（モツ4+肉団子6）・GENTLE=5（豆腐）・
## FILLING=5（割れた餃子皮）に増量した（HOT=10・MELLOW=10は元から十分）。
## 各客が「要求タグ1つに具材1つだけ」の最小構成で作ることを前提にした値なので、
## 余分な具材を追加で使うプレイだと市場が開くDay2を待たずに尽きる可能性がある
## （在庫の余裕を持たせる場合は数値をさらに増やすこと）。
static func initial_inventory() -> Dictionary:
	return {
		"nam_prik_pao": 10, "coconut_milk": 10, "herbal_sauce": 10,
		"offal": 4, "meat_ball": 6, "tofu": 5, "broken_wrapper": 5,
	}


## ADJUSTボタンの表示文言。id→ラベルのみで、
## 在庫の有無・個数は _adjust_options() 側（GameState.inventory）が決める。
## OptionsRow（横並び）に収まるよう、「を入れる」は付けず名前だけにしている。
## pickled_lime・bitter_meronのように今は初期在庫に無い（＝市場等で買わないと出てこない）
## idの分も、買った瞬間ラベル無しにならないよう先に用意しておく。
const _ADJUST_LABELS := {
	"nam_prik_pao": "ナムプリックパオ", "coconut_milk": "ココナッツミルク",
	"pickled_lime": "塩漬けライム", "herbal_sauce": "薬膳ナンプラーだれ",
	"bitter_melon": "苦瓜", "offal": "下処理したモツ",
	"meat_ball": "肉団子", "tofu": "豆腐",
	"broken_wrapper": "割れた餃子皮", "winter_melon": "冬瓜",
	"cartilage": "軟骨", "tendon_meat": "すじ肉", "dried_wood_ear": "乾燥きくらげ",
	"rice_noodle": "米麺", "shrimp": "海老", "clam": "貝", "fish_maw": "魚の浮き袋",
}


## ADJUSTの選択肢（DESIGN.md 9.5 STEP17.6 → 7.7で在庫連動に変更）。
## 全客共通なのでここに1箇所だけ置く。GameState.inventory にある id だけを出す
## （＝在庫が選択肢を決める）。remove_inventory は0以下でキーごと削除する仕様なので、
## 辞書に残っている＝在庫1個以上、のチェックは不要。
## 鮮度: 腐る品目は「傷んでいない分」と「傷んだ分」を別ボタンにする（傷んだ側は
## "damaged": true とラベル末尾の「(傷)」。キーが無ければ傷んでいない側）。腐らない品目は
## damaged_count が常に0なので今までどおり1つ。どちらのボタンを押したかが判定を決める
## （傷んだボタン＝-1段階）。その側の在庫が0のボタンは出さない。
static func _adjust_options() -> Array:
	var options := []
	for id in GameState.inventory:
		if id == "soup_base":   # 鍋のベースはADJUSTの対象外
			continue
		# 日数は夜の間に変わらないので、接客開始時に組み立てる既存の扱いのままでよい。
		var label: String = _ADJUST_LABELS.get(id, str(id))
		if GameState.fresh_count(id) > 0:
			options.append({ "id": id, "label": label })
		if GameState.damaged_count(id) > 0:
			options.append({ "id": id, "label": label + "(傷)", "damaged": true })
	return options


## 客ごとに変わる差分だけ（売上は DESIGN.md 6章の Day1 台本準拠：45 / 40 / 55）。
## STEP 17.5: greetは複数行の配列。
## STEP 17.6: wanted_tags は「味の軸＋具の軸」の2つ（DESIGN.md 9.5 STEP17.6）。
##   会話の中に両方の手がかりを置く（例：配達員＝辛くしてくれ／疲れて眠い → HOT + POWER）。
##   reactions は判定結果をキーにした辞書。各段階2パターンで、どちらを出すかはランダム。
##   favorite は好物の具材id（1つ）。椀に入っていれば評価が1段上がる（クリティカル）。
## §9-C「データの外部化」：客の会話・要求タグ・favorite・reactions・servingsは
##   ScheduleData.customer_data()（res://data/customers/<id>.json）へ外部化した。
##   ここでは「どのデータ源を読むか」の出し分けだけを行う（データそのものは持たない）。
##   delivery_man は初日だけ customer_events が専用の Event 列（_delivery_man_events）を
##   返すため、その間は is_mob・wanted_tags・favorite だけ使う。2日目以降に配達員が
##   再来店したときは（客の番数請求は1杯に減る）、他の客と同じ下の汎用の返り値を使う
##   （customers/delivery_man.json の "days"."1" エントリへフォールバックする内容）。
## モブ（DESIGN.md 7.6）は、まず_mob_instances（customer_schedule()が枠ごとに独立抽選
##   した結果）を見る。あれば、そのインスタンスの型でScheduleData.mob_data()を読む
##   （favorite は持たない＝GREAT は出ない。個人の好物は「その人を知っているから分かる」
##   もので、一見の集団には無い。servingsはそのインスタンスの人数）。引数のmob_countは
##   モブに対しては使わない（枠ごとに独立して決めた人数を使うため。互換のため引数
##   自体は残す）。
## 未知 id（JSONファイルが無い等）は無音・売上0・wanted_tags 空（＝一致0なので常に BAD）
##   でフォールバックする（既存どおり。ScheduleDataは空辞書を返すのでそこで判別する）。
static func _customer_flavor(customer_id: String, mob_count: int = 0) -> Dictionary:
	if _mob_instances.has(customer_id):
		var inst: Dictionary = _mob_instances[customer_id]
		var mob := ScheduleData.mob_data(str(inst.get("type", "")))
		if mob.is_empty():
			return _unknown_customer_flavor()
		var count := int(inst.get("count", 0))
		var greet := []
		for line in mob.get("greet", []):
			greet.append(_format_mob_greet(str(line), count))
		return { "greet": greet, "reactions": mob.get("reactions", {}),
			"servings": count, "is_mob": true,
			"wanted_tags": mob.get("wanted_tags", []), "favorite": "" }
	var data := ScheduleData.customer_data(customer_id, GameState.day_count)
	if data.is_empty():
		return _unknown_customer_flavor()
	if customer_id == "delivery_man" and GameState.day_count == 1:
		# 初日は_delivery_man_events()が専用のEvent列を組む（greet/reactions/servingsは
		# 使わない＝ここでは返さない）。2日目以降は下の汎用の返り値（他の客と同じ形）を使う。
		return { "is_mob": data.get("is_mob", false),
			"wanted_tags": data.get("wanted_tags", []), "favorite": data.get("favorite", "") }
	return { "greet": data.get("greet", []), "reactions": data.get("reactions", {}),
		"servings": int(data.get("servings", 1)), "is_mob": data.get("is_mob", false),
		"wanted_tags": data.get("wanted_tags", []), "favorite": data.get("favorite", "") }


## モブのgreet 1行を仕上げる（旧_format_dock_greetを改名。dock_workers専用ではなく
## 全モブ種で使う）。"%d"を含む行だけ人数を埋め込み、含まない行（素の台詞）はそのまま
## 返す（GDScriptの % 演算子はプレースホルダの無い文字列に値を渡すと実行時エラーに
## なるため、含む行だけに絞る）。
static func _format_mob_greet(line: String, count: int) -> String:
	if line.contains("%d"):
		return line % count
	return line


## 未知id・データ無しのフォールバック（既存どおり）。
static func _unknown_customer_flavor() -> Dictionary:
	return { "greet": ["客「……。」"],
		"reactions": {
			"GREAT": ["客、無言。", "客、無言。"],
			"GOOD": ["客、無言。", "客、無言。"],
			"OK": ["客、無言。", "客、無言。"],
			"BAD": ["客、無言。", "客、無言。"],
		},
		"servings": 0, "is_mob": false, "wanted_tags": [], "favorite": "" }


## REACT の後ろに差し込む客ごとの追加 Event（DESIGN.md 4章「pay を1つ挿すだけ」）。
## STEP 8: チンピラの場所代。Day2 の分岐テスト: 「徴収日のみ」に条件化する。
##   - 徴収日の判定は GameState.is_collection_day()（データ関数が事実を読んで出し分け。
##     処理の埋め込みではなく「どの Event を出すか」の判断なので分離方針に反しない）
##   - 金額処理は既存の DebugPanel._apply_event "PAY" 枝（apply_money(-amount)）のまま
##   - 専用 State は作らない（確定事項どおり単なる Event）
##   - thug 以外、または徴収日でない日は空配列
## STEP 17.5: 判定結果に関わらず入る掛け合い（2行）。1行目のチンピラの台詞にPAYの効果を
##   乗せ、2行目の主人公の返しは効果無しのTEXTにする（GREETと同じ「1行1Event」の形）。
## "kind": "rent" は、この PAY が場所代であることを示す印（DebugPanel._apply_event が
##   GameState.mark_rent_paid() を呼ぶかどうかの判定に使う。CURRENT_SPEC.md §11
##   「未解決：閉店で場所代を避けられる」の直し方の一部）。
static func _customer_extra_events(customer_id: String) -> Array:
	# 新人警官：評価の結果に関係なく、REACT の後に同じ共通会話と会計・退店を出す（PAYは無い＝
	# 会計は台詞だけ。売上は REACT の sale で反映済み）。
	if customer_id == "officer":
		return _talk("officer", _OFFICER_AFTER + _OFFICER_PAYMENT)
	if customer_id == "thug" and GameState.is_collection_day():
		return [
			{ "type": "PAY", "customer": "thug", "amount": GameState.RENT_PRICE, "kind": "rent",
				"text": "チンピラ（場所代）" },
		]
	return []
