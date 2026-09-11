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
enum Phase { WAKE, PREP, OPEN, CLOSE, NEXT_DAY }

# 一杯の売価（PRICING_SPEC.md：内容にかかわらず50固定）。
# 客ごとのデータではなくゲーム共通のルールなのでここに置く（is_collection_day() と同じ扱い）。
# 評価差は価格ではなく評判・翌日の客数へ反映する（高級具に追加料金は付けない）。
const PRICE_PER_SERVING := 50

# ベース1袋で作れる杯数（PRICING_SPEC.md 5章：1袋80＝10杯分）。
# 値段と同じくゲーム共通のルール。
const SERVINGS_PER_BASE := 10

# 鍋の操作の効き方（DESIGN.md 7.6「状態の変化」の表）。値をここに集約する。
const STRENGTH_MIN := 1            # 濃さの下限（水っぽい）
const STRENGTH_MAX := 5            # 濃さの上限（煮詰まりすぎ）
const WATER_DOSES_PER_NIGHT := 2   # 毎朝汲める水の回数（PRICING_SPEC 4章。持ち越さない）
const WATER_SERVINGS := 2          # 水1回： 残量 +2 / 濃さ -1
const BASE_SERVINGS := 2           # ベース追加：残量 +2 / 濃さ +1
const BASE_UNITS_PER_ADD := 2      # ベース追加1回で使う単位数（1袋＝10単位）

# --- 永続する事実 ---
var day_count: int = 1
var money: int = 300
var reputation: int = 0

# 初期具材・調味料・購入した食材。中身の型は Ingredient（後で定義）。
var inventory: Array = []

# スマホで得た情報の断片。中身の型は Rumor（後で定義）。
var rumors: Array = []

# 追加用ベースの単位数（1袋＝10単位。DESIGN.md 7.6「ベースと水の扱い」）。
# soup の中ではなくここに置く理由：**余った単位は翌日へ持ち越す**ので、
# NEXT_DAY で null になる soup に入れると消えてしまうため（寿命が違う）。
# 初期値は仮。PREP でベース2袋目を買う操作が未実装なので、最初から持たせている。
var reserve_base_units: int = 10

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


## 日次リセット。NEXT_DAY フェーズの処理から呼ぶ。
## soup と served だけをクリアする。money/reputation/inventory は残す。
func reset_for_new_day() -> void:
	soup = null
	served.clear()


## 日を1つ進める。reset_for_new_day() の後に呼ぶ想定。
func advance_day() -> void:
	day_count += 1


## 今日が場所代（みかじめ）の徴収日か。GameState は事実だけ持つのでここに置く。
## 7日版なので今は初日のみ。将来 day_count in [1, 7, 14] 等へ広げられる形にしておく。
func is_collection_day() -> bool:
	return day_count == 1


## 金額の増減をまとめて通す入口。
## 支払いも売上も同じここを通す（DESIGN.md「金額処理はすべて money -= x で同じ」）。
## 差はデータ側の text（トーン）で持ち、ここでは数値だけ扱う。
func apply_money(delta: int) -> void:
	money += delta


## 評判の増減をまとめて通す入口（DESIGN.md 7.6）。apply_money と同じ役割で、
## 「どれだけ動かすか」を決めるのは受け側、ここは適用するだけ。
## 名前あり客とモブで増加量が違う（受け側の増減表で決める）。
func apply_reputation(delta: int) -> void:
	reputation += delta


## 在庫に item を count 個足す入口。ADD_ITEM Event を受けた側から呼ぶ。
## apply_money と同じく「在庫をいじる唯一の入口」を用意し、受け側から
## inventory 配列を直接触らせない。中身は今は id 文字列。Ingredient 型が
## 定義されたらここと表示側だけ差し替えれば済む。
func add_inventory(item, count: int = 1) -> void:
	for _i in count:
		inventory.append(item)


## 在庫から item を count 個抜く入口。add_inventory の裏返し。
## 該当が無い分は黙って無視する（Array.erase は未ヒットでも安全、size は負にならない）。
## STEP 4: 「仕込み」で具材を消費するのに使う。soup を埋める処理はまだ持たない。
func remove_inventory(item, count: int = 1) -> void:
	for _i in count:
		inventory.erase(item)


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
## 今の段階では 0 未満にもなる。尽きたときの選択（断る／薄めて出す）は後の段階なので、
## ここでは止めない。負の値が出れば「足りないのに出した」と計器盤で見えるので、
## 次の段階を作るときの入口としてむしろ有用。
func consume_soup(servings: int) -> void:
	if soup == null:
		return
	soup["remaining_servings"] = int(soup.get("remaining_servings", 0)) - servings


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


## ベースを足す（DESIGN.md 7.6）。残量 +2 / 濃さ +1 / 予備ベース -2単位。
## add_water と同じく複合操作を1つの入口にまとめる。
func add_base() -> void:
	if not can_add_base():
		return
	soup["remaining_servings"] = int(soup.get("remaining_servings", 0)) + BASE_SERVINGS
	soup["strength"] = clampi(int(soup.get("strength", 3)) + 1, STRENGTH_MIN, STRENGTH_MAX)
	reserve_base_units -= BASE_UNITS_PER_ADD


## 提供実績を1件記録する。REACT で売上が確定したときに呼ぶ。
func record_served(record) -> void:
	served.append(record)
