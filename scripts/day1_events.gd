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

## 日々の運営費（DAILY_OPERATING_COST）は、ここではなくDebugPanel._set_runner_for_phase
## (WAKE)が直接支払う（Eventとしては持たない）。理由：WAKEは_phase_can_skip=trueで
## [次のPhase]がrunnerを消化せず先へ進めるため、支払いをPAY Eventとして置くと毎回
## スキップされてしまう（場所代・水道代の再編＋日々の運営費で確認済み）。ここに置く
## 3つ目のTEXTは、既に支払い済みであることを見せるだけの表示専用の行（効果は持たない）。
## 「共同水道と炭屋」という具体的な行き先にしているのは、実際に支払いが完了する
## （物語上のけじめが付く）タイミングを市場を出るとき（prep_after_tier_events参照）に
## 見せるため、ここでは「まとめて渡す分を先に取っておく」という前振りにしてある。
static func wake_events() -> Array:
	# システム整理D：スマホを見た後に、その日のニュースとDM（News.morning_events）を必ず差す。必須情報を
	# 客の会話に頼らず届けるため。ニュースの無い日は従来の列と同一。表示だけで、数値には触れない。
	return [
		{ "type": "TEXT", "text": "……目が覚めた。まだ薄暗い店の奥。" },
		{ "type": EventRunner.TYPE_WAIT_INPUT, "text": "スマホを見る。" },
	] + News.morning_events(GameState.day_count) + _wake_common_events() + [
		{ "type": "TEXT", "text": "共同水道と炭屋への払い（¥%d）は、市場を出るときにまとめて渡す分として先に取っておく。" % GameState.DAILY_OPERATING_COST },
		{ "type": "TEXT", "text": "さて、準備へ向かうか。" },
	]


## 朝（at:"wake"）の共通イベントの TEXT（ニュースの後）。無い日は空配列。
static func _wake_common_events() -> Array:
	var events := []
	for item in News.pending_events(GameState.day_count, [], "wake"):
		events.append_array(News.event_lines(item))
	return events


## 仕込みの3段階（BALANCE_REDESIGN_PLAN.md§2「7日版の数値一式」）。MARKETの
## *_goods()と同じ置き場所・schema思想（id/label/price + この場合はservings）。
## 小仕込みの価格(80)は独立した定数（旧GameState.BASE_PRICEは予備ベース購入専用の
## 値だったが、濃さメカニクス三点セットで予備ベースごと廃止した）。
## F1キャンペーン設定（DESIGN.md 10.8.1）：価格・杯数の実体はRules.prep_tiers()
## （data/campaigns/week7.jsonのeconomy.prep_tiers、[servings, price]の数値ペア配列）
## へ移した。id/labelは表示用でキャンペーン設定のスキーマに無いため、ここでRules側の
## 並び順に対応づけて重ねる（_PREP_TIER_IDSの並びとJSON配列の並びが一致している前提。
## 既存の呼び出し側（prep_tier_options()・prep_tier_by_id()・PREP_TIERS[0]等）が読む形
## {id, label, price, servings} は変えていないので無改修で動く）。
const _PREP_TIER_IDS := ["small", "medium", "large"]
const _PREP_TIER_LABELS := { "small": "小仕込み", "medium": "中仕込み", "large": "大仕込み" }
static var PREP_TIERS := _build_prep_tiers()


static func _build_prep_tiers() -> Array:
	var pairs := Rules.prep_tiers()
	var result := []
	for i in range(pairs.size()):
		var id: String = _PREP_TIER_IDS[i]
		result.append({ "id": id, "label": _PREP_TIER_LABELS[id],
			"servings": int(pairs[i][0]), "price": int(pairs[i][1]) })
	return result


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
	# 初日セット（DESIGN.md 10.3.4）：day_overrides.kit（Day1のみ"day1_kit"）が
	# 宣言されている日だけ、仕込み量を選ぶ前に固定の購入イベントを差し込む。
	# 自由な買い物ではない（DESIGN.md §6「Day1は自由な買い物なし」を維持）ので
	# MARKETのようなプレイヤー操作は挟まず、進行に乗せるだけの一方向イベントにする。
	# _scraps_base（このすぐ後の分岐）はWAKE直後・このセット購入前の所持金で
	# 既に決まっている（debug_panel.gd._set_runner_for_phase(PREP)参照）。Day1の
	# 初期現金(600)では購入順序を入れ替えても結果は変わらない数値のため、あえて
	# 処理順序（_scraps_base判定→PREP突入→このセット購入）の入れ替えはしない。
	var kit_id := str(Rules.day_overrides(GameState.day_count).get("kit", ""))
	if kit_id != "":
		events.append_array(_kit_purchase_events(kit_id))
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


## 初日セット（DESIGN.md 10.3.4）の購入Event列。kit_idからdata/kits/<id>.jsonを読み、
## 合計額をPAY（kind:"kit"）で払い、各品目をADD_ITEM（unit_price付き）で受け取る。
## 濃縮だし（idが"dashi"）は在庫ではないため、受け側（debug_panel.gd._apply_event）が
## 市場の購入ハンドラ（_on_shop_item_selected）と同じ前例でGameState.buy_dashi()へ
## 振り分ける。
static func _kit_purchase_events(kit_id: String) -> Array:
	var kit := ScheduleData.kit_data(kit_id)
	var items: Array = kit.get("items", [])
	var total := 0
	for good in items:
		total += int(good.get("price", 0))
	var events := [
		{ "type": "TEXT", "text": "いつもの仕入れ先で、仕込みに使う分をまとめて受け取った。" },
		{ "type": "PAY", "amount": total, "kind": "kit", "text": "初日セット" },
	]
	for good in items:
		var count: int = int(good.get("count", 1))
		var price: int = int(good.get("price", 0))
		events.append({ "type": "ADD_ITEM", "item": str(good.get("item", "")),
			"amount": count, "unit_price": int(price / count) if count > 0 else price })
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
	# ベース入手の後・市場の前に、今日来る常連の場面が持つ昼の市場の会話（market_talk）を挟む
	# （新人警官の初登場＝officer_01。要求タグを仕入れの前に知らせるため）。市場の enabled とは
	# 無関係に、会話は必ず出る。日番号の直書きではなく、場面データから引く。
	events.append_array(market_talk_events())
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
	var market_open: bool = GameState.day_count >= Rules.market_open_from_day()
	# 「（訪問済み）」は、Day1に自動で済んだ店が押せない理由の説明にだけ付ける。
	# 2日目以降は6店とも買い物のできる店なので、クズ野菜の日でも付けず、押せる
	# （貧しい日こそ端材屋の安い商品が要る。店には何度でも入れる）。
	var meat_label := "食肉仲卸"
	var scraps_label := "端材半端物"
	if not market_open:
		if scraps_base:
			scraps_label += "（訪問済み）"
		else:
			meat_label += "（訪問済み）"
	return [
		{ "id": "meat_wholesale", "label": meat_label, "enabled": market_open },
		{ "id": "produce",        "label": "青果",       "enabled": market_open },
		{ "id": "dry_goods",      "label": "乾物調味料", "enabled": market_open },
		{ "id": "tofu_noodles",   "label": "豆腐麺",     "enabled": market_open },
		{ "id": "seafood",        "label": "海鮮",       "enabled": market_open },
		{ "id": "scraps",         "label": scraps_label, "enabled": market_open },
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
## → STEP 7: 3人 → §9-C: 日ごとの構成をデータから組み立てる汎用ロジックに変更
## （day1_events.gd側にはもう客IDのif/matchを持たない）。
## 4-3：常連は抽選ではなく固定日程（data/schedules/week7_regulars.json・10.5.1の21枠）。
## モブの抽選ルールはdata/schedules/mob_rules.json。4-4a：ScheduleData.regular_slots()を
## 直接読み、各枠に regular_id・episode_id を持たせる（互換層は撤去）。
## 7.6: フラットな配列をやめ、**時間帯で区切る**（宵の口 / 夜半 / 明け方）。
##   時間帯名と客リストを1つの辞書に同居させる（名前を別配列で並行管理しない）。
## 定義の無い日（Day8以降）は枠が無く、空の配列を返す（客なし）。
##   ここでは「今日の枠構成」をそのまま信じて組み立てるだけでよい。
## 常連のいない枠（想定外）は regular_id="" のまま customers=[]（モブのみ）になるだけで安全。
##
## モブの独立抽選（Day2-7ダミーデータ・モブ抽選独立化 → ④評判の更新+⑤客数の決め方で
## Day2以降のauto経路をtotal_demand_today()ベースへ置き換え）。
## 枠ごとに決めたモブの（型・人数）は、customersに積む文字列自体を"mob#N"という
## その日だけのインスタンスidにし、GameState.today_plan["mob_instances"]へ退避しておく
## （客の番が来てcustomer_events()→_customer_flavor()が呼ばれるときに引けるようにする
## ため。OpenController・debug_panel.gdはcustomersを不透明な文字列としてしか見ないので、
## この2つは無改修で動く）。F2 DayPlan（DESIGN.md 10.8.2）：この辞書はGameStateへ移した
## ので、customer_schedule()の呼び出しごとに明示的に空へ差し替える（前日分・前回呼び出し
## 分を持ち越さない）。
##
## debug_mob_count（-1=自動、0以上=QA用の一律上書き）が無いとき、その日にF1
## day_overrides（DESIGN.md 10.9・10.3.3）で固定モブ編成が宣言されていれば（Day1の
## week7.json day_overrides."1".mobsが該当）、それを最優先で使う。mob_rules.jsonの
## Day1の日別上書き（夜半のプール等）は、この固定編成に優先権を譲るためあえて
## 残している（自動編成のDay1では参照されない。デバッグ上書き中は従来どおりslotの
## "mob"フィールドを_pick_mob()経由で見る）。
## day_overridesが無い日（Day2以降）はDay2-7ダミーデータ・モブ抽選独立化のとおり、
## その夜の総需要からメイン客の合計杯数を引いたモブ杯数を先に決め、_plan_mob_groups()
## で組へ配分してから枠へ割り当てる。デバッグ上書きは総需要システムを丸ごとバイパスして
## 全モブ枠へ一律適用する既存挙動のまま（_pick_mob()経由）。
static func customer_schedule(debug_mob_count: int = -1) -> Array:
	GameState.today_plan["mob_instances"] = {}
	# 4-4a：常連の固定日程（week7_regulars.json）を直接読む（互換層は撤去）。各枠は
	# { name, regular_id, episode_id, mob }。mobはmob_rules.jsonの規則（false｜{pool}）で、
	# _plan_mob_groups()・_pick_mob()・_pick_mob_type()へ従来と同じ形で渡す。
	var slots: Array = []
	var main_ids := []
	var episode_ids := []
	for entry in ScheduleData.regular_slots(GameState.day_count):
		var slot_name := str(entry.get("slot", ""))
		var regular := str(entry.get("regular", ""))
		# 4-4b-2：場面を選ぶ（日程の静的idを第一候補に、requires・not_seenを満たす場面。
		# 既存データ＝requiresなしでは、必ず静的idと同じ）。今日の頼みも場面から枠へ写す。
		var episode_id := EpisodeSelector.select(regular, str(entry.get("episode_id", "")))
		slots.append({ "name": slot_name, "regular_id": regular, "episode_id": episode_id,
			"today_request": ScheduleData.episode_today_request(regular, episode_id),
			"mob": ScheduleData.mob_rule_for(GameState.day_count, slot_name) })
		main_ids.append(regular)
		episode_ids.append(episode_id)

	var fixed_mobs: Array = Rules.day_overrides(GameState.day_count).get("mobs", []) \
		if debug_mob_count < 0 else []
	var use_fixed_mobs: bool = not fixed_mobs.is_empty()
	# 総需要システムを使うのは、デバッグ上書きが無く、その日に固定モブ編成が宣言されていない日。
	# 「Day1は使わない」は日番号ではなく、Day1の固定編成（day_overrides."1".mobs）が表す
	# （システム整理Aで day_count > 1 の直書きを外した。現行データでは動作は同一）。
	var use_demand_system: bool = debug_mob_count < 0 and not use_fixed_mobs
	var mob_groups_by_index := {}
	if use_demand_system:
		var main_total := 0
		for mi in range(main_ids.size()):
			if main_ids[mi] != "":
				# 選んだ場面の杯数で数える（DayPlanはまだ無いので、場面idを直接渡す）。
				main_total += _customer_total_servings(main_ids[mi], episode_ids[mi])
		var mob_cups: int = maxi(GameState.total_demand_today() - main_total, 0)
		mob_groups_by_index = _plan_mob_groups(slots, mob_cups)

	var mob_seq := 0
	var result := []
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var slot_name := str(slot.get("name", ""))
		var customers := []
		if main_ids[i] != "":
			customers.append(main_ids[i])
		if use_fixed_mobs:
			for mob_override in fixed_mobs:
				if str(mob_override.get("slot", "")) != slot_name:
					continue
				var instance_id := "mob#%d" % mob_seq
				mob_seq += 1
				GameState.today_plan["mob_instances"][instance_id] = {
					"type": str(mob_override.get("type", "")),
					"count": int(mob_override.get("count", 0)) }
				customers.append(instance_id)
		elif use_demand_system:
			for size in mob_groups_by_index.get(i, []):
				var type_id := _pick_mob_type(slot)
				if type_id == "":
					continue
				var instance_id := "mob#%d" % mob_seq
				mob_seq += 1
				GameState.today_plan["mob_instances"][instance_id] = { "type": type_id, "count": size }
				customers.append(instance_id)
		else:
			var mob := _pick_mob(slot, debug_mob_count)
			if not mob.is_empty():
				var instance_id := "mob#%d" % mob_seq
				mob_seq += 1
				GameState.today_plan["mob_instances"][instance_id] = mob
				customers.append(instance_id)
		# OpenController・Forecastが読むのはname・customers（不透明な文字列）。regular_id・
		# episode_idは、場面を引くDay1Events.episode_id_of()の元（DayPlanが持つ。4-4a）。
		result.append({ "name": slot_name, "customers": customers,
			"regular_id": str(slot.get("regular_id", "")),
			"episode_id": str(slot.get("episode_id", "")),
			"today_request": (slot.get("today_request", {}) as Dictionary).duplicate(true) })
	return result


## 1人の客の合計servings（そのcustomer_events()の全REACT Eventのservingsを合算する）。
## 総需要からメイン客分を差し引く計算（customer_schedule）用。_customer_flavor().servingsを
## 直接見ないのは、配達員のDay1（3杯を別々のREACTに分ける専用Event列）のような
## 「1客で複数REACT」の形にも自動的に対応するため（配達員Day1は合計3になる）。
static func _customer_total_servings(customer_id: String, scene_id: String = "") -> int:
	var total := 0
	for ev in customer_events(customer_id, 0, scene_id):
		if ev.get("type", "") == "REACT":
			total += int(ev.get("servings", 0))
	return total


## モブ杯数を1〜4人の組へ均等配分し（大きい組から先。BALANCE_REDESIGN_PLAN.md§5原文）、
## その日の枠index（日程の枠の並び順）へ割り当てる。返り値は
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
## 抽選。同日内の重複除外はしない。3-1節確定）。
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


## モブの種類id（"dock_workers"等）→表示名（"港湾労働者"等）。3-7 朝の一画面（予報）が
## 人数・組数を出さずに客層の種類だけを並べるために、data/mobs/*.jsonの"name"を読む。
## 未知の種類・"name"の無いデータは種類id自体を返す（クラッシュしない）。
static func mob_display_name(type_id: String) -> String:
	return str(ScheduleData.mob_data(type_id).get("name", type_id))


## id がモブ客か（DESIGN.md 7.6）。自動閉店の判定などで、受け側が
## 「これより後に名前あり客が残っているか」を問い合わせるために公開する。
static func is_mob_customer(customer_id: String) -> bool:
	return bool(_customer_flavor(customer_id).get("is_mob", false))


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
## scene_id（省略可）：場面idを直接指定する（DayPlanがまだ無いcustomer_schedule()の途中で、
## 選んだ場面の杯数を数えるため。省略すれば episode_id_of() で引く）。
static func customer_events(customer_id: String, mob_count: int = 0, scene_id: String = "") -> Array:
	# 複数杯の場面（場面データの cups。システム整理E。Day1の配達員の「1杯ずつ3回」＝delivery_man_01）は、
	# 同じ客へ複数の杯を1杯ずつ会話の合間に出す専用の列（_cups_events）。客や場面idの直書きは無く、
	# 場面データに cups があるかだけで決まる（DESIGN.md 10.8.6・10.9）。2回目以降の来店
	# （delivery_man_02〜）は、他の客と同じ通常の1杯の流れ（下の汎用ロジック）を使う。
	var scene := scene_id if scene_id != "" else episode_id_of(customer_id)
	if not ScheduleData.episode_cups(customer_id, scene).is_empty():
		return _cups_events(customer_id, scene)
	var flavor := _customer_flavor(customer_id, mob_count, scene)
	var events := []
	# 来店の前に「前回の料理を読んだ2行」（場面にcallbackがあるときだけ。現行の21場面は無し）。
	for line in _callback_lines(customer_id, scene):
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	# 注文の前の行（場面にpre_orderがあるときだけ。前回の2行と注文の間。現行の21場面は無し）。
	for line in ScheduleData.episode_pre_order(customer_id, scene):
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	for line in flavor["greet"]:
		events.append({ "type": "GREET", "customer": customer_id, "text": line })
	events.append({ "type": "ADJUST", "customer": customer_id, "text": "（味を調える）",
		"options": _adjust_options() })
	events.append({ "type": "SERVE", "customer": customer_id, "text": "「はいよ、お待ち。」" })
	var react := { "type": "REACT", "customer": customer_id,
		"reactions": flavor["reactions"], "wanted_tags": flavor["wanted_tags"],
		"favorite": flavor["favorite"], "servings": flavor["servings"],
		"is_mob": flavor["is_mob"],
		"sale": GameState.PRICE_PER_SERVING * int(flavor["servings"]) }
	# 今日の頼みがあるときだけ、基本注文（いつもの）を残す（wanted_tagsは実効注文）。無い場面
	# （現行の21場面）はキー自体を付けない＝従来のREACTと同一。朝の予報（Forecast）は基本注文。
	if flavor.has("base_wanted_tags"):
		react["base_wanted_tags"] = flavor["base_wanted_tags"]
	events.append(react)
	events.append_array(_customer_extra_events(customer_id))
	return events


## 複数杯の場面か（場面データに cups がある）。提供後の列・注文カード・[聞き直す]など「1杯の場面だけの
## 機能」を出さない判定を、ここ1つに統一する（客idや場面idは直書きしない）。
static func is_multi_cup_scene(customer_id: String, scene_id: String) -> bool:
	return not ScheduleData.episode_cups(customer_id, scene_id).is_empty()


## 複数杯の場面（場面データの cups）の Event 列：来店会話（greet）→ 各杯（ADJUST → SERVE → REACT →
## その杯の after_talk）。2杯目以降の ADJUST は new_bowl:true。全 REACT は servings:1・aggregate:true
## （鍋の消費と売上はその場で、評判と提供記録は退店時に客1人分として1回だけ。受け側は変えない）。
## 杯の要求タグ（tags）省略＝プロフィールの wanted_tags、好物（favorite）省略＝プロフィールの好物
## （false なら REACT に favorite のキーを付けない）、反応（reactions）省略＝空（反応を出さない）。
## 状態を読むだけ（乱数なし・何度呼んでも同じ）。
static func _cups_events(customer_id: String, scene_id: String) -> Array:
	var cups := ScheduleData.episode_cups(customer_id, scene_id)
	var flavor := _customer_flavor(customer_id, 0, scene_id)
	var options := _adjust_options()
	var sale: int = GameState.PRICE_PER_SERVING * 1
	var events := []
	events.append_array(_talk(customer_id, ScheduleData.episode_data(customer_id, scene_id).get("greet", [])))
	for i in range(cups.size()):
		var cup: Dictionary = cups[i]
		var adjust := { "type": "ADJUST", "customer": customer_id,
			"text": str(cup.get("adjust", "（味を調える）")), "options": options }
		if i > 0:
			adjust["new_bowl"] = true
		events.append(adjust)
		events.append({ "type": "SERVE", "customer": customer_id, "text": str(cup.get("serve", "「はいよ、お待ち。」")) })
		var react := { "type": "REACT", "customer": customer_id, "servings": 1, "sale": sale,
			"reactions": (cup.get("reactions", {}) as Dictionary).duplicate(true),
			"wanted_tags": (cup.get("tags", flavor["wanted_tags"]) as Array).duplicate(),
			"is_mob": false, "aggregate": true }
		if bool(cup.get("favorite", true)):
			react["favorite"] = flavor["favorite"]
		events.append(react)
		events.append_array(_talk(customer_id, cup.get("after_talk", [])))
	return events


## その客の今日の場面id（4-4a。会話・要求・杯数を引く元）。引き方：
##   1. DayPlan（today_plan）がその日のもの（today_plan["day"] == day_count）なら、
##      regular_idがこの客の枠のepisode_id。日が違う（DayPlanner.build()の途中、または
##      テストが日を進めて続けて呼ぶ）ときは使わない＝前日の枠で別の日の場面を引かない
##      （例：Day1の配達員の3杯列がDay2の杯数計算に混ざる）。
##   2. なければ、その日の日程（regular_slots(day)）の枠。
##   3. それでも無ければ（日程に無い客）、その客の最後の場面（3杯列の最初の場面を踏まない）。
##   客でない（モブのインスタンスid等）・場面が無い客は空文字。
static func episode_id_of(customer_id: String) -> String:
	var plan: Dictionary = GameState.today_plan
	if int(plan.get("day", -1)) == GameState.day_count:
		for slot in plan.get("slots", []):
			if str(slot.get("regular_id", "")) == customer_id and str(slot.get("episode_id", "")) != "":
				return str(slot["episode_id"])
	for entry in ScheduleData.regular_slots(GameState.day_count):
		if str(entry.get("regular", "")) == customer_id:
			return str(entry.get("episode_id", ""))
	var ids := ScheduleData.customer_episode_ids(customer_id)
	return str(ids[ids.size() - 1]) if not ids.is_empty() else ""


## 今日来る常連の場面（客id・場面id）を、枠の順に返す。今日のDayPlanがあればその枠
## （regular_id・episode_id）、無ければ日程（regular_slots）の枠。episode_id_of() と同じ引き方。
static func _todays_scenes() -> Array:
	var scenes := []
	var plan: Dictionary = GameState.today_plan
	if int(plan.get("day", -1)) == GameState.day_count:
		for slot in plan.get("slots", []):
			if str(slot.get("regular_id", "")) != "" and str(slot.get("episode_id", "")) != "":
				scenes.append({ "customer": str(slot["regular_id"]), "episode_id": str(slot["episode_id"]) })
		return scenes
	for entry in ScheduleData.regular_slots(GameState.day_count):
		if str(entry.get("regular", "")) != "" and str(entry.get("episode_id", "")) != "":
			scenes.append({ "customer": str(entry["regular"]), "episode_id": str(entry["episode_id"]) })
	return scenes


## 昼の市場の会話（場面データの market_talk）。PREPの市場の前に差す Event 列（_talk と同じ形）。
## 今日来る場面が market_talk を持つものだけ、枠の順に全部出す（同じ場面は1回）。持つ場面が
## 無い日は空。一度見た場面でも出す（seen_episodesは見ない：今の割り当てでは影響が無く、
## 同じ場面が複数日に来る設計になった時点で決める）。状態を読むだけで書かない。
static func market_talk_events() -> Array:
	var events := []
	var done := {}
	for scene in _todays_scenes():
		var key := "%s/%s" % [scene["customer"], scene["episode_id"]]
		if done.has(key):
			continue
		done[key] = true
		events.append_array(_talk(str(scene["customer"]),
			ScheduleData.episode_market_talk(str(scene["customer"]), str(scene["episode_id"]))))
	return events


## 提供後の列（DESIGN.md 10.5.3・10.8.6。システム整理C）。REACT の処理が済んだ後に DebugPanel が
## 呼び、返った列を現在位置の直後へ差し込む（来店時に最後まで固定しない＝実際の出来が出た後に組む）。
## 状態を読むだけで書かない（何度呼んでも同じ。乱数も使わない）。EventRunner に条件分岐は入れない
## （どの行を出すかはここで選ぶ）。出来（grade）で本文・締めは分けない：10.5.3「差分は冒頭2行・
## 反応・締めだけ」。わざと失敗すると親密になる経路を作らないため、締めの引き当てに grade を使わない。
##
## outcome：{ served: bool, grade: String }
##   served=true  … 本文（body）→ 締め（closing.default）。反応は REACT の表示（reactions[出来]）
##   served=false … 断った客。must_info を持つ場面だけ未提供版の本文（body_unserved）。反応は
##                  REACT の表示（reactions.UNSERVED）。本文の無い場面は何も差さない
## 各行は { type:"GREET", customer, text, part:"body"|"closing" }。場面データに該当のキーが無い
## （現行の21場面）・モブ・配達員の3杯列は空配列＝従来のイベント列と同一。
static func after_serve_events(customer_id: String, scene_id: String, outcome: Dictionary) -> Array:
	var events := []
	if customer_id == "" or scene_id == "" or is_multi_cup_scene(customer_id, scene_id) or is_mob_customer(customer_id):
		return events
	if bool(outcome.get("served", false)):
		events.append_array(_scene_lines("body", customer_id, ScheduleData.episode_body(customer_id, scene_id)))
		# 店主の距離感の選択（本文の後。選択ごとに入力待ちのCHOICE）。選択がある場面の締めは、最後の
		# 選択が済んだ後に DebugPanel が closing_events() で組んで差し込む（選んだ結果を読むため）。
		var choices := ScheduleData.episode_choices(customer_id, scene_id)
		for choice in choices:
			var options := []
			for option in choice["options"]:
				options.append({ "id": option["id"], "label": option["label"] })
			events.append({ "type": "CHOICE", "customer": customer_id, "choice_id": choice["id"],
				"options": options, "part": "choice" })
		if choices.is_empty():
			events.append_array(closing_events(customer_id, scene_id))
		# 場面が終わったとき（締めを読み終えて先へ進んだとき）に事実を書く。提供しなかった客には
		# 付けない（本文を再生しても事実は立てない）。
		var sets_facts := ScheduleData.episode_sets_facts(customer_id, scene_id)
		if not sets_facts.is_empty():
			events.append({ "type": "SCENE_END", "customer": customer_id, "sets_facts": sets_facts,
				"part": "end" })
	elif not ScheduleData.episode_must_info(customer_id, scene_id).is_empty():
		events.append_array(_scene_lines("body", customer_id,
			ScheduleData.episode_body_unserved(customer_id, scene_id)))
	return events


## 接客中に提供できないまま閉店して退店する客（鍋不足の[閉店]・自動閉店）の未提供版。REACT が
## 適用されないので、反応（reactions.UNSERVED の要素0）も GREET（part:"reaction"）として出し、続けて
## after_serve_events(served=false) の列（must_info を持つ場面だけ未提供版の本文）。DebugPanel が
## CLOSE の先頭に積む。どちらも無い場面（現行の21場面）は空配列＝従来の閉店と同一。
## 到着前に閉店して来なかった客は対象外（場面が始まっていない。必須情報はニュースが担う）。
static func unserved_exit_events(customer_id: String, scene_id: String) -> Array:
	var events := []
	if customer_id == "" or scene_id == "" or is_multi_cup_scene(customer_id, scene_id) or is_mob_customer(customer_id):
		return events
	var reactions = ScheduleData.episode_data(customer_id, scene_id).get("reactions", {})
	if reactions is Dictionary and (reactions as Dictionary).get("UNSERVED", []) is Array:
		var pool: Array = (reactions as Dictionary).get("UNSERVED", [])
		if not pool.is_empty() and pool[0] is String and pool[0] != "":
			events.append({ "type": "GREET", "customer": customer_id, "text": pool[0], "part": "reaction" })
	events.append_array(after_serve_events(customer_id, scene_id, { "served": false, "grade": "" }))
	return events


## 締め（closing）の列。default に、今日の来店で選んだ選択ごとの差分（"<選択id>:<選択肢id>"）を
## 場面の選択の順に足す。差分のキーが無ければ default だけ。足し算で、置き換えではない。
## 出来（grade）は引き当てに使わない（わざと失敗すると親密になる経路を作らない。10.5.3）。
## 今日の来店記録（CustomerMemory）を読むだけで書かない。
static func closing_events(customer_id: String, scene_id: String) -> Array:
	if is_multi_cup_scene(customer_id, scene_id):
		return []
	var closing := ScheduleData.episode_closing(customer_id, scene_id)
	var lines: Array = closing.get("default", []).duplicate()
	var made := CustomerMemory.choices_today(customer_id)
	for choice in ScheduleData.episode_choices(customer_id, scene_id):
		var key := "%s:%s" % [choice["id"], str(made.get(choice["id"], ""))]
		if made.has(choice["id"]) and closing.has(key):
			lines.append_array(closing[key])
	# 約束（今日の頼みに応えたか）の差分。今日の頼みがある場面を提供したときだけ記録がある。
	var visit := CustomerMemory.today_visit(customer_id)
	if visit.has("request_honored"):
		var honored_key := "request_honored:%s" % ("true" if bool(visit["request_honored"]) else "false")
		if closing.has(honored_key):
			lines.append_array(closing[honored_key])
	return _scene_lines("closing", customer_id, lines)


## 提供後の列の1部分（本文・締め）の行を GREET イベントにする。part は列の中の位置の印。
static func _scene_lines(part: String, customer_id: String, lines: Array) -> Array:
	var events := []
	for line in lines:
		events.append({ "type": "GREET", "customer": customer_id, "text": line, "part": part })
	return events


## 前回の来店を読んだ2行（DESIGN.md 10.5.3・10.8.6。4-4b-2）。場面のcallbackから、前回の来店
## （今日より前の最後の来店。CustomerMemory.previous_visit）に応じた行を最大2行返す。出し分け：
##   前回の来店なし                → first
##   前回提供しなかった（served=0） → last_unserved
##   前回の評価が GREAT・GOOD      → last_grade_good_or_better
##   前回の評価が OK・BAD          → last_grade_bad   （キー名は10.8.6のまま。OKもこちら）
##   提供したが評価なし            → last_ungraded（任意。無ければ何も出さない）
## callbackを持たない場面・モブは何も出さない。**評価で料金・評判・関係は変えない**（どの行を
## 読むかを選ぶだけ。好感度の数値は持たない）。失敗した前回にも関係が続く台詞にするのは
## データ側（4-5）の方針。状態を読むだけで書かない（Forecastや杯数の先読みが何度呼んでも
## 副作用が無く、REACTの数・杯数も変わらない）。
static func _callback_lines(customer_id: String, scene_id: String) -> Array:
	var callback := ScheduleData.episode_callback(customer_id, scene_id)
	if callback.is_empty():
		return []
	var previous := CustomerMemory.previous_visit(customer_id)
	var key := "first"
	if not previous.is_empty():
		var grade := str(previous.get("grade", ""))
		if int(previous.get("served", 0)) <= 0:
			key = "last_unserved"
		elif grade == "GREAT" or grade == "GOOD":
			key = "last_grade_good_or_better"
		elif grade == "OK" or grade == "BAD":
			key = "last_grade_bad"
		else:
			key = "last_ungraded"
	var lines := []
	var source = callback.get(key, [])
	if source is Array:
		for line in source:
			if lines.size() < 2:
				lines.append(str(line))
	return lines


## 注文カード（DESIGN.md 10.5.2。4-4b-2）：「いつもの」（基本注文）と「今日の頼み」。
## 戻り値 { base: [タグ], today: [タグ]（無ければ空）, label: 文字列 }。名前あり客以外は空辞書。
static func order_card(customer_id: String) -> Dictionary:
	var profile := ScheduleData.customer_profile(customer_id)
	if profile.is_empty() or bool(profile.get("is_mob", false)):
		return {}
	var today := today_request_of(customer_id, episode_id_of(customer_id))
	return { "base": (profile.get("wanted_tags", []) as Array).duplicate(),
		"today": (today.get("tags", []) as Array).duplicate(), "label": str(today.get("label", "")) }


## その客のその場面の「今日の頼み」（{ tags, label }。無ければ空辞書）。DayPlanがその日の
## もの（today_plan["day"] == day_count）で、場面idが枠のepisode_idと同じなら枠の
## today_request（WAKEで確定した値。再挑戦でも変わらない）、そうでなければ場面データから引く。
static func today_request_of(customer_id: String, episode_id: String) -> Dictionary:
	var plan: Dictionary = GameState.today_plan
	if int(plan.get("day", -1)) == GameState.day_count:
		for slot in plan.get("slots", []):
			if str(slot.get("regular_id", "")) == customer_id 					and str(slot.get("episode_id", "")) == episode_id and slot.has("today_request"):
				return (slot["today_request"] as Dictionary).duplicate(true)
	return ScheduleData.episode_today_request(customer_id, episode_id)


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
## res://data/episodes/officer/officer_01.json（market_talk）へ移した（重複を避けるため
## 定数としては持たない。中身を見るならJSON側を参照）。

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


## Day1開始時の無料在庫（DESIGN.md 10.3.4「無料在庫0」）。3-5でこれまでの無料在庫
## （調味料10個・具材4〜6個の増量版）を廃止し、代わりにPREPで「初日セット」を
## 固定購入するようにした（prep_events()の_kit_purchase_events()参照。中身は
## data/kits/day1_kit.json）。市場は初日はまだ開いていない（market_open_from_day=2）
## ため、このセットがDay1に使える具材の唯一の出どころになる。
static func initial_inventory() -> Dictionary:
	return {}


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
## §9-C「データの外部化」：客の基本プロフィール（is_mob・favorite・wanted_tags）は
##   ScheduleData.customer_profile()（res://data/customers/<id>.json）、会話・reactions・
##   servingsは来店場面 ScheduleData.episode_data()（res://data/episodes/<客>/<id>.json）
##   へ外部化した（4-4a。日番号キーは無い）。ここでは「どのデータ源を読むか」の出し分けだけを
##   行う（データそのものは持たない）。
##   複数杯の場面（cups を持つ場面。Day1の配達員）は customer_events が杯ごとの Event 列
##   （_cups_events）を組み、そこでは is_mob・wanted_tags・favorite だけ使う（杯ごとの反応・注文は
##   場面の cups が持つ）。2回目以降の来店は、他の客と同じ下の汎用の返り値（1杯）を使う。
## モブ（DESIGN.md 7.6）は、まずGameState.today_plan["mob_instances"]（customer_schedule()
##   が枠ごとに独立抽選した結果。F2 DayPlan）を見る。あれば、そのインスタンスの型で
##   ScheduleData.mob_data()を読む（favorite は持たない＝GREAT は出ない。個人の好物は
##   「その人を知っているから分かる」もので、一見の集団には無い。servingsはそのインスタンス
##   の人数）。引数のmob_countはモブに対しては使わない（枠ごとに独立して決めた人数を
##   使うため。互換のため引数自体は残す）。
## 未知 id（JSONファイルが無い等）は無音・売上0・wanted_tags 空（＝一致0なので常に BAD）
##   でフォールバックする（既存どおり。ScheduleDataは空辞書を返すのでそこで判別する）。
static func _customer_flavor(customer_id: String, mob_count: int = 0, scene_id: String = "") -> Dictionary:
	var mob_instances: Dictionary = GameState.today_plan.get("mob_instances", {})
	if mob_instances.has(customer_id):
		var inst: Dictionary = mob_instances[customer_id]
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
	# 4-4a：基本プロフィール（is_mob・favorite・wanted_tags）＋来店場面（greet・reactions・
	# servings。場面idはepisode_id_of）。日番号では引かない。
	var profile := ScheduleData.customer_profile(customer_id)
	if profile.is_empty():
		return _unknown_customer_flavor()
	var episode_id := scene_id if scene_id != "" else episode_id_of(customer_id)
	var episode := ScheduleData.episode_data(customer_id, episode_id)
	var flavor := { "greet": episode.get("greet", []), "reactions": episode.get("reactions", {}),
		"servings": int(episode.get("servings", 1)), "is_mob": profile.get("is_mob", false),
		"wanted_tags": profile.get("wanted_tags", []), "favorite": profile.get("favorite", "") }
	# 複数杯の場面（cups）は杯数＝cups の数（場面直下の servings は持たない）。杯ごとの反応は杯が持つので、
	# 場面直下の reactions は空。
	var cups := ScheduleData.episode_cups(customer_id, episode_id)
	if not cups.is_empty():
		flavor["servings"] = cups.size()
	# 実効注文（DESIGN.md 10.3.2・10.5.2）：基本注文（プロフィールのwanted_tags）を、今日の頼み
	# （場面のorder.today_request.tags）があれば**上書き**する（足し算ではない）。好物・杯数は
	# 変えない。今日の頼みが無ければ従来と同一（base_wanted_tagsも付かない）。
	var today := today_request_of(customer_id, episode_id)
	if not today.is_empty():
		flavor["base_wanted_tags"] = (flavor["wanted_tags"] as Array).duplicate()
		flavor["wanted_tags"] = (today["tags"] as Array).duplicate()
	return flavor


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
##   - 徴収日の判定は、bills[]（Rules.bills_for_scene）が事実を読んで出し分ける（処理の埋め込みではなく
##     「どの Event を出すか」の判断なので分離方針に反しない）
##   - 金額処理は既存の DebugPanel._apply_event "PAY" 枝（apply_money(-amount)）のまま
##   - 専用 State は作らない（確定事項どおり単なる Event）
##   - 今日その客が取り立てる請求が無ければ空配列（thug の場所代も bills[] から引く）
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
	# 今日この客が取り立てる請求（bills[]のsceneがこの客のid・daysに今日を含む）。客idの直書きや
	# is_collection_day() は使わない。kind は請求のid（"rent"＝場所代の印）、金額は請求のamount。
	var collected := []
	for bill in Rules.bills_for_scene(customer_id, GameState.day_count):
		collected.append({ "type": "PAY", "customer": customer_id, "amount": int(bill["amount"]),
			"kind": str(bill["id"]),
			"text": "%s（%s）" % [ScheduleData.customer_display_name(customer_id), str(bill.get("label", bill["id"]))] })
	return collected
