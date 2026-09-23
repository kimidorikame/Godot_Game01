extends Node
## GameState — 日をまたいで残る「事実」だけを持つ autoload シングルトン。
##
## 設計上の役割分担（DESIGN.md 準拠）:
##   - GameState      : 事実のみ・永続。進行度は持たない。
##   - FlowController : 上位フェーズの進行（別ファイル）
##   - EventRunner    : フェーズ内の Event 再生・進行度(index/status)（別ファイル）
##   - OpenController : OPEN 中の客ループ（別ファイル）
##
## ここに status / index / customer_step の類は置かない。
## それらは進行を司る側（EventRunner 等）が持つ。

# --- フェーズ（今どのフェーズか、を GameState が知るためだけに持つ） ---
# GAME_OVER は末尾に足す（既存の0〜4の値は変えない）。水道代・場所代が払えないときに
# force_phase で飛ぶ終端フェーズで、ここからはどこへも進まない。
enum Phase { WAKE, PREP, OPEN, CLOSE, NEXT_DAY, GAME_OVER }

# 一杯の売価（PRICING_SPEC.md：内容にかかわらず50固定）。
# 客ごとのデータではなくゲーム共通のルールなのでここに置く（is_collection_day() と同じ扱い）。
# 評価差は価格ではなく評判・翌日の客数へ反映する（高級具に追加料金は付けない）。
const PRICE_PER_SERVING := 50

# ベース1袋で作れる杯数（PRICING_SPEC.md 5章：1袋80＝10杯分）。
# 値段と同じくゲーム共通のルール。
const SERVINGS_PER_BASE := 10

# ベース1袋の値段（PRICING_SPEC.md 5章）。食肉仲卸での支払いと、所持金がこれに満たない
# ときにクズ野菜ベースへ切り替える閾値の両方で使う（別々の数字にならないよう1箇所に置く）。
const BASE_PRICE := 80

# 場所代（みかじめ・PRICING_SPEC.md 4章）。徴収日のみ。チンピラのPAY Eventの金額と、
# 未払いのまま閉店したときの特別請求（CURRENT_SPEC.md §11「未解決」の直し方）の
# 両方で使う（別々の数字にならないよう1箇所に置く）。
const RENT_PRICE := 150

# 最終日（DESIGN.md/CURRENT_SPEC：7日目のCLOSE後に「（終了）」を出し、翌朝1日目へ巻き戻す）。
# 体験版では 3 にして使っていた。日数を変えるときはここを直接書き換える（切り替えUIは対象外）。
const FINAL_DAY := 7

# 新規ゲーム開始時の初期値。変数宣言と reset_for_new_game() の両方で使う
# （別々の数字にならないよう1箇所に置く）。
const INITIAL_MONEY := 300
const INITIAL_RESERVE_BASE_UNITS := 10

# 評判 → その日のモブ人数（DESIGN.md 7.6「評判→翌日のモブ客数」）。ゲーム共通のルール。
# [評判の下限, 人数の上限] を大きい順に並べ、最初に当たった行を使う。人数は1〜上限の乱数。
# 評判が0未満なら0人（テーブルの外）。数値は仮。上限・逓減の調整は今回は対象外。
const MOB_COUNT_TABLE := [[80, 8], [50, 6], [20, 4], [0, 3]]

# Day1のモブ人数は台本どおり固定（チュートリアルなので揺らさない）。
const DAY1_MOB_COUNT := 4

# 市場で具材を1回買うと足される杯数（DESIGN.md 7.7：具材は5杯分の小分けで販売）。
# ベースと違い袋／単位の2段管理はしない。inventoryの個数＝そのまま使える杯数として持つ
# （将来ADJUSTで消費するとき remove_inventory(id, 1) するだけで済む形にしておく）。
const INGREDIENT_SERVINGS_PER_PURCHASE := 5

# 具材の腐敗（購入日を1日目に数える経過日数。どの品目が腐るかは Ingredients.is_perishable）。
#   1〜2日目 … 新鮮／3日目 … 傷んでいる（使えるが判定が-1段階）／4日目以降 … 自動破棄
# 腐敗の速度は全品目一律（品目ごとに変える仕組みは対象外）。
const SPOIL_DAMAGED_DAY := 3
const SPOIL_DISCARD_DAY := 4

# 鍋の操作の効き方（DESIGN.md 7.6「状態の変化」の表）。値をここに集約する。
const STRENGTH_MIN := 1            # 濃さの下限（水っぽい）
const STRENGTH_MAX := 5            # 濃さの上限（煮詰まりすぎ）
const WATER_DOSES_PER_NIGHT := 2   # 毎朝汲める水の回数（PRICING_SPEC 4章。持ち越さない）
const WATER_SERVINGS := 2          # 水1回： 残量 +2 / 濃さ -1
# ベース追加は残量を増やさず、濃さだけ +1（かさ増しは水の役。DESIGN.md 7.6「味が戻る」）。
const RESERVE_BASE_PURCHASE_UNITS := 10   # 予備ベース1袋の購入で増える単位数（価格は BASE_PRICE）
const BASE_UNITS_PER_ADD := 2      # ベース追加1回で使う単位数（1袋＝10単位）

# --- 永続する事実 ---
var day_count: int = 1
var money: int = INITIAL_MONEY
var reputation: int = 0

# 初期具材・調味料・購入した食材。{ id: 個数 } の辞書（DESIGN.md 7.7：
# 市場での複数購入を表すため、文字列配列から数量辞書に変更）。
# 個数が0になったキーは削除する＝「持っていない」を辞書に無い状態で表現する。
var inventory: Dictionary = {}

# 腐る品目（Ingredients.is_perishable）の購入日別の内訳 { id: [ { "day": 購入日, "count": 個数 }, ... ] }。
# 配列は購入日が早い順（day_count は増える一方なので、末尾へ足すだけで古い順が保たれる）。
# 個数の合計は常に inventory[id] と一致させる。個数0のバッチは取り除き、品目の合計が0に
# なったらキーごと消す。腐らない品目・soup_base は登場しない。経過日数は保存せず都度計算する。
var perishable_batches: Dictionary = {}

# スマホで得た情報の断片。中身の型は Rumor（後で定義）。
var rumors: Array = []

# 追加用ベースの単位数（1袋＝10単位。DESIGN.md 7.6「ベースと水の扱い」）。
# soup の中ではなくここに置く理由：**余った単位は翌日へ持ち越す**ので、
# NEXT_DAY で null になる soup に入れると消えてしまうため（寿命が違う）。
# 初期値は仮。PREP でベース2袋目を買う操作が未実装なので、最初から持たせている。
var reserve_base_units: int = INITIAL_RESERVE_BASE_UNITS

# 予備ベースの購入（食肉仲卸。1周1回）。購入した分だけに期限がある（初期分は対象外）。
# inventory / perishable_batches は再利用しない（予備ベースは在庫の品目ではなく、期限の日数の
# 数え方だけ食材と揃える）。reserve_base_units は「初期分＋購入分」の合計のまま残す。
# purchased は破棄されても true のまま（1周1回の上限）。remaining は購入分のうち未使用の単位数。
var reserve_base_purchased: bool = false
var reserve_base_purchase_remaining: int = 0
var reserve_base_purchase_day: int = 0

# 今どのフェーズか。進行度ではなく「位置」だけ。
var phase: Phase = Phase.WAKE

# --- 日ごとの使い捨て（NEXT_DAY でリセット） ---

# 今日の共有鍋。形は { base_id, tags[] }（STEP 11 で決定）。仕込み前は null。
# 全客で共有され、OpenController からは参照される。客ごとの味付けはここに混ぜず、
# 接客中の Bowl.additions に持たせる（STEP 13 以降）。
# 水量・濃さは持たせない（7.5 の管理要素は STEP 18 以降）。
var soup = null

# 今夜の提供実績。中身の型は ServedRecord（後で定義）。
# 提供人数は served.size() で出す（カウンタは別に持たない）。
var served: Array = []

# 今日の場所代（RENT_PRICE）をもう払ったか（徴収日のみ意味を持つ）。チンピラのPAY
# Event（kind:"rent"）が実際に適用されたときだけ true になる。日ごとの使い捨てで、
# soup/served と同じく reset_for_new_day() でリセットする。
# 用途：徴収日に、チンピラの番より前で閉店（保留中・鍋不足・鍋が尽きての自動閉店）
# すると場所代の支払いEventごと消えてしまう抜け道があったため、閉店の直前に
# 「まだ払っていなければ特別請求する」判定に使う（CURRENT_SPEC.md §11「未解決」参照）。
var rent_paid_today: bool = false


## 日次リセット。NEXT_DAY フェーズの処理から呼ぶ。
## soup・served・rent_paid_today だけをクリアする。money/reputation/inventory は残す。
func reset_for_new_day() -> void:
	soup = null
	served.clear()
	rent_paid_today = false


## 日を1つ進める。reset_for_new_day() の後に呼ぶ想定。
func advance_day() -> void:
	day_count += 1


## 最終日か。>= なので、デバッグの [Day+1] で最終日を飛び越えても最終日扱いのまま
## （is_collection_day() と同じく「今日が何日目か」というルールなのでここに置く）。
func is_final_day() -> bool:
	return day_count >= FINAL_DAY


## 新規ゲームの状態へ戻す（最終日の翌朝に、すべてを1日目に巻き戻す）。
## 「日をまたいで残る事実」は全部ここで初期化する。日ごとの使い捨て（soup・served）は
## 既存の reset_for_new_day() に任せる。
## inventory は空にするだけ。Day1の初期在庫は台本データ（Day1Events.initial_inventory）
## なので、積み直しは受け側（DebugPanel）が game_restarted を受けて行う
## （GameState から台本データへ依存させない）。
func reset_for_new_game() -> void:
	day_count = 1
	money = INITIAL_MONEY
	reputation = 0
	inventory.clear()
	perishable_batches.clear()
	rumors.clear()
	reserve_base_units = INITIAL_RESERVE_BASE_UNITS
	reserve_base_purchased = false
	reserve_base_purchase_remaining = 0
	reserve_base_purchase_day = 0
	phase = Phase.WAKE
	reset_for_new_day()


## 今日が場所代（みかじめ）の徴収日か。GameState は事実だけ持つのでここに置く。
## 7日版なので今は初日のみ。将来 day_count in [1, 7, 14] 等へ広げられる形にしておく。
func is_collection_day() -> bool:
	return day_count == 1


## 評判からその日のモブ人数を決める（乱数を引くので呼ぶたびに値が変わり得る）。
## 呼び出し側は「その日のEvent列を作る時点で1回だけ」呼んで、結果を使い回すこと。
func mob_count_for_reputation(rep: int) -> int:
	if rep < 0:
		return 0
	for row in MOB_COUNT_TABLE:
		if rep >= int(row[0]):
			return randi_range(1, int(row[1]))
	return 0


## 今日のモブ人数。Day1は固定、Day2以降は評判で決まる（is_collection_day() と同じく
## 「今日が何日目か」というルールなので GameState に置く）。
func mob_count_today() -> int:
	if day_count == 1:
		return DAY1_MOB_COUNT
	return mob_count_for_reputation(reputation)


## 金額の増減をまとめて通す入口。
## 支払いも売上も同じここを通す（DESIGN.md「金額処理はすべて money -= x で同じ」）。
## 差はデータ側の text（トーン）で持ち、ここでは数値だけ扱う。
func apply_money(delta: int) -> void:
	money += delta


## 払えなければ実行しない支払いの入口（水道代・場所代など、払えない＝ゲームオーバーになる
## 義務的な支払い用）。払えたら true、足りなければ何もせず false（所持金はマイナスにならない）。
## apply_money に残高チェックを持たせないのは、apply_money が売上（+）・青果の購入・
## デバッグの所持金操作など、負の値でも通ってよい場面と共用の入口だから。
func try_pay(amount: int) -> bool:
	if money < amount:
		return false
	apply_money(-amount)
	return true


## 評判の増減をまとめて通す入口（DESIGN.md 7.6）。apply_money と同じ役割で、
## 「どれだけ動かすか」を決めるのは受け側、ここは適用するだけ。
## 名前あり客とモブで増加量が違う（受け側の増減表で決める）。
func apply_reputation(delta: int) -> void:
	reputation += delta


## 在庫に item を count 個足す入口。ADD_ITEM Event を受けた側から呼ぶ。
## apply_money と同じく「在庫をいじる唯一の入口」を用意し、受け側から
## inventory 辞書を直接触らせない。
## 腐る品目は、購入日別のバッチ（perishable_batches）にも足す（同じ日なら末尾へ合算）。
func add_inventory(item, count: int = 1) -> void:
	inventory[item] = int(inventory.get(item, 0)) + count
	if Ingredients.is_perishable(str(item)) and count > 0:
		var batches: Array = perishable_batches.get(item, [])
		if not batches.is_empty() and int(batches[-1]["day"]) == day_count:
			batches[-1]["count"] = int(batches[-1]["count"]) + count
		else:
			batches.append({ "day": day_count, "count": count })
		perishable_batches[item] = batches


## 在庫から item を count 個抜く入口。add_inventory の裏返し。
## 個数が0以下になったらキーごと削除する（「持っていない」を無い状態で表現する）。
## 該当が無い分・引きすぎた分は黙って0扱いにする（負の在庫は持たない。
## 旧・配列版の「Array.erase は未ヒットでも安全」と同じ安全性を保つ）。
## STEP 4: 「仕込み」で具材を消費するのに使う。soup を埋める処理はまだ持たない。
## 腐る品目はバッチと整合させるため remove_inventory_fresh（古い順）へ委譲する
## （呼び出し元は今 soup_base の仕込み消費だけ＝腐らない品目）。
func remove_inventory(item, count: int = 1) -> void:
	if Ingredients.is_perishable(str(item)):
		remove_inventory_fresh(item, count)
		return
	var remaining: int = int(inventory.get(item, 0)) - count
	if remaining <= 0:
		inventory.erase(item)
	else:
		inventory[item] = remaining


## バッチの経過日数（購入日を1日目とする）。
func _batch_age(batch: Dictionary) -> int:
	return day_count - int(batch["day"]) + 1


## 傷んでいない在庫数。腐らない品目は在庫の全量。
func fresh_count(item) -> int:
	if not Ingredients.is_perishable(str(item)):
		return int(inventory.get(item, 0))
	var total := 0
	for batch in perishable_batches.get(item, []):
		if _batch_age(batch) < SPOIL_DAMAGED_DAY:
			total += int(batch["count"])
	return total


## 傷んだ在庫数（3日目以降。4日目以降は本来PREPで破棄済みだが、残っていても傷んだ側に数える）。
## 腐らない品目は常に0。
func damaged_count(item) -> int:
	if not Ingredients.is_perishable(str(item)):
		return 0
	var total := 0
	for batch in perishable_batches.get(item, []):
		if _batch_age(batch) >= SPOIL_DAMAGED_DAY:
			total += int(batch["count"])
	return total


## 傷んでいない分から古い順に count 個引く。足りなければ傷んだ分で補う。
## どちらのボタンを押したか（判定）は呼び出し側が決める。ここは在庫を引くだけ。
func remove_inventory_fresh(item, count: int = 1) -> void:
	_take_from_batches(item, count, false)


## 傷んだ分から count 個引く。足りなければ傷んでいない分（古い順）で補う。
func remove_inventory_damaged(item, count: int = 1) -> void:
	_take_from_batches(item, count, true)


## バッチを指定の優先順で count 個引き、inventory と整合させる。腐らない品目は素の減算。
## 引きすぎた分は黙って捨てる（remove_inventory と同じ安全設計。負の在庫は持たない）。
func _take_from_batches(item, count: int, damaged_first: bool) -> void:
	if not Ingredients.is_perishable(str(item)):
		remove_inventory(item, count)
		return
	var batches: Array = perishable_batches.get(item, [])
	var left := count
	for pass_damaged in [damaged_first, not damaged_first]:
		var i := 0
		while i < batches.size() and left > 0:
			var batch: Dictionary = batches[i]
			if (_batch_age(batch) >= SPOIL_DAMAGED_DAY) != pass_damaged:
				i += 1
				continue
			var take := mini(int(batch["count"]), left)
			batch["count"] = int(batch["count"]) - take
			left -= take
			if int(batch["count"]) <= 0:
				batches.remove_at(i)
			else:
				i += 1
	_sync_batches(item, batches)


## バッチの合計を inventory へ反映する。合計が0ならキーごと消す。
func _sync_batches(item, batches: Array) -> void:
	var total := 0
	for batch in batches:
		total += int(batch["count"])
	if total <= 0:
		inventory.erase(item)
		perishable_batches.erase(item)
	else:
		inventory[item] = total
		perishable_batches[item] = batches


## 腐りきったバッチ（4日目以降）だけを在庫から消し、消した品目 id → 消した個数の
## Dictionary を返す（日次ログ導入で個数も要るようになったため Array から拡張。
## 呼び出し元は day1_events.gd の prep_events()（`for id in spoiled` でキーを回すだけ）と
## debug_panel.gd のPREP分岐のみで、どちらも Array 時代のまま無改修で動く）。
## 同じ品目の新しいバッチが残れば品目は在庫に残る。
## 呼び出し側（PREPに入る瞬間）が1回だけ呼び、返り値を通知テキスト・日次ログに使う。
func discard_spoiled_inventory() -> Dictionary:
	var discarded := {}
	for item in perishable_batches.keys():
		var batches: Array = perishable_batches[item]
		var kept := []
		var lost := 0
		for batch in batches:
			if _batch_age(batch) < SPOIL_DISCARD_DAY:
				kept.append(batch)
			else:
				lost += int(batch["count"])
		if lost > 0:
			_sync_batches(item, kept)
			discarded[item] = lost
	return discarded


## 予備ベースを1袋買った効果だけを適用する（支払いは呼び出し側）。購入済みなら何もせず false。
func buy_reserve_base() -> bool:
	if reserve_base_purchased:
		return false
	reserve_base_purchased = true
	reserve_base_units += RESERVE_BASE_PURCHASE_UNITS
	reserve_base_purchase_remaining = RESERVE_BASE_PURCHASE_UNITS
	reserve_base_purchase_day = day_count
	return true


## 購入日を1日目とした経過日数（_batch_age と同じ数え方）。
func _reserve_base_age() -> int:
	return day_count - reserve_base_purchase_day + 1


## 購入分が「傷んでいる」日か（表示のみ。判定には効かない）。
func is_reserve_base_damaged() -> bool:
	if reserve_base_purchase_remaining <= 0:
		return false
	var age := _reserve_base_age()
	return age >= SPOIL_DAMAGED_DAY and age < SPOIL_DISCARD_DAY


## 購入分の未使用の残りが腐りきっていれば捨てる（初期分は残す）。捨てたら true。
## discard_spoiled_inventory() と同じく、PREPに入る瞬間に1回だけ呼ぶ。
func discard_spoiled_reserve_base() -> bool:
	if reserve_base_purchase_remaining <= 0 or _reserve_base_age() < SPOIL_DISCARD_DAY:
		return false
	reserve_base_units = maxi(reserve_base_units - reserve_base_purchase_remaining, 0)
	reserve_base_purchase_remaining = 0
	return true


## 今日の共有鍋を作る入口。SET_SOUP Event を受けた側から呼ぶ（STEP 12）。
## 形は STEP 11 で決めた { base_id, tags[] } ＋ 残量（7.6）。apply_money / add_inventory と
## 同じく「soup をいじる唯一の入口」を用意し、受け側から soup へ直接代入させない。
## tags は複製して持つ（データ側の配列を共有して後から書き換わるのを防ぐ）。
## 7.6: 残量に加えて濃さ（1〜5）と、今夜使える水の回数も持つ。
## 予備ベースは soup ではなく GameState 直下（翌日へ持ち越すため）。
func set_soup(base_id: String, tags: Array, servings: int = 0,
		strength: int = 3, water_doses: int = 0) -> void:
	soup = { "base_id": base_id, "tags": tags.duplicate(),
		"remaining_servings": servings,
		"strength": clampi(strength, STRENGTH_MIN, STRENGTH_MAX),
		"water_doses": water_doses }


## 鍋から取り分けた分だけ残量を減らす入口（DESIGN.md 7.6）。
## apply_money と同じ方針で、受け側から soup を直接触らせない。
## 0未満にはならないようクランプする（廃棄機能の追加時に決定：「残量-2杯」のような
## 見た目の不自然さを避けるため。尽きた後に何度でも廃棄できてしまう点はあえて許容する
## ＝稀なケースなので今は気にしない、という判断）。
func consume_soup(servings: int) -> void:
	if soup == null:
		return
	soup["remaining_servings"] = maxi(int(soup.get("remaining_servings", 0)) - servings, 0)


## 鍋を濃くする（DESIGN.md 7.6：時間帯が進むと煮詰まる）。上限で頭打ち。
## 残量は動かさない（蒸発は入れない仕様）。
func deepen_soup(delta: int = 1) -> void:
	if soup == null:
		return
	soup["strength"] = clampi(int(soup.get("strength", 3)) + delta,
		STRENGTH_MIN, STRENGTH_MAX)


## 水を足せるか（鍋があり、今夜の水がまだ残っているか）。
func can_add_water() -> bool:
	return soup != null and int(soup.get("water_doses", 0)) > 0


## ベースを足せるか（鍋があり、予備ベースが1回分以上あるか）。
func can_add_base() -> bool:
	return soup != null and reserve_base_units >= BASE_UNITS_PER_ADD


## 水を一回足す（DESIGN.md 7.6）。残量 +2 / 濃さ -1 / 水の回数 -1。
## apply_money のような「量は受け側が決める」形にしないのは、
## 「資源を1つ消費する」ことと「2つの数値が動く」ことが常にセットで、
## 分けて呼べると壊せてしまうため（複合操作を1つの入口にまとめる）。
## 資源が足りなければ黙って何もしない（UI側でもボタンを無効化して二重に防ぐ）。
func add_water() -> void:
	if not can_add_water():
		return
	soup["remaining_servings"] = int(soup.get("remaining_servings", 0)) + WATER_SERVINGS
	soup["strength"] = clampi(int(soup.get("strength", 3)) - 1, STRENGTH_MIN, STRENGTH_MAX)
	soup["water_doses"] = int(soup.get("water_doses", 0)) - 1


## ベースを足す（DESIGN.md 7.6）。**残量は変えず**濃さ +1 / 予備ベース -2単位。
## 出汁の素を足しても量は増えない（増やせるのは水だけ）。
## add_water と同じく複合操作を1つの入口にまとめる。
func add_base() -> void:
	if not can_add_base():
		return
	soup["strength"] = clampi(int(soup.get("strength", 3)) + 1, STRENGTH_MIN, STRENGTH_MAX)
	# 古い（初期）分から先に使い、購入分（期限つき）は最後まで残す。
	if reserve_base_units - reserve_base_purchase_remaining < BASE_UNITS_PER_ADD:
		reserve_base_purchase_remaining -= BASE_UNITS_PER_ADD - (reserve_base_units - reserve_base_purchase_remaining)
	reserve_base_units -= BASE_UNITS_PER_ADD


## 提供実績を1件記録する。REACT で売上が確定したときに呼ぶ。
func record_served(record) -> void:
	served.append(record)


## 今日の場所代を払い終えたと記録する入口（apply_money 等と同じく、受け側から
## rent_paid_today を直接代入させない）。チンピラのPAY Event（kind:"rent"）が
## 実際に適用されたときと、閉店直前の特別請求が通ったときの両方から呼ぶ。
func mark_rent_paid() -> void:
	rent_paid_today = true
